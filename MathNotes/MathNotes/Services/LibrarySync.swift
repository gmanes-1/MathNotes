import Foundation
import os

/// The synced copy of the library: the app's iCloud container on a device, or any folder in tests.
/// The library the app works in always stays on the device; syncing copies whole notebooks to and from this folder.
struct CloudFolder: Sendable, Hashable {
    let url: URL
    /// True for a real iCloud container, whose files may still need downloading before they can be read.
    var isUbiquitous = false

    var library: URL { url.appending(path: "Library", directoryHint: .isDirectory) }
    var stickers: URL { url.appending(path: "Stickers", directoryHint: .isDirectory) }
    var tombstones: URL { url.appending(path: "Deleted", directoryHint: .isDirectory) }
    var foldersFile: URL { library.appending(path: "folders.json") }
    /// A random ID naming this synced copy, so a device can tell an erased or different copy from the one it knows.
    var copyFile: URL { url.appending(path: "copy-id") }

    func package(_ id: UUID) -> URL {
        library.appending(path: "\(id.uuidString).\(StorageRoot.packageExtension)", directoryHint: .isDirectory)
    }

    func tombstone(_ id: UUID) -> URL { tombstones.appending(path: id.uuidString) }

    static let uploadExtension = "uploading"

    /// Where a notebook new to the synced copy is assembled before it is moved into place. No listing takes it for a notebook.
    func upload(_ id: UUID) -> URL {
        library.appending(path: "\(id.uuidString)-\(UUID().uuidString).\(Self.uploadExtension)", directoryHint: .isDirectory)
    }
}

/// What a delete marker says was deleted: the notebook's page date, and when it was last moved into or out of
/// Recently Deleted. A marker from an older build is empty and says neither.
struct DeleteMarker: Sendable, Equatable {
    var modifiedAt: Date?
    var trashStamp: Date?
    /// The delete was held back with others and then let go, so another device doesn't hold it again.
    var confirmed = false

    init(modifiedAt: Date? = nil, trashStamp: Date? = nil, confirmed: Bool = false) {
        self.modifiedAt = modifiedAt
        self.trashStamp = trashStamp
        self.confirmed = confirmed
    }

    init(_ data: Data) {
        let json = try? JSONValue.parse(data)
        modifiedAt = json?["modifiedAt"]?.stringValue.flatMap(ManifestCodec.parseDate)
        trashStamp = json?["trashStamp"]?.stringValue.flatMap(ManifestCodec.parseDate)
        confirmed = json?["confirmed"]?.boolValue ?? false
    }

    func encoded() throws -> Data {
        var values: [String: JSONValue] = [:]
        if let modifiedAt { values["modifiedAt"] = ManifestCodec.encodeDate(modifiedAt) }
        if let trashStamp { values["trashStamp"] = ManifestCodec.encodeDate(trashStamp) }
        if confirmed { values["confirmed"] = .bool(true) }
        return try JSONValue.object(values).serialized()
    }

    /// Whether the marker is for this version of a notebook: the same pages, and not taken back out of Recently
    /// Deleted since. Nil for a marker that doesn't say.
    func covers(_ notebook: (modifiedAt: Date, library: LibraryState)) -> Bool? {
        guard let modifiedAt else { return nil }
        return abs(notebook.modifiedAt.timeIntervalSince(modifiedAt)) < 0.002 && !notebook.library.wasRestored(since: trashStamp)
    }
}

/// What this device and the synced copy agreed on last time, kept on the device. It is what tells a notebook that was
/// deleted elsewhere from one that was never uploaded, and a change made here from one made there.
struct SyncState: Sendable, Equatable {
    /// Each notebook's modification date when it was last in step.
    var notebooks: [UUID: Date] = [:]
    /// Each notebook's Recently Deleted stamp at that time, which tells a restore made elsewhere since from none.
    var trashStamps: [UUID: Date] = [:]
    var folders: Set<UUID> = []
    /// Which folder list `folders` was agreed with. Nil from before lists were named, or with no list yet.
    var folderList: String?
    var stickers: Set<String> = []
    /// Which synced copy all of that was agreed with.
    var copy: String?
    /// A marker for the Apple Account it was synced under. It says nothing about the account but whether it is the same one.
    var account: String?

    static func file(_ root: StorageRoot) -> URL { root.url.appending(path: "sync-state.json") }

    var holdsAnything: Bool { !notebooks.isEmpty || !folders.isEmpty || !stickers.isEmpty }

    /// Nothing is agreed any more, so the next pass only adds: what is missing on either side is copied, never deleted.
    mutating func startAgain() {
        notebooks = [:]
        trashStamps = [:]
        folders = []
        folderList = nil
        stickers = []
        copy = nil
    }

    mutating func agree(on id: UUID, _ notebook: (modifiedAt: Date, library: LibraryState)) {
        notebooks[id] = notebook.modifiedAt
        trashStamps[id] = notebook.library.changedAt(.deleted)
    }

    mutating func forget(_ id: UUID) {
        notebooks[id] = nil
        trashStamps[id] = nil
    }

    static func read(_ root: StorageRoot) -> SyncState {
        guard let data = try? Data(contentsOf: file(root)), let json = try? JSONValue.parse(data) else { return SyncState() }
        var state = SyncState()
        for (key, value) in json["notebooks"]?.objectValue ?? [:] {
            if let id = UUID(uuidString: key), let date = value.stringValue.flatMap(ManifestCodec.parseDate) { state.notebooks[id] = date }
        }
        for (key, value) in json["trashStamps"]?.objectValue ?? [:] {
            if let id = UUID(uuidString: key), let date = value.stringValue.flatMap(ManifestCodec.parseDate) { state.trashStamps[id] = date }
        }
        state.folders = Set(json["folders"]?.arrayValue?.compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) } ?? [])
        state.folderList = json["folderList"]?.stringValue
        state.stickers = Set(json["stickers"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        state.copy = json["copy"]?.stringValue
        state.account = json["account"]?.stringValue
        return state
    }

    func write(_ root: StorageRoot) throws {
        var values: [String: JSONValue] = [
            "notebooks": .object(Dictionary(uniqueKeysWithValues: notebooks.map { ($0.key.uuidString, ManifestCodec.encodeDate($0.value)) })),
            "trashStamps": .object(Dictionary(uniqueKeysWithValues: trashStamps.map { ($0.key.uuidString, ManifestCodec.encodeDate($0.value)) })),
            "folders": .array(folders.map { .string($0.uuidString) }.sorted { ($0.stringValue ?? "") < ($1.stringValue ?? "") }),
            "stickers": .array(stickers.sorted().map(JSONValue.string)),
        ]
        if let folderList { values["folderList"] = .string(folderList) }
        if let copy { values["copy"] = .string(copy) }
        if let account { values["account"] = .string(account) }
        try JSONValue.object(values).serialized().write(to: Self.file(root), options: .atomic)
    }
}

