import Foundation
import Observation
import CryptoKit
import os

/// Runs the library's sync with iCloud: finds the container, decides when to sync, and tells the library what changed.
/// Nothing is copied until it has been allowed once on this device, and it is unavailable in a build without the
/// iCloud capability.
@MainActor
@Observable
final class SyncCenter {
    enum Availability: Equatable {
        case checking
        case unavailable(String)
        case available
    }

    /// What has to be answered before anything is copied.
    enum Question: Equatable {
        /// This device has never synced.
        case firstSync
        /// The Apple Account signed in isn't the one this library was last synced with.
        case accountChanged
    }

    private(set) var availability = Availability.checking
    private(set) var question: Question?
    private(set) var isSyncing = false
    /// When a pass last finished, kept across launches.
    private(set) var lastSynced: Date? {
        didSet { defaults.set(lastSynced, forKey: SettingsKey.lastSynced) }
    }
    private(set) var lastError: String?
    private(set) var lastReport: SyncReport?
    /// What iCloud still has to upload from the synced copy, as last looked at.
    private(set) var uploads = CloudUploads()
    /// What the library shows about sync: failures, and conflicted copies made since it was last put away.
    private(set) var news = SyncNews()
    /// The switch in Settings. It can be set while iCloud is unavailable, and takes effect once it isn't.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: SettingsKey.syncsWithICloud)
            guard isEnabled else {
                // Turning sync off is an answer to whatever was being asked.
                question = nil
                return halt()
            }
            Task {
                await review()
                schedule(after: .zero)
            }
        }
    }

    @ObservationIgnored private let root: StorageRoot
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let hadSynced: Bool
    @ObservationIgnored private var cloud: CloudFolder?
    @ObservationIgnored private var account: String?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var identityObserver: NSObjectProtocol?
    @ObservationIgnored private var wantsAnotherPass = false
    @ObservationIgnored private var running: Task<SyncReport, Error>?
    @ObservationIgnored private var reviewing = 0
    /// Pulls for an editor waiting or under way, and whether one is under way.
    @ObservationIgnored private var pulls = 0
    @ObservationIgnored private var isPulling = false
    @ObservationIgnored private var uploadCheck: Task<Void, Never>?
    @ObservationIgnored private var stopped: String?
    /// Conflicted copies the library hasn't shown yet, kept across launches so a quit doesn't lose them.
    @ObservationIgnored private var newCopies: [UUID] = [] {
        didSet { defaults.set(newCopies.map(\.uuidString), forKey: SettingsKey.syncConflictCopies) }
    }
    /// This device's journals that gave way to one begun earlier on another device, not yet shown.
    @ObservationIgnored private var setAsideJournals: [UUID] = [] {
        didSet { defaults.set(setAsideJournals.map(\.uuidString), forKey: SettingsKey.syncSetAsideJournals) }
    }
    @ObservationIgnored private var putAway = SyncNews()
    /// Notebooks a pass held back that were asked to be kept, which the next pass brings back.
    @ObservationIgnored private var keeping: Set<UUID> = []
    /// Notebooks a pass held back whose deletes were meant, which the next pass lets through.
    @ObservationIgnored private var lettingGo: Set<UUID> = []
    /// The folder list in iCloud that can't be read is to be made again from this device's, which the next pass does.
    @ObservationIgnored private var replacingFolders = false
    @ObservationIgnored private let log = Logger(subsystem: "com.owais.MathNotes", category: "sync")
    /// Reads what iCloud has still to upload. A test stands in for iCloud here.
    @ObservationIgnored var readUploads: @Sendable (CloudFolder) -> CloudUploads = { $0.isUbiquitous ? CloudUploads.read($0) : CloudUploads() }
    /// Called after a sync that changed the library on this device, so the index can be brought up to date. A pass
    /// that stopped part-way is reported too, with what it had done by then.
    @ObservationIgnored var onLibraryChanged: (@MainActor (SyncReport) async -> Void)?
    /// Called after every pass that finished, once the library has heard what it changed.
    @ObservationIgnored var onSynced: (@MainActor (SyncReport) async -> Void)?
    /// A pass takes each notebook in hand just before it touches it, and lets it go after. One that is open in an
    /// editor can't be taken, and is left for next time.
    @ObservationIgnored var take: @MainActor (UUID) -> Bool = { _ in true }
    @ObservationIgnored var release: @MainActor (UUID) -> Void = { _ in }
    /// A pass settles the folders inside this, which the library uses to keep its own folder writes out of the way.
    @ObservationIgnored var holdFolders: @MainActor (@escaping @Sendable () throws -> FolderPass?) async throws -> FolderPass? = { try $0() }

    init(root: StorageRoot, defaults: UserDefaults = .standard) {
        self.root = root
        self.defaults = defaults
        // A device that synced before there was a question to answer has already been syncing: it carries on.
        hadSynced = FileManager.default.fileExists(atPath: SyncState.file(root).path(percentEncoded: false))
        isEnabled = defaults.object(forKey: SettingsKey.syncsWithICloud) == nil ? hadSynced : defaults.bool(forKey: SettingsKey.syncsWithICloud)
        lastSynced = defaults.object(forKey: SettingsKey.lastSynced) as? Date
        newCopies = defaults.stringArray(forKey: SettingsKey.syncConflictCopies)?.compactMap(UUID.init(uuidString:)) ?? []
        setAsideJournals = defaults.stringArray(forKey: SettingsKey.syncSetAsideJournals)?.compactMap(UUID.init(uuidString:)) ?? []
        news.conflictCopies = newCopies
        news.journals = setAsideJournals
    }

    /// The library settled two journals that met, and this device's gave way: the notice says so until it is put away.
    func noteJournalSetAside(_ id: UUID) {
        guard !setAsideJournals.contains(id) else { return }
        setAsideJournals.append(id)
        refreshNews()
    }

    private var isDecided: Bool { hadSynced || defaults.object(forKey: SettingsKey.syncsWithICloud) != nil }

    /// Whether a pass may run: sync is on, the copy is found, and nothing is being asked or worked out.
    var canSync: Bool { isEnabled && question == nil && availability == .available && reviewing == 0 && cloud != nil }

    /// A marker for an Apple Account: a digest of the token iPadOS gives the app for it. It tells one account from
    /// another and nothing else.
    nonisolated static func marker(for token: (any NSCoding & NSCopying & NSObjectProtocol)?) -> String? {
        guard let token else { return nil }
        let data = (token as? NSData).map { $0 as Data } ?? (try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false))
        return data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
    }

    /// Finds where the synced copy lives. A test can stand a plain folder in for iCloud with `-cloudFolder <name>`,
    /// and a name in for the account with `-cloudAccount <name>`.
    func resolve() async {
        #if DEBUG
        if let name = LaunchOptions.value("-cloudFolder") {
            guard let url = LaunchOptions.testFolder(named: "cloud-\(name)") else { preconditionFailure("-cloudFolder takes a plain folder name, not \(name)") }
            if LaunchOptions.arguments.contains("-resetCloud") { try? FileManager.default.removeItem(at: url) }
            return await use(CloudFolder(url: url), account: LaunchOptions.value("-cloudAccount"))
        }
        #endif
        let signedOut = String(localized: "iCloud isn't available. Sign in to iCloud and turn on iCloud Drive in Settings; this copy of MathNotes also has to be built with the iCloud capability.")
        // A test's storage root never syncs with real iCloud.
        guard !LaunchOptions.usesTestStorage else { return leave(signedOut) }
        if identityObserver == nil {
            identityObserver = NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.identityChanged() }
            }
        }
        guard let token = FileManager.default.ubiquityIdentityToken else { return leave(signedOut) }
        let container = await Task.detached(priority: .utility) { FileManager.default.url(forUbiquityContainerIdentifier: nil) }.value
        guard let container else {
            return leave(String(localized: "This copy of MathNotes was built without the iCloud capability, so it can't sync."))
        }
        await use(CloudFolder(url: container.appending(path: "Sync", directoryHint: .isDirectory), isUbiquitous: true), account: Self.marker(for: token))
    }

    /// The synced copy has been found. What has to be asked first is worked out before sync is said to be
    /// available, so no pass touches the copy in between.
    func use(_ cloud: CloudFolder, account: String?) async {
        if cloud != self.cloud || account != self.account { halt() }
        availability = .checking
        self.cloud = cloud
        self.account = account
        await review()
        availability = .available
        if canSync { startWatching() }
    }

    private func leave(_ reason: String) {
        halt()
        cloud = nil
        account = nil
        question = nil
        availability = .unavailable(reason)
    }

    /// Signing out of iCloud, or in with another account, moves the container out from under the app. Nothing
    /// syncs until the account now signed in has been looked at.
    private func identityChanged() {
        halt()
        cloud = nil
        availability = .checking
        Task {
            await resolve()
            await syncNow()
        }
    }

    /// Works out what has to be asked. No pass starts while it does.
    private func review() async {
        guard cloud != nil else { return }
        reviewing += 1
        defer { reviewing -= 1 }
        let root = root
        let known = await Task.detached(priority: .utility) { SyncState.read(root).account }.value
        // Another account only matters while sync is on: with it off nothing is copied, and a refusal stands.
        if isEnabled, let account, let known, known != account {
            question = .accountChanged
        } else if !isDecided {
            question = .firstSync
        } else {
            question = nil
        }
    }

    /// The answer to `question`. Saying no turns sync off; turning it on again in Settings asks again while another
    /// account is still signed in.
    func answer(_ allowed: Bool) async {
        guard let asked = question else { return }
        guard allowed else {
            question = nil
            if isEnabled { isEnabled = false } else { defaults.set(false, forKey: SettingsKey.syncsWithICloud) }
            return
        }
        if asked == .accountChanged {
            // Only the marker moves. Whether what was agreed still holds is for the copy's own ID to say.
            let root = root, account = account
            await Task.detached(priority: .utility) {
                var state = SyncState.read(root)
                state.account = account
                try? state.write(root)
            }.value
        }
        question = nil
        if isEnabled {
            startWatching()
            await syncNow()
        } else {
            isEnabled = true
        }
    }

    /// Syncs a little later, so a burst of changes becomes one sync.
    func schedule(after delay: Duration = .seconds(4)) {
        guard canSync else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    func syncNow() async {
        guard canSync else { return }
        guard !isSyncing else { wantsAnotherPass = true; return }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            wantsAnotherPass = false
            var done: SyncReport?, failure: (any Error)?
            do {
                // A second pass uploads the copies a conflict left behind.
                guard let first = try await pass() else { break }
                done = first
                if !first.conflictCopies.isEmpty, let again = try await pass() { done?.add(again) }
            } catch let stopped as StoppedPass {
                if done == nil { done = stopped.report } else { done?.add(stopped.report) }
                failure = stopped.reason
            } catch {
                failure = error
            }
            if failure == nil {
                lastReport = done
                lastSynced = .now
                lastError = nil
                stopped = nil
            }
            newCopies += done?.conflictCopies ?? []
            // What a pass did before it stopped is on disk all the same, so the library hears of that as well.
            if let done, done.changedHere { await onLibraryChanged?(done) }
            switch failure {
            case nil:
                if let done { await onSynced?(done) }
                await checkUploads()
            case is CancellationError:
                // Stopped part-way because sync was turned off or the copy moved. Whoever stopped it decides what follows.
                break
            case let error? where error as? SyncError == .accountChanged:
                identityChanged()
            case let error?:
                lastError = error.localizedDescription
                // Waiting for iCloud to finish a download isn't something the library needs to hear about.
                stopped = error as? SyncError == .stillArriving ? nil : error.localizedDescription
                log.error("sync failed: \(error.localizedDescription)")
            }
            refreshNews()
        } while wantsAnotherPass
        if canSync { startWatching() }
    }

    /// One pass, or nil when sync may no longer run. That is asked before every pass, since the account may have
    /// changed or sync been turned off during the one before, and a ubiquitous pass asks the account again as it goes.
    private func pass() async throws -> SyncReport? {
        // A pull for an editor goes first: it is quick, and gives up after a few seconds.
        while pulls > 0 { try? await Task.sleep(for: .milliseconds(20)) }
        guard canSync, let cloud else { return nil }
        let root = root, account = account, keeping = keeping, lettingGo = lettingGo, replacing = replacingFolders
        let take = take, release = release, holdFolders = holdFolders
        let signedIn: @Sendable () -> String? = { SyncCenter.marker(for: FileManager.default.ubiquityIdentityToken) }
        let task = Task.detached(priority: .utility) {
            try await LibrarySync.run(root: root, cloud: cloud, account: account, keeping: keeping, lettingGo: lettingGo, replacingFolders: replacing,
                                      take: { await take($0) }, release: { await release($0) },
                                      holdingFolders: { try await holdFolders($0) }, signedIn: cloud.isUbiquitous ? signedIn : nil)
        }
        running = task
        defer { running = nil }
        do {
            let report = try await task.value
            self.keeping.subtract(keeping)
            // One the pass left for later is still let go when it comes back to it.
            self.lettingGo.subtract(lettingGo.subtracting(report.waiting))
            if replacing { replacingFolders = false }
            return report
        } catch let stopped as StoppedPass {
            // What was agreed was saved, kept notebooks and all.
            self.keeping.subtract(keeping)
            self.lettingGo.subtract(stopped.report.removedHere + stopped.report.removedThere)
            throw stopped
        }
    }

    /// The notebooks the last pass wouldn't take as deleted are wanted after all: the next pass brings them back
    /// wherever they're gone.
    func keepHeld() async {
        keeping.formUnion(news.held)
        refreshNews()
        await syncNow()
    }

    /// The deletes the last pass held back were meant: the next pass lets them through, as it would one at a time.
    func letHeldGo() async {
        lettingGo.formUnion(news.held)
        refreshNews()
        await syncNow()
    }

    /// The folder list in iCloud can't be read: the next pass puts a new one made from this device's folders in its
    /// place, and every other device adds its own to it.
    func replaceFolders() async {
        replacingFolders = true
        refreshNews()
        await syncNow()
    }

    /// How long a window waits at launch for the notebook it reopens to be brought up to date.
    static let reopenLimit: Duration = .seconds(4)

    /// Brings in the synced copy's newer version of notebooks an editor is about to open, or has open (`take` then lets
    /// go of it), without waiting for a whole pass. Gives up after `limit`, and returns at once with sync off. It waits
    /// for a pass under way, and a pass for it, so the two never settle a notebook at once.
    @discardableResult
    func pullNewer(_ ids: [UUID], within limit: Duration, take: (@MainActor (UUID) -> Bool)? = nil) async -> [UUID: LibrarySync.Newer] {
        guard isEnabled, !ids.isEmpty else { return [:] }
        let deadline = ContinuousClock.now + limit
        pulls += 1
        defer { pulls -= 1 }
        while isEnabled, availability == .checking || reviewing > 0 || running != nil || isPulling, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard canSync, let cloud, running == nil, !isPulling else { return [:] }
        isPulling = true
        defer { isPulling = false }
        let root = root, take = take ?? self.take, release = release
        var outcome: [UUID: LibrarySync.Newer] = [:]
        for id in ids {
            let left = deadline - ContinuousClock.now
            guard left > .zero, canSync else { break }
            let newer = try? await Task.detached(priority: .userInitiated) {
                try await LibrarySync.pullNewer(id, root: root, cloud: cloud, timeout: left, take: { await take($0) }, release: { await release($0) })
            }.value
            outcome[id] = newer ?? LibrarySync.Newer.none
        }
        let pulled = ids.filter { outcome[$0] == .pulled }
        if !pulled.isEmpty { await onLibraryChanged?(SyncReport(pulled: pulled)) }
        return outcome
    }

    /// Notebooks open in an editor that another device has written in since: one with nothing unsaved takes that version
    /// and its editor opens it again, and one with writing of its own is told that a newer version is waiting.
    func catchUp(open registry: DocumentRegistry, within limit: Duration = .seconds(10)) async {
        let ids = registry.openNotebooks
        guard isEnabled, !ids.isEmpty else { return }
        // Saved first, so what is on the device says whether it was written in here.
        for id in ids { await registry.document(for: id)?.flush() }
        let outcome = await pullNewer(ids, within: limit) { registry.takeOpen($0) }
        for (id, newer) in outcome where newer == .waiting { registry.document(for: id)?.noteNewerVersion() }
    }

    /// Notebooks, flashcards and stickers arriving from another device show up as changes to the container's files.
    private func startWatching() {
        guard query == nil, cloud?.isUbiquitous == true else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        // Ink and pictures too, since a pull waits for files that come down after the manifest, and the package as one item, as iCloud may list it.
        let kinds = ["*.\(StorageRoot.packageExtension)", "*.pkdrawing", "*.png", "*.jpg", "*.pdf"].map { NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, $0) }
        query.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [NSPredicate(format: "%K IN %@", NSMetadataItemFSNameKey, ["manifest.json", "cards.json"])] + kinds)
        for name in [Notification.Name.NSMetadataQueryDidUpdate, .NSMetadataQueryDidFinishGathering] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
        query.start()
        self.query = query
    }

    /// Looks at what iCloud still has to upload, and again a little later while anything is left.
    private func checkUploads() async {
        uploadCheck?.cancel()
        guard let cloud else { return }
        let read = readUploads
        uploads = await Task.detached(priority: .utility) { read(cloud) }.value
        refreshNews()
        guard !uploads.isClear else { return }
        uploadCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            await self?.checkUploads()
        }
    }

    /// Whether the last pass finished with nothing left behind, and iCloud holds everything it sent.
    var isUpToDate: Bool {
        lastError == nil && lastReport?.waiting.isEmpty == true && lastReport?.foldersUnreadable == false && uploads.isClear
    }

    /// "15 Oct, 14:05": the day as well as the time, since the last sync may be days ago.
    nonisolated static func formatted(_ date: Date, now: Date = .now) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).hour().minute()
        return date.formatted(Calendar.current.isDate(date, equalTo: now, toGranularity: .year) ? style : style.year())
    }

    /// The Settings line for the last pass: what it did, what it left, and what iCloud still has to upload.
    var status: String? {
        guard let lastReport else { return nil }
        let parts = lastReport.parts + uploads.parts
        return parts.isEmpty ? String(localized: "Everything is up to date") : parts.joined(separator: ", ")
    }

    /// What is shown now, less what was put away and hasn't changed since.
    private func refreshNews() {
        let failed = lastReport?.failed ?? [], held = (lastReport?.held ?? []).filter { !keeping.contains($0) && !lettingGo.contains($0) }
        let foldersUnreadable = lastReport?.foldersUnreadable == true && !replacingFolders
        putAway.failed.removeAll { !failed.contains($0) }
        if Set(putAway.held) != Set(held) { putAway.held = [] }
        if putAway.uploadProblem != uploads.problem { putAway.uploadProblem = nil }
        if putAway.stopped != stopped { putAway.stopped = nil }
        if !foldersUnreadable { putAway.foldersUnreadable = false }
        let fresh = SyncNews(failed: failed.filter { !putAway.failed.contains($0) }, held: putAway.held.isEmpty ? held : [],
                             conflictCopies: newCopies, journals: setAsideJournals,
                             uploadProblem: uploads.problem == putAway.uploadProblem ? nil : uploads.problem,
                             stopped: stopped == putAway.stopped ? nil : stopped,
                             foldersUnreadable: foldersUnreadable && !putAway.foldersUnreadable)
        if fresh != news { news = fresh }
    }

    /// The library's notice was closed: what it said stays away until it changes.
    func putAwayNews() {
        putAway.failed += news.failed
        if !news.held.isEmpty { putAway.held = news.held }
        putAway.uploadProblem = uploads.problem
        putAway.stopped = stopped
        if news.foldersUnreadable { putAway.foldersUnreadable = true }
        newCopies = []
        setAsideJournals = []
        refreshNews()
    }

    /// Stops watching the container, and a pass that is part-way.
    private func halt() {
        pending?.cancel()
        running?.cancel()
        uploadCheck?.cancel()
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}

