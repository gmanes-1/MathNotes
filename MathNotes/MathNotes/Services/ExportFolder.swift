import Foundation

/// The folders in tmp that exports and backups are written into, one each. A folder goes once the sheet offering it
/// has closed and every share or print of it has finished; what a quit left behind goes at the next launch.
enum ExportFolder {
    enum Kind: String, CaseIterable { case export, backup }

    /// What earlier versions wrote into a folder named only by a UUID, which a cancelled export left empty.
    private static let legacyExtensions: Set<String> = ["pdf", "png", "mp4"]
    @MainActor private static var readers: [URL: Int] = [:]
    @MainActor private static var discarded: Set<URL> = []

    static func make(_ kind: Kind, in parent: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let folder = parent.appending(path: "\(kind.rawValue)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A share or print of these files has begun: their folder stays until it ends.
    @MainActor static func beginReading(_ files: [URL]) {
        for folder in folders(of: files) { readers[folder, default: 0] += 1 }
    }

    @MainActor static func endReading(_ files: [URL]) {
        for folder in folders(of: files) {
            let left = (readers[folder] ?? 1) - 1
            readers[folder] = left > 0 ? left : nil
            if left <= 0, discarded.remove(folder) != nil { remove(folder) }
        }
    }

    /// Removes the folders these files were written into, now or once the last share or print of them has ended.
    @MainActor static func discard(_ files: [URL]) {
        for folder in folders(of: files) {
            if readers[folder] != nil { discarded.insert(folder) } else { remove(folder) }
        }
    }

    /// Removes the export and backup folders in `parent` made before `date`, and nothing else.
    @discardableResult
    static func sweep(_ parent: URL = FileManager.default.temporaryDirectory, madeBefore date: Date) -> Int {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var removed = 0
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: keys), values.isDirectory == true, values.isSymbolicLink != true,
                  let made = values.creationDate, made < date, isOurs(entry.lastPathComponent) || isLegacy(entry) else { continue }
            if (try? FileManager.default.removeItem(at: entry)) != nil { removed += 1 }
        }
        return removed
    }

    private static func isOurs(_ name: String) -> Bool {
        Kind.allCases.contains { name.hasPrefix("\($0.rawValue)-") && UUID(uuidString: String(name.dropFirst($0.rawValue.count + 1))) != nil }
    }

    private static func isLegacy(_ folder: URL) -> Bool {
        guard UUID(uuidString: folder.lastPathComponent) != nil,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return false }
        return files.allSatisfy {
            legacyExtensions.contains($0.pathExtension.lowercased()) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
    }

    private static func folders(of files: [URL]) -> Set<URL> {
        Set(files.map { $0.deletingLastPathComponent() }.filter { isOurs($0.lastPathComponent) })
    }

    private static func remove(_ folder: URL) {
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: folder) }
    }
}