struct SyncReport: Sendable, Equatable {
    /// Notebooks sent to the synced copy, and notebooks brought in from it.
    var pushed: [UUID] = []
    var pulled: [UUID] = []
    /// Notebooks taken out of the library here because they were deleted on another device: into Recently Deleted, or
    /// for good when they were in it already. And notebooks removed from the synced copy because they were deleted here.
    var removedHere: [UUID] = []
    var removedThere: [UUID] = []
    /// Notebooks changed on two devices since they last agreed: the older version was kept as a copy under this new ID.
    var conflictCopies: [UUID] = []
    /// Notebooks left for next time: busy here (open, opening, saving, a change waiting), or not all down from iCloud yet.
    var open: [UUID] = []
    var arriving: [UUID] = []
    /// Notebooks that couldn't be copied, each with why. Every pass tries them again.
    var failed: [SyncFailure] = []
    /// Notebooks gone from one side that weren't taken as deleted, since too many went at once.
    var held: [UUID] = []
    /// The synced copy's folder list is there and can't be read, so the folders were left as they are on both sides.
    var foldersUnreadable = false
    /// Notebooks whose lock, favourite, folder, tags, Recently Deleted date or journal mark was brought in or sent, their pages untouched.
    var stateReceived: [UUID] = []
    var stateSent: [UUID] = []
    /// Notebooks whose flashcards took cards, answers or deletions from the other side.
    var cardsReceived: [UUID] = []
    var cardsSent: [UUID] = []
    var foldersChanged = false
    var stickersChanged = false
    /// The synced copy wasn't the one this device knew (erased, or another account's), so nothing was taken as deleted.
    var startedAgain = false

    /// Every notebook the pass left as it was.
    var waiting: [UUID] { open + arriving + failed.map(\.id) + held }

    var changedHere: Bool {
        !pulled.isEmpty || !removedHere.isEmpty || !conflictCopies.isEmpty || !stateReceived.isEmpty || !cardsReceived.isEmpty || foldersChanged || stickersChanged
    }

    /// Adds what the pass run straight after this one did. What is left is what that pass left.
    mutating func add(_ next: SyncReport) {
        pushed += next.pushed
        pulled += next.pulled
        removedHere += next.removedHere
        removedThere += next.removedThere
        conflictCopies += next.conflictCopies
        open = next.open
        arriving = next.arriving
        failed = next.failed
        held = next.held
        foldersUnreadable = next.foldersUnreadable
        stateReceived += next.stateReceived
        stateSent += next.stateSent
        cardsReceived += next.cardsReceived
        cardsSent += next.cardsSent
        foldersChanged = foldersChanged || next.foldersChanged
        stickersChanged = stickersChanged || next.stickersChanged
        startedAgain = startedAgain || next.startedAgain
    }
}

/// What a pass did with the folders: whether it changed them here, and which both sides now have, in which list.
struct FolderPass: Sendable, Equatable {
    var changedHere: Bool
    var agreed: Set<UUID>
    var list: String?
    /// The synced list can't be read: nothing was written, and what was agreed stands.
    var unreadableThere = false
}

/// A notebook a pass couldn't copy, and why.
struct SyncFailure: Sendable, Hashable {
    enum Reason: Sendable, Hashable {
        /// There is no room left on this device.
        case noRoom
        /// Its manifest is there and won't read: the copy in iCloud, or the one here.
        case unreadable(inICloud: Bool)
        /// Saved by a newer version of MathNotes, which this one mustn't change.
        case newerVersion
        /// iCloud Drive wouldn't hand over the files.
        case coordination(String)
        case other(String)
    }

    let id: UUID
    let reason: Reason
}

extension SyncFailure.Reason {
    init(_ error: any Error) {
        if let error = error as? CoordinationError {
            self = Self.isOutOfSpace(error.underlying) ? .noRoom : .coordination(error.underlying.localizedDescription)
        } else if Self.isOutOfSpace(error as NSError) {
            self = .noRoom
        } else if error as? PackageError == .readOnly {
            self = .newerVersion
        } else if error as? PackageError == .unreadable {
            // Only a pull finds a manifest it can't read, in what it brought down from iCloud.
            self = .unreadable(inICloud: true)
        } else {
            self = .other(error.localizedDescription)
        }
    }

    private static func isOutOfSpace(_ error: NSError) -> Bool {
        (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError)
            || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC))
            || (error.userInfo[NSUnderlyingErrorKey] as? NSError).map(isOutOfSpace) == true
    }
}

/// What a file coordinator said when it wouldn't let the synced copy's files be read or written.
struct CoordinationError: Error {
    let underlying: NSError
}

/// A pass that stopped part-way: what it had done by then, which is kept as agreed, and why it stopped.
struct StoppedPass: Error {
    let report: SyncReport
    let reason: any Error
}

enum SyncError: LocalizedError {
    case stillArriving
    /// The Apple Account signed in is no longer the one the pass began with. `SyncCenter` looks again; it is never shown.
    case accountChanged

    var errorDescription: String? {
        switch self {
        case .stillArriving: String(localized: "iCloud is still downloading your library. Sync will try again shortly.")
        case .accountChanged: nil
        }
    }
}

extension LibraryState {
    /// Whether two copies file the notebook alike: favourite, lock, folder, tags, Recently Deleted and the journal mark.
    func agrees(with other: LibraryState) -> Bool {
        Filing.allCases.allSatisfy { files($0, like: other) }
    }

    /// Whether the notebook was taken back out of Recently Deleted after `stamp`, which is all a delete made then knew of.
    func wasRestored(since stamp: Date?) -> Bool {
        guard deletedAt == nil, let changed = changedAt(.deleted) else { return false }
        return changed.timeIntervalSince(stamp ?? .distantPast) > 0.0005
    }

    /// Whether this copy lacks something `wanted` holds: an item filed differently, or stamped later.
    func trails(_ wanted: LibraryState) -> Bool {
        Filing.allCases.contains { !files($0, like: wanted) || (changedAt($0) ?? .distantPast) < (wanted.changedAt($0) ?? .distantPast) }
    }

    private mutating func take(_ filing: Filing, from other: LibraryState) {
        switch filing {
        case .favorite: isFavorite = other.isFavorite
        case .locked: isLocked = other.isLocked
        case .folder: folderID = other.folderID
        case .tags: tags = other.tags
        case .deleted: deletedAt = other.deletedAt
        case .journal: isJournal = other.isJournal
        }
        setChangedAt(other.changedAt(filing), for: filing)
    }

    /// Takes on how another copy files the notebook. Where it was left off reading stays this copy's own, and an
    /// item both file alike keeps the later stamp, so a stamp never moves backwards.
    mutating func adopt(_ other: LibraryState) {
        for filing in Filing.allCases {
            if !files(filing, like: other) {
                take(filing, from: other)
            } else if let theirs = other.changedAt(filing), theirs > (changedAt(filing) ?? .distantPast) {
                setChangedAt(theirs, for: filing)
            }
        }
    }