/// The words for what sync asks, in the library's notice and in Settings.
enum SyncQuestion {
    static func title(_ question: SyncCenter.Question) -> String {
        switch question {
        case .firstSync: String(localized: "Keep a copy of your notebooks in iCloud?")
        case .accountChanged: String(localized: "A different Apple Account is signed in")
        }
    }

    static func message(_ question: SyncCenter.Question) -> String {
        switch question {
        case .firstSync:
            String(localized: "MathNotes can copy every notebook, folder and sticker to your private iCloud storage, so your other devices have them. Nothing is copied until you choose to, and Settings › iCloud in MathNotes can change it later.")
        case .accountChanged: accountChangedMessage
        }
    }

    static var accountChangedMessage: String {
        String(localized: "This iPad's notebooks were last synced with another account's iCloud. Syncing with this account copies them to its iCloud storage and brings in the notebooks it holds.")
    }

    static func allow(_ question: SyncCenter.Question) -> String {
        switch question {
        case .firstSync: String(localized: "Sync with iCloud")
        case .accountChanged: String(localized: "Sync with This Account")
        }
    }

    static func refuse(_ question: SyncCenter.Question) -> String {
        switch question {
        case .firstSync: String(localized: "Not Now")
        case .accountChanged: String(localized: "Turn Off Sync")
        }
    }
}

