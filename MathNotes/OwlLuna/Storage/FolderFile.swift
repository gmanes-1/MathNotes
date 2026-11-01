import Foundation

struct FolderEntry: Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var clothRaw: String
    var createdAt: Date
    var sortIndex: Int
    /// The folder this one sits inside. Older builds keep the key and show the folder at the top level.
    var parentID: UUID?
    var extra: [String: JSONValue] = [:]
    var undecoded: [String: UndecodedField] = [:]

    var cloth: ClothColor {
        get { ClothColor(rawValue: clothRaw) ?? .slate }
        set { clothRaw = newValue.rawValue }
    }
}

extension FolderEntry {
    /// What sync settles one at a time for a folder both sides have.
    enum Field: String, CaseIterable, Sendable {
        case name, cloth, parent, sortIndex
    }

    /// When each of those was last changed. Older builds keep the stamps as an unknown key; an entry from before them has none.
    func changedAt(_ field: Field) -> Date? {
        extra["changedAt"]?[field.rawValue]?.stringValue.flatMap(ManifestCodec.parseDate)
    }

    mutating func setChangedAt(_ date: Date?, for field: Field) {
        var stamps = extra["changedAt"]?.objectValue ?? [:]
        stamps[field.rawValue] = date.map(ManifestCodec.encodeDate)
        extra["changedAt"] = stamps.isEmpty ? nil : .object(stamps)
    }

    func holds(_ field: Field, like other: FolderEntry) -> Bool {
        switch field {
        case .name: name == other.name
        case .cloth: clothRaw == other.clothRaw
        case .parent: parentID == other.parentID
        case .sortIndex: sortIndex == other.sortIndex
        }
    }

    fileprivate mutating func copy(_ field: Field, from other: FolderEntry) {
        switch field {
        case .name: name = other.name
        case .cloth: clothRaw = other.clothRaw
        case .parent: parentID = other.parentID
        case .sortIndex: sortIndex = other.sortIndex
        }
    }

    /// The folder as both sides should have it, one field at a time: whichever was changed last, or the newer file's
    /// when neither says. A stamp never moves backwards.
    static func settled(newer: FolderEntry, older: FolderEntry) -> FolderEntry {
        var result = newer
        for field in Field.allCases {
            guard let olderAt = older.changedAt(field), olderAt > (newer.changedAt(field) ?? .distantPast) else { continue }
            if !newer.holds(field, like: older) { result.copy(field, from: older) }
            result.setChangedAt(olderAt, for: field)
        }
        return result
    }
}

/// `Library/folders.json`, the durable list of folders the index is rebuilt from.
struct FolderFile: Sendable, Hashable {
    var folders: [FolderEntry] = []
    var opaque: [JSONValue] = []
    /// Names the list in the synced copy. One that replaces a damaged list has a new name, which tells every other
    /// device that what it agreed on with the old one no longer holds.
    var listID: String?
    var extra: [String: JSONValue] = [:]

    /// A file that is there and isn't a folder list.
    struct Damaged: Error {}

    /// Nil when there is no file. One that is there and can't be read throws, and is left where it is: it is never
    /// taken for a list with no folders in it.
    static func load(_ root: StorageRoot) throws -> FolderFile? {
        let data: Data
        do {
            data = try Data(contentsOf: root.foldersFile)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        guard let file = FolderFile(data) else { throw Damaged() }
        return file
    }

    /// The folders, or none when there is no file or it can't be read.
    static func read(_ root: StorageRoot) -> FolderFile {
        (try? load(root)) ?? FolderFile()
    }

    func encoded() throws -> Data {
        let encoded = folders.map { folder -> JSONValue in
            var writer = ObjectWriter(base: folder.extra, undecoded: folder.undecoded)
            writer.set("id", .string(folder.id.uuidString))
            writer.set("name", .string(folder.name))
            writer.set("cloth", .string(folder.clothRaw))
            writer.set("createdAt", ManifestCodec.encodeDate(folder.createdAt))
            writer.set("sortIndex", .number(Double(folder.sortIndex)))
            if let parent = folder.parentID { writer.set("parent", .string(parent.uuidString)) }
            return .object(writer.values)
        }
        var values = extra
        values["folders"] = .array(encoded + opaque)
        values["listID"] = listID.map(JSONValue.string)
        return try JSONValue.object(values).serialized()
    }

    /// A damaged file this replaces is set aside as `folders.json.corrupt`, so it's kept and never overwritten.
    func write(_ root: StorageRoot) throws {
        try FileManager.default.createDirectory(at: root.library, withIntermediateDirectories: true)
        if let existing = try? Data(contentsOf: root.foldersFile), FolderFile(existing) == nil { try Quarantine.move(root.foldersFile) }
        try encoded().write(to: root.foldersFile, options: .atomic)
    }

    /// Takes the changes the app made to its folders between `before` and `after`, stamping each field it changed after
    /// any stamp the file already has for it. A folder it didn't touch stays as the file has it, so one a sync brought
    /// in meanwhile isn't lost.
    mutating func apply(from before: [FolderEntry], to after: [FolderEntry], at date: Date) {
        let previous = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = Set(after.map(\.id))
        folders.removeAll { previous[$0.id] != nil && !kept.contains($0.id) }
        for entry in after {
            guard let old = previous[entry.id] else {
                if !folders.contains(where: { $0.id == entry.id }) { folders.append(entry) }
                continue
            }
            guard let index = folders.firstIndex(where: { $0.id == entry.id }) else { continue }
            for field in FolderEntry.Field.allCases where !entry.holds(field, like: old) {
                let seen = folders[index].changedAt(field)
                folders[index].copy(field, from: entry)
                folders[index].setChangedAt(LibraryState.stamp(after: seen, at: date), for: field)
            }
        }
        // Kept in sidebar order, as the app numbers it.
        folders = folders.enumerated().sorted { ($0.element.sortIndex, $0.offset) < ($1.element.sortIndex, $1.offset) }.map(\.element)
    }

    mutating func upsert(_ folder: FolderEntry) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) { folders[index] = folder } else { folders.append(folder) }
    }
}

extension FolderFile {
    init?(_ data: Data) {
        guard var top = (try? JSONValue.parse(data))?.objectValue, let values = top.removeValue(forKey: "folders")?.arrayValue else { return nil }
        listID = top.removeValue(forKey: "listID")?.stringValue
        extra = top
        for raw in values {
            guard let object = raw.objectValue,
                  let id = object["id"]?.stringValue.flatMap(UUID.init(uuidString:)),
                  let name = object["name"]?.stringValue else {
                opaque.append(raw)
                continue
            }
            var reader = ObjectReader(object)
            _ = reader.take("id")
            _ = reader.take("name")
            let cloth = reader.string("cloth", default: ClothColor.slate.rawValue)
            let createdAt = reader.date("createdAt", default: .now)
            let sortIndex = reader.int("sortIndex", default: folders.count)
            let parent = reader.take("parent")?.stringValue.flatMap(UUID.init(uuidString:))
            folders.append(FolderEntry(id: id, name: name, clothRaw: cloth, createdAt: createdAt, sortIndex: sortIndex, parentID: parent,
                                       extra: reader.remaining, undecoded: reader.undecoded))
        }
    }
}
