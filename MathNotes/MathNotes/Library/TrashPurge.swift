import Foundation

/// How long Recently Deleted keeps a notebook on this device. Each device keeps to its own.
enum TrashLength: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, season = 90
    var id: Int { rawValue }
    var days: Int { rawValue }

    static let initial = TrashLength.month
    /// No device keeps a notebook longer, so one deleted this long ago can go from every device.
    static let longest = TrashLength.season

    static func current(_ defaults: UserDefaults = .standard) -> TrashLength {
        TrashLength(rawValue: defaults.integer(forKey: SettingsKey.trashLength)) ?? .initial
    }

    var displayName: String { String(localized: "\(days) days") }

    /// Notebooks put in Recently Deleted before this have been there `days` days.
    static func cutoff(_ days: Int, now: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
    }
}

/// Notebooks this device's own Recently Deleted let go of, with when they went into it. Another device may keep
/// Recently Deleted longer, so a sync leaves their synced copy for it until no device keeps one that long.
struct ExpiredTrash: Sendable, Equatable {
    var notebooks: [UUID: Date] = [:]

    static func file(_ root: StorageRoot) -> URL { root.url.appending(path: "expired-trash.json") }

    /// Whether a device may still have a notebook put in Recently Deleted at `deletedAt` there.
    static func mayBeKeptElsewhere(deletedAt: Date, now: Date = .now) -> Bool {
        deletedAt >= TrashLength.cutoff(TrashLength.longest.days, now: now)
    }

    mutating func note(_ expired: [UUID: Date], now: Date = .now) {
        notebooks.merge(expired) { $1 }
        notebooks = notebooks.filter { Self.mayBeKeptElsewhere(deletedAt: $0.value, now: now) }
    }

    static func read(_ root: StorageRoot) -> ExpiredTrash {
        guard let data = try? Data(contentsOf: file(root)), let json = try? JSONValue.parse(data) else { return ExpiredTrash() }
        var expired = ExpiredTrash()
        for (key, value) in json["notebooks"]?.objectValue ?? [:] {
            if let id = UUID(uuidString: key), let date = value.stringValue.flatMap(ManifestCodec.parseDate) { expired.notebooks[id] = date }
        }
        return expired
    }

    func write(_ root: StorageRoot) throws {
        let values = Dictionary(uniqueKeysWithValues: notebooks.map { ($0.key.uuidString, ManifestCodec.encodeDate($0.value)) })
        try JSONValue.object(["notebooks": .object(values)]).serialized().write(to: Self.file(root), options: .atomic)
    }
}

/// Recently Deleted loses what is past its days once a launch, and after a sync when there is one to wait
/// for: a notebook restored on another device has to arrive before it is counted as still deleted here.
@MainActor
final class TrashPurge {
    private let library: LibraryStore
    private let sync: SyncCenter
    private let defaults: UserDefaults
    private var isDue = true

    init(library: LibraryStore, sync: SyncCenter, defaults: UserDefaults = .standard) {
        self.library = library
        self.sync = sync
        self.defaults = defaults
        sync.onSynced = { [weak self] in await self?.empty(skipping: $0.waiting) }
    }

    /// Called at launch, once the first sync has been tried.
    func launchSyncTried() async {
        // While iCloud is still being looked for, a pass may be about to follow.
        while sync.availability == .checking { try? await Task.sleep(for: .milliseconds(50)) }
        // With nothing to sync with there is nothing to wait for.
        if !sync.canSync { await empty() }
    }

    /// A new length counts from now, once a sync has had the chance to bring in a notebook restored elsewhere.
    func lengthChanged() async {
        isDue = true
        while sync.availability == .checking { try? await Task.sleep(for: .milliseconds(50)) }
        if sync.canSync { await sync.syncNow() } else { await empty() }
    }

    /// Notebooks the sync left waiting are kept: it couldn't tell whether another device restored them.
    private func empty(skipping waiting: [UUID] = []) async {
        guard isDue else { return }
        isDue = false
        await library.purgeExpiredTrash(olderThan: TrashLength.current(defaults).days, skipping: Set(waiting))
    }
}