extension SyncReport {
    /// What the pass did and left, a phrase each, a notebook whose lock, folder or cards alone went counted too.
    var parts: [String] {
        var parts: [String] = []
        let sent = Set(pushed).union(stateSent).union(cardsSent).count, received = Set(pulled).union(stateReceived).union(cardsReceived).count
        let deletions = removedHere.count + removedThere.count
        if sent > 0 { parts.append(String(localized: "\(sent) notebooks sent")) }
        if received > 0 { parts.append(String(localized: "\(received) notebooks received")) }
        if deletions > 0 { parts.append(String(localized: "\(deletions) deletions carried over")) }
        if conflictCopies.count > 0 { parts.append(String(localized: "\(conflictCopies.count) conflicted copies kept")) }
        if open.count > 0 { parts.append(String(localized: "\(open.count) notebooks waiting until they're closed")) }
        if arriving.count > 0 { parts.append(String(localized: "\(arriving.count) notebooks still downloading from iCloud")) }
        if failed.count > 0 { parts.append(String(localized: "\(failed.count) notebooks didn't sync")) }
        if held.count > 0 { parts.append(String(localized: "\(held.count) deletions held back")) }
        if foldersUnreadable { parts.append(String(localized: "Folders aren't syncing")) }
        return parts
    }

    var summary: String { parts.isEmpty ? String(localized: "Everything is up to date") : parts.joined(separator: ", ") }
}