    /// What both copies should hold, settled one item at a time: whichever was changed last, or this device's when
    /// neither says. A lock from before changes were stamped is kept whichever side has it, and pages `written` in
    /// unseen by whoever deleted a notebook take it back out of Recently Deleted. Nil when neither copy lacks anything.
    static func settled(here: LibraryState, there: LibraryState, written: (here: Bool, there: Bool) = (false, false), now: Date) -> LibraryState? {
        var result = here
        for filing in Filing.allCases {
            let hereAt = here.changedAt(filing), thereAt = there.changedAt(filing)
            guard !here.files(filing, like: there) else {
                if let thereAt, thereAt > (hereAt ?? .distantPast) { result.setChangedAt(thereAt, for: filing) }
                continue
            }
            var takesThere = (thereAt ?? .distantPast) > (hereAt ?? .distantPast)
            if filing == .locked, hereAt == nil, thereAt == nil { takesThere = there.isLocked }
            let kept = takesThere ? there : here, other = takesThere ? here : there
            if filing == .deleted, kept.deletedAt != nil, other.deletedAt == nil, takesThere ? written.here : written.there {
                // Stamped after the delete it overrules, so every device takes the same answer.
                result.deletedAt = nil
                result.setChangedAt(stamp(after: kept.changedAt(.deleted), at: now), for: .deleted)
                continue
            }
            if takesThere { result.take(filing, from: there) }
            // A tie is stamped now, so the other devices take this answer and don't each give their own.
            if hereAt == thereAt { result.stampChange(filing, at: now) }
        }
        return here.trails(result) || there.trails(result) ? result : nil
    }
}

/// Brings this device's library and the synced copy into step, one notebook at a time. Pages aren't merged: the newer
/// version wins, and when both sides changed since they last agreed the older is kept as a copy, so a sync never loses
/// writing. Flashcards are merged card by card, apart from the pages.
enum LibrarySync {
    private static let log = Logger(subsystem: "com.owais.MathNotes", category: "sync")

    /// When a notebook was last changed, read straight from its manifest.
    static func stamp(ofPackage url: URL) -> Date? { glance(ofPackage: url)?.modifiedAt }

    /// How a notebook is filed, read straight from its manifest.
    static func filing(ofPackage url: URL) -> LibraryState? { glance(ofPackage: url)?.library }

    /// The two things a pass decides on, from one read of the manifest: when the pages changed, and how the notebook is filed.
    private static func glance(ofPackage url: URL) -> (modifiedAt: Date, library: LibraryState)? {
        guard let data = try? Data(contentsOf: url.appending(path: "manifest.json")), let json = try? JSONValue.parse(data),
              let modifiedAt = json["modifiedAt"]?.stringValue.flatMap(ManifestCodec.parseDate) else { return nil }
        return (modifiedAt, ManifestCodec.decodeLibrary(json["library"]?.objectValue ?? [:]))
    }

    /// Rewrites how a notebook is filed and nothing else. Returns false for a manifest this version mustn't write.
    private static func refile(_ id: UUID, as library: LibraryState, inPackage url: URL) throws -> Bool {
        let manifestURL = url.appending(path: "manifest.json")
        var manifest = try ManifestCodec.decode(Data(contentsOf: manifestURL), fallbackID: id).manifest
        guard !manifest.isNewerThanSupported else { return false }
        manifest.library.adopt(library)
        try ManifestCodec.encode(manifest).write(to: manifestURL, options: .atomic)
        return true
    }