extension SyncFailure.Reason {
    var message: String {
        switch self {
        case .noRoom: String(localized: "There isn't enough room on this iPad.")
        case .unreadable(inICloud: true): String(localized: "Its copy in iCloud can't be read.")
        case .unreadable(inICloud: false): String(localized: "Its copy on this iPad can't be read.")
        case .newerVersion: String(localized: "It was saved by a newer version of MathNotes. Update MathNotes on this iPad to sync it.")
        case .coordination(let detail): String(localized: "iCloud Drive didn't let MathNotes reach its files: \(detail)")
        case .other(let detail): detail
        }
    }
}

/// What iCloud still has to upload from the synced copy, and what is stopping it.
struct CloudUploads: Sendable, Equatable {
    enum Problem: Sendable, Equatable {
        case full
        case unreachable
        case other(String)

        var message: String {
            switch self {
            case .full:
                String(localized: "Your iCloud storage is full, so changes made on this iPad can't be uploaded. Free up space, or choose a bigger plan in Settings › your name › iCloud.")
            case .unreachable: String(localized: "iCloud can't be reached right now. Changes made on this iPad will upload when it's back.")
            case .other(let detail): String(localized: "iCloud couldn't upload some files: \(detail)")
            }
        }
    }

    /// Notebooks with a file iCloud hasn't uploaded yet.
    var pending: Set<UUID> = []
    /// Folders, stickers or deletions iCloud hasn't uploaded yet.
    var othersPending = false
    var problem: Problem?

    var isClear: Bool { pending.isEmpty && !othersPending && problem == nil }

    var parts: [String] {
        if !pending.isEmpty {
            return [problem == nil ? String(localized: "\(pending.count) notebooks still uploading to iCloud")
                                   : String(localized: "\(pending.count) notebooks not uploaded to iCloud")]
        }
        return othersPending ? [String(localized: "Still uploading to iCloud")] : []
    }

    /// Looks at every file in the synced copy. `values` stands in for iCloud's word on one file in tests.
    static func read(_ cloud: CloudFolder, values: (URL) -> (uploaded: Bool?, error: (any Error)?) = uploadValues) -> CloudUploads {
        var result = CloudUploads()
        let base = cloud.url.standardizedFileURL.path(percentEncoded: false)
        let keys: [URLResourceKey] = [.isRegularFileKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey]
        let enumerator = FileManager.default.enumerator(at: cloud.url, includingPropertiesForKeys: keys)
        while let url = enumerator?.nextObject() as? URL {
            let name = url.lastPathComponent
            // A placeholder stands for a file that is in iCloud already; an upload under way is assembled before it counts.
            if name.hasSuffix(".icloud") || name.hasSuffix(".part") || name.hasSuffix(".\(CloudFolder.uploadExtension)") {
                enumerator?.skipDescendants()
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let (uploaded, error) = values(url)
            if let error { result.problem = worse(result.problem, Problem(error)) }
            guard uploaded == false || error != nil else { continue }
            let path = url.standardizedFileURL.path(percentEncoded: false).dropFirst(base.count).split(separator: "/")
            if path.count > 2, path[0] == "Library", path[1].hasSuffix(".\(StorageRoot.packageExtension)"),
               let id = UUID(uuidString: String(path[1].dropLast(StorageRoot.packageExtension.count + 1))) {
                result.pending.insert(id)
            } else {
                result.othersPending = true
            }
        }
        return result
    }

    static func uploadValues(_ url: URL) -> (uploaded: Bool?, error: (any Error)?) {
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey])
        return (values?.ubiquitousItemIsUploaded, values?.ubiquitousItemUploadingError)
    }

    private static func worse(_ a: Problem?, _ b: Problem) -> Problem {
        switch (a, b) {
        case (.full?, _), (_, .full): .full
        case (.unreachable?, _), (_, .unreachable): .unreachable
        default: a ?? b
        }
    }
}