    /// Whether a file is in the synced copy. One still on its way down from iCloud is waited for.
    private static func isPresent(_ url: URL) throws -> Bool {
        let fileManager = FileManager.default
        let placeholder = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud")
        guard !fileManager.fileExists(atPath: placeholder.path(percentEncoded: false)) else { throw SyncError.stillArriving }
        return fileManager.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// A file in the synced copy, nil when there is none. One that is there but can't be read yet, or is still on
    /// its way down from iCloud, is waited for and never taken as missing.
    private static func contents(of url: URL) throws -> Data? {
        guard try isPresent(url) else { return nil }
        guard let data = try? Data(contentsOf: url) else { throw SyncError.stillArriving }
        return data
    }

    /// Whether a file in the synced copy is all there, downloaded, and still can't be read as a manifest.
    private static func isDamaged(_ url: URL) -> Bool {
        let placeholder = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud")
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: placeholder.path(percentEncoded: false)),
              fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return false }
        let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
        return status == nil || status == .current
    }

    /// The synced copy's ID, nil when it has none.
    private static func copyID(in cloud: CloudFolder) throws -> String? {
        guard let data = try contents(of: cloud.copyFile) else { return nil }
        let id = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    /// Whether the synced copy holds nothing at all: no notebooks, folders, stickers or deletions.
    private static func isEmpty(_ cloud: CloudFolder) -> Bool {
        [cloud.library, cloud.stickers, cloud.tombstones].allSatisfy {
            ((try? FileManager.default.contentsOfDirectory(atPath: $0.path(percentEncoded: false))) ?? []).isEmpty
        }
    }

    /// Clears away pulls and new notebooks a quit left half-assembled beside the library. One touched since `cutoff` is still under way.
    static func sweepArriving(root: StorageRoot, untouchedSince cutoff: Date = .now) {
        let fileManager = FileManager.default
        for url in (try? fileManager.contentsOfDirectory(at: root.arriving, includingPropertiesForKeys: [.attributeModificationDateKey])) ?? [] {
            let touched = (try? url.resourceValues(forKeys: [.attributeModificationDateKey]))?.attributeModificationDate ?? .distantPast
            if touched < cutoff { try? fileManager.removeItem(at: url) }
        }
    }

    /// Clears away uploads a quit cut short. One begun within the hour may be another device's, still under way.
    private static func sweepUploads(in cloud: CloudFolder, now: Date) {
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(at: cloud.library, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in contents where url.pathExtension == CloudFolder.uploadExtension {
            let begun = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(begun) > 3600 { try? coordinated(writing: url) { try fileManager.removeItem(at: $0) } }
        }
    }

    /// Whether a synced package was left by an upload cut short: it has no manifest, and none is on its way down.
    private static func isCutShort(_ package: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: package.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        return !["manifest.json", ".manifest.json.icloud"].contains { fileManager.fileExists(atPath: package.appending(path: $0).path(percentEncoded: false)) }
    }

    private static func same(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.timeIntervalSince(b)) < 0.002
    }

    private static func packageIDs(in directory: URL) throws -> Set<UUID> {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return Set(contents.compactMap { url -> UUID? in
            // A notebook that hasn't been downloaded yet is listed as ".<name>.icloud".
            var name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") { name = String(name.dropFirst().dropLast(7)) }
            guard name.hasSuffix(".\(StorageRoot.packageExtension)") else { return nil }
            return UUID(uuidString: String(name.dropLast(StorageRoot.packageExtension.count + 1)))
        })
    }

    /// More notebooks than this gone in one pass, or most of a library when more than one is, looks like something gone
    /// wrong rather than deletes. Notebooks in Recently Deleted don't count.
    static let deletesAtOnce = 3

    static func isTooManyToDelete(_ count: Int, of library: Int) -> Bool {
        count > deletesAtOnce || (count > 1 && count * 2 > library)
    }

    /// Whether a notebook gone from here was deleted here: it was here and in step, and nobody has written in it or restored it since.
    private static func wasDeletedHere(_ remote: (modifiedAt: Date, library: LibraryState), agreed: Date?, trashStamp: Date?) -> Bool {
        guard let agreed else { return false }
        return same(remote.modifiedAt, agreed) && !remote.library.wasRestored(since: trashStamp)
    }

    /// Whether a marker carries a delete to the notebook here: it is for this version, and not over a restore made since.
    private static func carries(_ marker: DeleteMarker?, to local: (modifiedAt: Date, library: LibraryState), agreed: Date?) -> Bool {
        guard let marker, agreed != nil else { return false }
        return marker.covers(local) ?? same(local.modifiedAt, agreed)
    }

    /// Whether a notebook gone from here only ran out of this device's Recently Deleted, and is in the synced copy's,
    /// unchanged, from a time another device may still be keeping it.
    private static func expiredOnlyHere(_ id: UUID, _ remote: (modifiedAt: Date, library: LibraryState), agreed: Date?,
                                        expired: ExpiredTrash, now: Date) -> Bool {
        guard expired.notebooks[id] != nil, let agreed, same(remote.modifiedAt, agreed), let trashed = remote.library.deletedAt else { return false }
        return ExpiredTrash.mayBeKeptElsewhere(deletedAt: trashed, now: now)
    }

    /// Whether the notebook here went into Recently Deleted after the one the marker's delete knew of: for that delete, or since.
    private static func isTrashedSince(_ local: LibraryState, _ marker: DeleteMarker?) -> Bool {
        guard local.deletedAt != nil, let stamp = local.changedAt(.deleted) else { return false }
        return stamp.timeIntervalSince(marker?.trashStamp ?? .distantPast) > 0.0005
    }

    /// `take` asks for a notebook just before it is handled, so one opened in an editor since the pass began is still
    /// left alone, and `release` hands it back. `account` marks the Apple Account the synced copy belongs to, kept with
    /// what was agreed; `signedIn`, when given, says which is signed in now, and the pass stops once that isn't it.
    /// `keeping` are notebooks a pass held back that are wanted after all: nothing is taken as deleted for them, so
    /// they come back wherever they're gone. `lettingGo` are ones whose deletes were meant: they aren't held again,
    /// and go as a single delete would. The folders are settled inside `holdingFolders`, which a library uses to
    /// keep its own folder writes from interleaving with the pass's. `replacingFolders` puts this device's folders
    /// in place of a synced list that can't be read.
    static func run(root: StorageRoot, cloud: CloudFolder, account: String? = nil, now: Date = .now, keeping: Set<UUID> = [], lettingGo: Set<UUID> = [],
                    replacingFolders: Bool = false,
                    take: @Sendable (UUID) async -> Bool = { _ in true }, release: @Sendable (UUID) async -> Void = { _ in },
                    holdingFolders: @Sendable (@escaping @Sendable () throws -> FolderPass?) async throws -> FolderPass? = { try $0() },
                    signedIn: (@Sendable () -> String?)? = nil) async throws -> SyncReport {
        let fileManager = FileManager.default
        func checkStillWanted() throws {
            try Task.checkCancellation()
            if let signedIn, signedIn() != account { throw SyncError.accountChanged }
        }
        try checkStillWanted()
        for directory in [root.library, cloud.library, cloud.tombstones] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // Notebooks with files iCloud still hadn't brought down when the wait ran out.
        let stillComing = await cloud.isUbiquitous ? CloudFiles.download(cloud.url) : CloudFiles.pending(in: cloud.url)
        let arriving = Set(stillComing.compactMap { url in
            url.pathComponents.first { $0.hasSuffix(".\(StorageRoot.packageExtension)") }.flatMap { UUID(uuidString: String($0.dropLast(StorageRoot.packageExtension.count + 1))) }
        })
        try checkStillWanted()
        var state = SyncState.read(root)
        var report = SyncReport()
        if let account, state.account != account {
            // Kept before anything is copied, so a pass that is cut short still knows whose copy it began with.
            state.account = account
            try state.write(root)
        }
        // What was agreed holds only for the copy it was agreed with. With an erased copy, or another account's,
        // something missing there was never deleted: this pass starts again and only adds.
        let copy = try copyID(in: cloud)
        // Looked at before anything is copied, so a pass that has to wait for the folders changes nothing.
        _ = try contents(of: cloud.foldersFile)
        if let known = state.copy {
            if known != copy {
                state.startAgain()
                report.startedAgain = true
            }
        } else if copy == nil, state.holdsAnything, isEmpty(cloud) {
            // A state from before copies were named can only tell an erased copy by its being empty.
            state.startAgain()
            report.startedAgain = true
        } else if copy != nil {
            // Nor can it tell a copy erased and filled again by another device, where a missing folder or sticker was never deleted.
            state.folders = []
            state.stickers = []
        }
        if let copy {
            state.copy = copy
        } else {
            // The fresh start is saved first: once the copy has a name, a state without one is taken to have agreed with it.
            if report.startedAgain { try state.write(root) }
            let made = UUID().uuidString
            try coordinated(writing: cloud.copyFile) { try Data(made.utf8).write(to: $0, options: .atomic) }
            state.copy = made
        }
        for id in keeping { state.forget(id) }
        sweepUploads(in: cloud, now: now)
        let here = Set(try root.listPackageIDs()), there = try packageIDs(in: cloud.library)
        // Read after the packages are listed: it is written before an expired one goes.
        let expired = ExpiredTrash.read(root)
        let deleted = Set(((try? fileManager.contentsOfDirectory(atPath: cloud.tombstones.path(percentEncoded: false))) ?? []).compactMap(UUID.init(uuidString:)))
        func deleteMarker(_ id: UUID) throws -> DeleteMarker? {
            guard deleted.contains(id), let data = try contents(of: cloud.tombstone(id)) else { return nil }
            return DeleteMarker(data)
        }
        // Counted before anything is touched: notebooks out of Recently Deleted that this pass would take out of the
        // library, less those already let go here or on the device that marked them.
        var vanishing: [UUID] = []
        for (id, agreed) in state.notebooks where !lettingGo.contains(id) {
            switch (here.contains(id), there.contains(id)) {
            case (false, true):
                if let remote = glance(ofPackage: cloud.package(id)), remote.library.deletedAt == nil,
                   wasDeletedHere(remote, agreed: agreed, trashStamp: state.trashStamps[id]) { vanishing.append(id) }
            case (true, false):
                if let local = glance(ofPackage: root.package(id)), local.library.deletedAt == nil,
                   let marker = try? deleteMarker(id), !marker.confirmed, carries(marker, to: local, agreed: agreed) { vanishing.append(id) }
            default:
                break
            }
        }
        let held = isTooManyToDelete(vanishing.count, of: here.union(there).count) ? Set(vanishing) : []

        do {
            for id in here.union(there).union(state.notebooks.keys).sorted(by: { $0.uuidString < $1.uuidString }) {
                try checkStillWanted()
                if held.contains(id) {
                    report.held.append(id)
                    continue
                }
                guard await take(id) else { report.open.append(id); continue }
                notebook: do {
                    let isHere = here.contains(id)
                    let local = isHere ? glance(ofPackage: root.package(id)) : nil
                    // An upload cut short left a package no device can read. With the notebook here, it is sent again.
                    let isThere = there.contains(id) && !(local != nil && isCutShort(cloud.package(id)))
                    let remote = isThere ? glance(ofPackage: cloud.package(id)) : nil
                    let agreed = state.notebooks[id]
                    if (isHere && local == nil) || (isThere && remote == nil) {
                        // One still on its way down is waited for, one that is there and won't read is damaged: neither goes over a good one.
                        if isHere && local == nil {
                            report.failed.append(SyncFailure(id: id, reason: .unreadable(inICloud: false)))
                        } else if isDamaged(cloud.package(id).appending(path: "manifest.json")) {
                            report.failed.append(SyncFailure(id: id, reason: .unreadable(inICloud: true)))
                        } else {
                            report.arriving.append(id)
                        }
                        break notebook
                    }
                    if let remote, arriving.contains(id), !same(remote.modifiedAt, local?.modifiedAt), !same(remote.modifiedAt, agreed) {
                        // A version iCloud is still bringing down is read once all of it has arrived, not part-way.
                        report.arriving.append(id)
                        break notebook
                    }
                    switch (local, remote) {
                    case (let local?, let remote?):
                        // Cards first, so whichever way the pages go they carry every card from both sides.
                        let cards = try settleCards(id, root: root, cloud: cloud)
                        if cards.here { report.cardsReceived.append(id) }
                        if cards.there { report.cardsSent.append(id) }
                        // The pages go by their date. How the notebook is filed is settled apart from them, so a pull
                        // never takes a lock off and a favourite never counts as an edit.
                        let inStep = same(local.modifiedAt, remote.modifiedAt)
                        let unchangedHere = inStep || (agreed != nil && same(local.modifiedAt, agreed))
                        let unchangedThere = inStep || (agreed != nil && same(remote.modifiedAt, agreed))
                        let wanted = LibraryState.settled(here: local.library, there: remote.library, written: (!unchangedHere, !unchangedThere), now: now)
                        var hereHolds = local.library, thereHolds = remote.library
                        // A marker beside a version it wasn't made for would mislead a new device: writing or a restore overrules it.
                        if let marker = try deleteMarker(id), !inStep || marker.covers((remote.modifiedAt, wanted ?? remote.library)) == false {
                            try? fileManager.removeItem(at: cloud.tombstone(id))
                        }
                        if inStep {
                            state.notebooks[id] = local.modifiedAt
                        } else if unchangedHere {
                            try pull(id, from: cloud, into: root, filedAs: wanted)
                            hereHolds = wanted ?? remote.library
                            state.notebooks[id] = remote.modifiedAt
                            report.pulled.append(id)
                        } else if unchangedThere {
                            try push(id, from: root, to: cloud)
                            thereHolds = local.library
                            state.notebooks[id] = local.modifiedAt
                            report.pushed.append(id)
                        } else {
                            // Both sides changed. The older version is kept as a notebook of its own first; once that is
                            // done the newer goes through like any other change, and can be tried again if it fails.
                            let remoteIsNewer = remote.modifiedAt > local.modifiedAt
                            let copy = try keepCopy(of: id, fromSyncedCopy: !remoteIsNewer, locked: local.library.isLocked || remote.library.isLocked,
                                                    root: root, cloud: cloud)
                            report.conflictCopies.append(copy)
                            state.notebooks[id] = remoteIsNewer ? local.modifiedAt : remote.modifiedAt
                            // Saved at once, so a pass cut short from here on doesn't find the conflict again and copy it twice.
                            try state.write(root)
                            if remoteIsNewer {
                                try pull(id, from: cloud, into: root, filedAs: wanted)
                                hereHolds = wanted ?? remote.library
                                state.notebooks[id] = remote.modifiedAt
                                report.pulled.append(id)
                            } else {
                                try push(id, from: root, to: cloud)
                                thereHolds = local.library
                                state.notebooks[id] = local.modifiedAt
                                report.pushed.append(id)
                            }
                        }
                        if let wanted {
                            // A stamp raised with nothing filed differently isn't a change worth reporting.
                            if hereHolds.trails(wanted), try refile(id, as: wanted, inPackage: root.package(id)), !hereHolds.agrees(with: wanted) {
                                report.stateReceived.append(id)
                            }
                            if thereHolds.trails(wanted) {
                                var sent = false
                                try coordinated(writing: cloud.package(id)) { sent = try refile(id, as: wanted, inPackage: $0) }
                                if sent, !thereHolds.agrees(with: wanted) { report.stateSent.append(id) }
                            }
                        }
                        state.trashStamps[id] = (wanted ?? remote.library).changedAt(.deleted)
                    case (let local?, nil):
                        // A marker carries a delete only to the version it was made for, and not over a restore made since.
                        let marker = try deleteMarker(id)
                        if carries(marker, to: local, agreed: agreed) {
                            if local.library.deletedAt == nil {
                                // Out of Recently Deleted here, it goes in there rather than for good. Stamped after the
                                // delete, so the next pass leaves it be.
                                var trashed = local.library
                                trashed.deletedAt = now
                                trashed.setChangedAt(LibraryState.stamp(after: marker?.trashStamp, at: now), for: .deleted)
                                guard try refile(id, as: trashed, inPackage: root.package(id)) else { throw PackageError.readOnly }
                                report.removedHere.append(id)
                            } else if !isTrashedSince(local.library, marker) {
                                try remove(root.package(id), root: root)
                                state.forget(id)
                                report.removedHere.append(id)
                            }
                        } else {
                            // New here, or changed here after it was deleted elsewhere: writing wins over a delete.
                            try? fileManager.removeItem(at: cloud.tombstone(id))
                            try push(id, from: root, to: cloud)
                            state.agree(on: id, local)
                            report.pushed.append(id)
                        }
                    case (nil, let remote?) where expiredOnlyHere(id, remote, agreed: agreed, expired: expired, now: now):
                        // Another device may keep Recently Deleted longer, and still have it there.
                        break
                    case (nil, let remote?):
                        if let agreed, same(remote.modifiedAt, agreed), !remote.library.wasRestored(since: state.trashStamps[id]) {
                            // It was here and in step, it's gone, and nobody has written in it or restored it since: it was deleted on this device.
                            try DeleteMarker(modifiedAt: remote.modifiedAt, trashStamp: remote.library.changedAt(.deleted), confirmed: lettingGo.contains(id))
                                .encoded().write(to: cloud.tombstone(id), options: .atomic)
                            try coordinated(writing: cloud.package(id)) { try fileManager.removeItem(at: $0) }
                            state.forget(id)
                            report.removedThere.append(id)
                        } else if agreed == nil, let marker = try deleteMarker(id), marker.covers(remote) ?? true {
                            try coordinated(writing: cloud.package(id)) { try fileManager.removeItem(at: $0) }
                        } else {
                            // New there, or written in or restored there since this device last saw it: that wins over a delete.
                            try? fileManager.removeItem(at: cloud.tombstone(id))
                            try pull(id, from: cloud, into: root)
                            state.agree(on: id, remote)
                            report.pulled.append(id)
                        }
                    case (nil, nil):
                        state.forget(id)
                    }
                } catch SyncError.stillArriving {
                    report.arriving.append(id)
                } catch {
                    log.error("sync of \(id) failed: \(error.localizedDescription)")
                    report.failed.append(SyncFailure(id: id, reason: SyncFailure.Reason(error)))
                }
                await release(id)
            }

            try checkStillWanted()
            let agreedFolders = state.folders, agreedList = state.folderList
            if let folders = try await holdingFolders({
                try syncFolders(root: root, cloud: cloud, agreed: agreedFolders, list: agreedList, replacing: replacingFolders)
            }) {
                report.foldersChanged = folders.changedHere
                report.foldersUnreadable = folders.unreadableThere
                state.folders = folders.agreed
                state.folderList = folders.list
            }
            report.stickersChanged = try syncStickers(root: root, cloud: cloud, state: &state)
        } catch {
            // What was done before the pass stopped is kept as agreed, and handed back so the library hears of it.
            try? state.write(root)
            throw StoppedPass(report: report, reason: error)
        }
        try state.write(root)
        return report
    }

    // MARK: Copying notebooks

    /// Thumbnails are made again where they're needed, and a file set aside as damaged stays on the device it was found on.
    private static func travels(_ relative: String) -> Bool {
        !relative.hasPrefix("thumbs/") && relative != "thumbs" && !relative.contains(".corrupt")
    }

    /// A file iCloud hasn't brought down yet is listed under its real name, at its placeholder.
    private static func files(in package: URL) -> [String: URL] {
        var result: [String: URL] = [:]
        let base = package.standardizedFileURL.path(percentEncoded: false)
        let enumerator = FileManager.default.enumerator(at: package, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            var relative = String(url.standardizedFileURL.path(percentEncoded: false).dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let name = CloudFiles.placeholderTarget(url.lastPathComponent) {
                relative = String(relative.dropLast(url.lastPathComponent.count)) + name
                if result[relative] != nil { continue }
            }
            if travels(relative) { result[relative] = url }
        }
        return result
    }

    /// A copy keeps its original's modification date, so a file of the same size written at the same instant is the
    /// same file. The manifests are small and decide everything, so they are always copied.
    private static func unchanged(_ relative: String, _ a: URL, _ b: URL) -> Bool {
        guard !relative.hasPrefix("manifest") else { return false }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let first = try? a.resourceValues(forKeys: keys), let second = try? b.resourceValues(forKeys: keys),
              let written = first.contentModificationDate, let copied = second.contentModificationDate else { return false }
        return first.fileSize == second.fileSize && abs(written.timeIntervalSince(copied)) < 0.000_002
    }

    /// Makes `destination` hold what `source` holds: files that differ are copied, files that are gone are removed
    /// unless `kept`, and the manifest goes last so a reader never sees it name ink that hasn't arrived.
    private static func mirror(_ source: URL, to destination: URL, keeping kept: (String) -> Bool = { _ in false }) throws {
        let wanted = files(in: source), present = files(in: destination)
        for (relative, url) in wanted.sorted(by: { ($0.key == "manifest.json" ? 1 : 0, $0.key) < ($1.key == "manifest.json" ? 1 : 0, $1.key) }) {
            guard CloudFiles.placeholderTarget(url.lastPathComponent) == nil else { throw SyncError.stillArriving }
            if let existing = present[relative], CloudFiles.placeholderTarget(existing.lastPathComponent) == nil, unchanged(relative, url, existing) { continue }
            try copy(url, over: destination.appending(path: relative))
        }
        for (relative, url) in present where wanted[relative] == nil && !kept(relative) { try? FileManager.default.removeItem(at: url) }
    }

    /// Copies one file over another, keeping its date, so `unchanged` takes the two for the same file afterwards.
    private static func copy(_ source: URL, over target: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staged = target.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).part")
        try fileManager.copyItem(at: source, to: staged)
        _ = try fileManager.replaceItemAt(target, withItemAt: staged)
    }

    private static func coordinated(writing url: URL, _ work: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { granted in
            do { try work(granted) } catch { failure = error }
        }
        if let coordinationError { throw CoordinationError(underlying: coordinationError) }
        if let failure { throw failure }
    }

    private static func coordinated(reading url: URL, _ work: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { granted in
            do { try work(granted) } catch { failure = error }
        }
        if let coordinationError { throw CoordinationError(underlying: coordinationError) }
        if let failure { throw failure }
    }

    /// A notebook new to the synced copy is assembled under another name and moved in whole, so an upload cut
    /// short never leaves a package without its manifest for every device to wait on.
    private static func push(_ id: UUID, from root: StorageRoot, to cloud: CloudFolder) throws {
        let fileManager = FileManager.default, target = cloud.package(id)
        guard !fileManager.fileExists(atPath: target.path(percentEncoded: false)) else {
            return try coordinated(writing: target) { try mirror(root.package(id), to: $0) }
        }
        let staging = cloud.upload(id)
        do {
            try coordinated(writing: staging) { try mirror(root.package(id), to: $0) }
            try coordinated(writing: target) { try fileManager.moveItem(at: staging, to: $0) }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// The notebook is assembled beside the library and swapped in whole, so a pull that stops halfway changes nothing.
    /// `library` is how it should be filed once here, when that isn't how the synced copy files it.
    private static func pull(_ id: UUID, from cloud: CloudFolder, into root: StorageRoot, filedAs library: LibraryState? = nil) throws {
        let fileManager = FileManager.default
        let staging = root.arriving.appending(path: "\(id.uuidString)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let target = root.package(id)
        if fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
            // Starting from what is here means only the pages that changed are copied.
            try fileManager.copyItem(at: target, to: staging)
        }
        // A clipping made here for a card not yet written stays; the cards file clears away ones no card names.
        try coordinated(reading: cloud.package(id)) { try mirror($0, to: staging, keeping: { $0.hasPrefix("cards/") }) }
        guard stamp(ofPackage: staging) != nil else { throw PackageError.unreadable }
        guard isWhole(staging) else { throw SyncError.stillArriving }
        if let library { _ = try refile(id, as: library, inPackage: staging) }
        try? fileManager.removeItem(at: staging.appending(path: "thumbs"))
        try fileManager.setAttributes([.modificationDate: Date.now], ofItemAtPath: staging.appending(path: "manifest.json").path(percentEncoded: false))
        if fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(target, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: target)
        }
    }

    /// What a pull of one notebook found: nothing newer in the synced copy (or nothing it can settle alone, which a pass
    /// does), the newer version brought in, or a newer version left there because this device wrote in it too or `take` said no.
    enum Newer: Sendable, Equatable { case none, pulled, waiting }

    /// Brings one notebook's newer version in without a whole pass, when nothing was written in it here since the two
    /// last agreed. iCloud has up to `timeout` to bring it down; `take` is asked just before it is swapped in.
    static func pullNewer(_ id: UUID, root: StorageRoot, cloud: CloudFolder, timeout: Duration, now: Date = .now,
                          take: @Sendable (UUID) async -> Bool = { _ in true }, release: @Sendable (UUID) async -> Void = { _ in }) async throws -> Newer {
        try Task.checkCancellation()
        let package = cloud.package(id)
        if cloud.isUbiquitous { _ = await CloudFiles.download(package, timeout: timeout) }
        var state = SyncState.read(root)
        // One never agreed on, a copy this device doesn't know, or a delete marker is for a pass to settle.
        guard let agreed = state.notebooks[id], let known = state.copy, try copyID(in: cloud) == known, !(try isPresent(cloud.tombstone(id))),
              let local = glance(ofPackage: root.package(id)), let remote = glance(ofPackage: package),
              !same(remote.modifiedAt, agreed), !same(remote.modifiedAt, local.modifiedAt) else { return .none }
        guard same(local.modifiedAt, agreed), await take(id) else { return .waiting }
        do {
            // Saved here while it was being taken: a pass keeps both.
            guard let taken = glance(ofPackage: root.package(id)), same(taken.modifiedAt, agreed) else {
                await release(id)
                return .waiting
            }
            _ = try settleCards(id, root: root, cloud: cloud)
            let wanted = LibraryState.settled(here: taken.library, there: remote.library, written: (false, true), now: now)
            try pull(id, from: cloud, into: root, filedAs: wanted)
            state.notebooks[id] = remote.modifiedAt
            state.trashStamps[id] = (wanted ?? remote.library).changedAt(.deleted)
            try state.write(root)
        } catch SyncError.stillArriving {
            await release(id)
            return .none
        } catch {
            await release(id)
            throw error
        }
        await release(id)
        return .pulled
    }

    /// Whether a package holds each page's ink as its manifest hashes it, and every asset it names: iCloud may bring the manifest down first.
    private static func isWhole(_ package: URL) -> Bool {
        let fileManager = FileManager.default
        func exists(_ relative: String) -> Bool { fileManager.fileExists(atPath: package.appending(path: relative).path(percentEncoded: false)) }
        guard let data = try? Data(contentsOf: package.appending(path: "manifest.json")),
              let manifest = try? ManifestCodec.decode(data, fallbackID: UUID()).manifest else { return true }
        for page in manifest.pages {
            guard let hash = page.inkHash else {
                if exists(page.inkFile) { return false }
                continue
            }
            guard let ink = try? Data(contentsOf: package.appending(path: page.inkFile), options: .mappedIfSafe), NotebookPackage.hash(ink) == hash else { return false }
        }
        let assets = manifest.pages.compactMap(\.background.assetFile) + manifest.recordings.flatMap { [$0.file] + [$0.transcriptFile].compactMap { $0 } }
        return assets.allSatisfy { exists("assets/\($0)") }
    }

    private static func remove(_ package: URL, root: StorageRoot) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root.deleting, withIntermediateDirectories: true)
        let tombstone = root.deleting.appending(path: "\(package.deletingPathExtension().lastPathComponent)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.moveItem(at: package, to: tombstone)
        try? fileManager.removeItem(at: tombstone)
    }

    /// The older version in a conflict is kept here as a notebook of its own, which the next pass uploads like any new
    /// one. It is assembled beside the library and moved in whole, so a copy is never left half-made. Returns its ID.
    /// A notebook locked on either side has a locked copy.
    private static func keepCopy(of id: UUID, fromSyncedCopy: Bool, locked: Bool, root: StorageRoot, cloud: CloudFolder) throws -> UUID {
        let fileManager = FileManager.default
        let copy = UUID()
        let staging = root.arriving.appending(path: "\(copy.uuidString)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root.arriving, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        if fromSyncedCopy {
            try coordinated(reading: cloud.package(id)) { try mirror($0, to: staging) }
            guard isWhole(staging) else { throw SyncError.stillArriving }
        } else {
            try fileManager.copyItem(at: root.package(id), to: staging)
        }
        let manifestURL = staging.appending(path: "manifest.json")
        var manifest = try ManifestCodec.decode(Data(contentsOf: manifestURL), fallbackID: id).manifest
        guard !manifest.isNewerThanSupported else { throw PackageError.readOnly }
        manifest.id = copy
        manifest.title = String(localized: "\(manifest.title) (conflicted copy)")
        manifest.library.isFavorite = false
        manifest.library.isJournal = false
        if locked { manifest.library.isLocked = true }
        try ManifestCodec.encode(manifest).write(to: manifestURL, options: .atomic)
        try CardFiles.renew(in: staging)
        try fileManager.moveItem(at: staging, to: root.package(copy))
        return copy
    }

    // MARK: Flashcards

    /// A notebook's cards are settled one at a time and apart from its pages, so cards made or answered on either side
    /// are all kept, and a card deleted on one stays deleted. Clippings go before the cards that name them. A file this
    /// version can't read or mustn't write is left to go with its pages. Returns which sides took something.
    private static func settleCards(_ id: UUID, root: StorageRoot, cloud: CloudFolder) throws -> (here: Bool, there: Bool) {
        let fileManager = FileManager.default
        let herePackage = root.package(id), therePackage = cloud.package(id)
        let hereFile = CardFiles.file(in: herePackage), thereFile = CardFiles.file(in: therePackage)
        if unchanged(hereFile.lastPathComponent, hereFile, thereFile) { return (false, false) }
        let hereData = fileManager.fileExists(atPath: hereFile.path(percentEncoded: false)) ? try Data(contentsOf: hereFile) : nil
        let thereData = try contents(of: thereFile)
        guard hereData != thereData else { return (false, false) }
        func deck(_ data: Data?) -> CardFiles.Deck? {
            guard let data else { return CardFiles.Deck() }
            return CardFiles.deck(from: data).flatMap { $0.isReadOnly ? nil : $0 }
        }
        guard let here = deck(hereData), let there = deck(thereData) else { return (false, false) }
        let merged = here.merged(with: there)
        let changesHere = merged != here, changesThere = merged != there
        if changesHere {
            try coordinated(reading: therePackage) { package in
                for name in merged.clippings where !fileManager.fileExists(atPath: CardFiles.imageURL(name, in: herePackage).path(percentEncoded: false)) {
                    if try isPresent(CardFiles.imageURL(name, in: package)) { try copy(CardFiles.imageURL(name, in: package), over: CardFiles.imageURL(name, in: herePackage)) }
                }
            }
            if changesThere {
                try CardFiles.write(merged, to: herePackage)
            } else {
                try coordinated(reading: thereFile) { try copy($0, over: hereFile) }
            }
        }
        if changesThere {
            try coordinated(writing: therePackage) { package in
                for name in merged.clippings where !fileManager.fileExists(atPath: CardFiles.imageURL(name, in: package).path(percentEncoded: false)) {
                    let clipping = CardFiles.imageURL(name, in: herePackage)
                    if fileManager.fileExists(atPath: clipping.path(percentEncoded: false)) { try copy(clipping, over: CardFiles.imageURL(name, in: package)) }
                }
                // The file goes over as it is here, so the next pass finds the two the same without reading them.
                try copy(hereFile, over: CardFiles.file(in: package))
            }
        }
        return (changesHere, changesThere)
    }

    // MARK: Folders and stickers

    /// A three-way merge on which folders exist: one added on either side is kept, one deleted on either side goes.
    /// A folder both sides have is settled field by field, each by when it was last changed. Either list being there
    /// and unreadable is waited for: nothing is written, and nothing is taken as deleted. Nil when it is this one.
    /// `replacing` puts a new list made from this device's folders in place of a synced one that can't be read,
    /// and keeps the damaged one aside here.
    private static func syncFolders(root: StorageRoot, cloud: CloudFolder, agreed: Set<UUID>, list: String?, replacing: Bool) throws -> FolderPass? {
        let local: FolderFile
        do {
            local = try FolderFile.load(root) ?? FolderFile()
        } catch {
            log.error("folders here can't be read: \(error.localizedDescription)")
            return nil
        }
        var remote = FolderFile(), isThere = false, replaced = false
        if let data = try contents(of: cloud.foldersFile) {
            isThere = true
            if let file = FolderFile(data) {
                remote = file
            } else if replacing {
                let aside = root.library.appending(path: "icloud-folders.json")
                try data.write(to: aside, options: .atomic)
                try Quarantine.move(aside)
                replaced = true
            } else {
                // Not written over unasked: a folder only that list holds would then be taken as deleted on every other device.
                log.error("folders in the synced copy can't be read")
                return FolderPass(changedHere: false, agreed: agreed, list: list, unreadableThere: true)
            }
        }
        // A list other than the one agreed with, made again or named since, says nothing of what was deleted: this pass only adds.
        let agreed = !replaced && remote.listID == list ? agreed : []
        func modified(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        let localIsNewer = modified(root.foldersFile) >= modified(cloud.foldersFile)
        let localByID = Dictionary(local.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteByID = Dictionary(remote.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var merged: [FolderEntry] = []
        for id in (localIsNewer ? local.folders + remote.folders : remote.folders + local.folders).map(\.id) where !merged.contains(where: { $0.id == id }) {
            let wasAgreed = agreed.contains(id)
            switch (localByID[id], remoteByID[id]) {
            case (let here?, let there?): merged.append(localIsNewer ? .settled(newer: here, older: there) : .settled(newer: there, older: here))
            case (let here?, nil): if !wasAgreed { merged.append(here) }
            case (nil, let there?): if !wasAgreed { merged.append(there) }
            case (nil, nil): break
            }
        }
        let ids = Set(merged.map(\.id))
        merged = merged.map { entry in
            var entry = entry
            if let parent = entry.parentID, !ids.contains(parent) { entry.parentID = nil }
            return entry
        }
        var changedHere = false
        if merged != local.folders {
            var file = local
            file.folders = merged
            try file.write(root)
            changedHere = true
        }
        if merged != remote.folders || (remote.listID == nil && (isThere || !merged.isEmpty)) {
            var file = remote
            file.folders = merged
            file.listID = file.listID ?? UUID().uuidString
            let data = try file.encoded()
            try coordinated(writing: cloud.foldersFile) { try data.write(to: $0, options: .atomic) }
            remote = file
        }
        return FolderPass(changedHere: changedHere, agreed: ids, list: remote.listID)
    }

    private static func syncStickers(root: StorageRoot, cloud: CloudFolder, state: inout SyncState) throws -> Bool {
        let fileManager = FileManager.default
        // A sticker iCloud has evicted, or not brought down yet, is still there, listed as ".<name>.icloud".
        func names(_ directory: URL) -> Set<String> {
            Set(((try? fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []).map { CloudFiles.placeholderTarget($0) ?? $0 }.filter { $0.hasSuffix(".png") })
        }
        func placeholder(_ name: String) -> URL? {
            let url = cloud.stickers.appending(path: ".\(name).icloud")
            return fileManager.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
        }
        let here = names(root.stickers), there = names(cloud.stickers)
        var changedHere = false
        for name in here.union(there) {
            let agreed = state.stickers.contains(name)
            switch (here.contains(name), there.contains(name)) {
            case (true, false):
                if agreed {
                    try? fileManager.removeItem(at: root.stickers.appending(path: name))
                    changedHere = true
                } else {
                    try fileManager.createDirectory(at: cloud.stickers, withIntermediateDirectories: true)
                    try coordinated(writing: cloud.stickers.appending(path: name)) { try fileManager.copyItem(at: root.stickers.appending(path: name), to: $0) }
                }
            case (false, true):
                if agreed {
                    try coordinated(writing: placeholder(name) ?? cloud.stickers.appending(path: name)) { try fileManager.removeItem(at: $0) }
                } else if placeholder(name) == nil {
                    try fileManager.createDirectory(at: root.stickers, withIntermediateDirectories: true)
                    try fileManager.copyItem(at: cloud.stickers.appending(path: name), to: root.stickers.appending(path: name))
                    changedHere = true
                }
            default:
                break
            }
        }
        state.stickers = names(root.stickers).intersection(names(cloud.stickers))
        return changedHere
    }
}

/// Getting files in an iCloud container onto the device before they are read.
enum CloudFiles {
    /// The real name of a file iCloud lists as ".<name>.icloud" until it is downloaded, nil for any other file.
    static func placeholderTarget(_ name: String) -> String? {
        name.hasPrefix(".") && name.hasSuffix(".icloud") && name.count > 8 ? String(name.dropFirst().dropLast(7)) : nil
    }

    /// Files under `url` that aren't on the device yet: placeholders, and items iCloud says aren't downloaded.
    static func pending(in url: URL) -> [URL] {
        var result: [URL] = []
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey], options: [])
        while let item = enumerator?.nextObject() as? URL {
            if let name = placeholderTarget(item.lastPathComponent) {
                result.append(item.deletingLastPathComponent().appending(path: name))
            } else if (try? item.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus == .notDownloaded {
                result.append(item)
            }
        }
        return result
    }

    /// Asks for everything under `url` to be downloaded and waits, up to `timeout`, for it to arrive. Returns what hadn't by then.
    static func download(_ url: URL, timeout: Duration = .seconds(60)) async -> [URL] {
        let deadline = ContinuousClock.now + timeout
        var waiting = pending(in: url)
        while !waiting.isEmpty, ContinuousClock.now < deadline, !Task.isCancelled {
            for item in waiting { try? FileManager.default.startDownloadingUbiquitousItem(at: item) }
            try? await Task.sleep(for: .milliseconds(500))
            waiting = pending(in: url)
        }
        return waiting
    }
}