extension CloudUploads.Problem {
    init(_ error: any Error) {
        let error = error as NSError
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, NSUbiquitousFileNotUploadedDueToQuotaError): self = .full
        case (NSCocoaErrorDomain, NSUbiquitousFileUbiquityServerNotAvailable): self = .unreachable
        default: self = .other(error.localizedDescription)
        }
    }
}

/// What the library shows about sync until it is put away.
struct SyncNews: Equatable {
    var failed: [SyncFailure] = []
    /// Notebooks gone from one side that sync didn't take as deleted, since too many went at once.
    var held: [UUID] = []
    /// Conflicted copies made since the notice was last put away.
    var conflictCopies: [UUID] = []
    /// This device's journals that gave way to one begun earlier on another device.
    var journals: [UUID] = []
    var uploadProblem: CloudUploads.Problem?
    /// Why the last pass stopped part-way.
    var stopped: String?
    /// The folder list in iCloud can't be read, so folders aren't syncing.
    var foldersUnreadable = false

    var isEmpty: Bool { !isTrouble && conflictCopies.isEmpty && journals.isEmpty }
    /// Something went wrong, as opposed to a conflicted copy, which is only worth knowing about.
    var isTrouble: Bool { !failed.isEmpty || !held.isEmpty || uploadProblem != nil || stopped != nil || foldersUnreadable }
    var count: Int {
        failed.count + (held.isEmpty ? 0 : 1) + conflictCopies.count + journals.count + (uploadProblem == nil ? 0 : 1) + (stopped == nil ? 0 : 1)
            + (foldersUnreadable ? 1 : 0)
    }

    func keeping(copies kept: (UUID) -> Bool) -> SyncNews {
        var news = self
        news.conflictCopies.removeAll { !kept($0) }
        news.journals.removeAll { !kept($0) }
        return news
    }
}
