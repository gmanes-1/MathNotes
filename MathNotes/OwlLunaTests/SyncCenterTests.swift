import XCTest
import PencilKit
import SwiftData
import os
@testable import OwlLuna

/// What sync asks before it copies anything: once on a device that has never synced, and again when the Apple Account changes.
@MainActor
final class SyncCenterTests: XCTestCase {
    private let paper = PageDefaults(template: .grid, paperColor: .white, pageSize: .letter)
    private var root: StorageRoot!
    private var cloud: CloudFolder!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        root = temporaryRoot(self)
        cloud = CloudFolder(url: temporaryRoot(self).url)
        let suite = "owlluna-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }

    @discardableResult
    private func makeNotebook(_ title: String, on root: StorageRoot) async throws -> UUID {
        let manifest = NotebookManifest(title: title, defaults: paper, pages: [paper.newPage()])
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        return manifest.id
    }

    private func synced(_ id: UUID, in cloud: CloudFolder) -> Bool {
        FileManager.default.fileExists(atPath: cloud.package(id).appending(path: "manifest.json").path(percentEncoded: false))
    }

    func testNothingIsCopiedUntilTheFirstSyncIsAllowed() async throws {
        let id = try await makeNotebook("Physics", on: root)
        let center = SyncCenter(root: root, defaults: defaults)
        XCTAssertFalse(center.isEnabled, "a device that has never synced doesn't start by itself")
        XCTAssertNil(center.question, "and isn't asked while iCloud is out of reach")

        await center.use(cloud, account: "one")
        XCTAssertEqual(center.question, .firstSync)
        await center.syncNow()
        XCTAssertFalse(synced(id, in: cloud))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.library.path(percentEncoded: false)), "the copy isn't touched while the question stands")

        await center.answer(true)
        XCTAssertNil(center.question)
        XCTAssertTrue(center.isEnabled)
        await center.syncNow()
        XCTAssertTrue(synced(id, in: cloud))
        XCTAssertEqual(defaults.object(forKey: SettingsKey.syncsWithICloud) as? Bool, true)
        XCTAssertEqual(SyncState.read(root).account, "one")

        let relaunched = SyncCenter(root: root, defaults: defaults)
        await relaunched.use(cloud, account: "one")
        XCTAssertTrue(relaunched.isEnabled)
        XCTAssertNil(relaunched.question, "it is asked once")
    }

    func testSayingNotNowLeavesSyncOffAndIsNotAskedAgain() async throws {
        let id = try await makeNotebook("Physics", on: root)
        let center = SyncCenter(root: root, defaults: defaults)
        await center.use(cloud, account: "one")
        await center.answer(false)
        XCTAssertNil(center.question)
        XCTAssertFalse(center.isEnabled)
        await center.syncNow()
        XCTAssertFalse(synced(id, in: cloud))

        let relaunched = SyncCenter(root: root, defaults: defaults)
        await relaunched.use(cloud, account: "one")
        XCTAssertNil(relaunched.question)
        XCTAssertFalse(relaunched.isEnabled)
    }

    func testTheSwitchCanBeSetBeforeICloudIsAvailable() async throws {
        let center = SyncCenter(root: root, defaults: defaults)
        XCTAssertEqual(center.availability, .checking)
        center.isEnabled = true
        center.isEnabled = false
        XCTAssertEqual(defaults.object(forKey: SettingsKey.syncsWithICloud) as? Bool, false)

        let id = try await makeNotebook("Physics", on: root)
        let later = SyncCenter(root: root, defaults: defaults)
        await later.use(cloud, account: "one")
        XCTAssertNil(later.question, "turned off beforehand, it neither asks nor starts when iCloud appears")
        await later.syncNow()
        XCTAssertFalse(synced(id, in: cloud))

        later.isEnabled = true
        await later.syncNow()
        XCTAssertTrue(synced(id, in: cloud), "turning the switch on is the answer")
    }

    func testADeviceAlreadySyncingCarriesOnUnasked() async throws {
        let id = try await makeNotebook("Physics", on: root)
        // An earlier build synced without asking and stored nothing about the choice.
        try SyncState().write(root)
        let center = SyncCenter(root: root, defaults: defaults)
        XCTAssertTrue(center.isEnabled)
        await center.use(cloud, account: "one")
        XCTAssertNil(center.question)
        await center.syncNow()
        XCTAssertTrue(synced(id, in: cloud))
    }

    func testAnotherAppleAccountStopsSyncUntilItIsAllowed() async throws {
        let mine = try await makeNotebook("Mine", on: root)
        var folders = FolderFile()
        folders.folders = [FolderEntry(id: UUID(), name: "Science", clothRaw: "jade", createdAt: .now, sortIndex: 0)]
        try folders.write(root)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let first = SyncCenter(root: root, defaults: defaults)
        await first.use(cloud, account: "one")
        await first.syncNow()
        XCTAssertTrue(synced(mine, in: cloud))

        let other = CloudFolder(url: temporaryRoot(self).url)
        let center = SyncCenter(root: root, defaults: defaults)
        await center.use(other, account: "two")
        XCTAssertEqual(center.question, .accountChanged)
        await center.syncNow()
        XCTAssertFalse(synced(mine, in: other), "nothing goes to the other account's iCloud unasked")
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.library.path(percentEncoded: false)))

        await center.answer(true)
        XCTAssertNil(center.question)
        XCTAssertTrue(synced(mine, in: other))
        XCTAssertEqual(center.lastReport?.startedAgain, true)
        XCTAssertEqual(FolderFile.read(root).folders.map(\.name), ["Science"], "and nothing synced under the first account is deleted")
        XCTAssertEqual(SyncState.read(root).account, "two")
    }

    func testRefusingAnotherAccountTurnsSyncOffAndAsksAgainWhenTurnedOn() async throws {
        let mine = try await makeNotebook("Mine", on: root)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        _ = try await LibrarySync.run(root: root, cloud: cloud, account: "one")

        let other = CloudFolder(url: temporaryRoot(self).url)
        let center = SyncCenter(root: root, defaults: defaults)
        await center.use(other, account: "two")
        await center.answer(false)
        XCTAssertFalse(center.isEnabled)
        XCTAssertNil(center.question)

        let relaunched = SyncCenter(root: root, defaults: defaults)
        await relaunched.use(other, account: "two")
        XCTAssertFalse(relaunched.isEnabled)
        XCTAssertNil(relaunched.question, "with sync off there is nothing to ask at the next launch: the refusal stands")

        center.isEnabled = true
        for _ in 0..<100 where center.question == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(center.question, .accountChanged)
        await center.syncNow()
        XCTAssertFalse(synced(mine, in: other))
    }

    func testTurningSyncOffInSettingsAnswersTheQuestion() async throws {
        try await makeNotebook("Mine", on: root)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        _ = try await LibrarySync.run(root: root, cloud: cloud, account: "one")

        let other = CloudFolder(url: temporaryRoot(self).url)
        let center = SyncCenter(root: root, defaults: defaults)
        await center.use(other, account: "two")
        XCTAssertEqual(center.question, .accountChanged)
        center.isEnabled = false
        XCTAssertNil(center.question, "the switch is an answer too, so the notice doesn't stay up")
    }

    func testNoPassSlipsInWhileTheQuestionIsBeingWorkedOut() async throws {
        let mine = try await makeNotebook("Mine", on: root)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        _ = try await LibrarySync.run(root: root, cloud: cloud, account: "one")

        let other = CloudFolder(url: temporaryRoot(self).url)
        let center = SyncCenter(root: root, defaults: defaults)
        let found = Task { await center.use(other, account: "two") }
        // A sync asked for by something else, arriving once the copy is found and before the question is known.
        for _ in 0..<100_000 where center.availability == .checking && center.question == nil { await Task.yield() }
        await center.syncNow()
        await found.value
        XCTAssertEqual(center.question, .accountChanged)
        XCTAssertFalse(synced(mine, in: other), "nothing goes to the other account's iCloud before it has been asked about")
    }

    // MARK: What changes while a pass runs

    /// Two notebooks in step with the synced copy and then written in on another device, in the order a pass takes them.
    private func twoNotebooksWrittenInElsewhere(account: String? = nil) async throws -> (first: UUID, second: UUID) {
        let ids = [try await makeNotebook("One", on: root), try await makeNotebook("Two", on: root)].sorted { $0.uuidString < $1.uuidString }
        let there = temporaryRoot(self)
        _ = try await LibrarySync.run(root: root, cloud: cloud, account: account)
        _ = try await LibrarySync.run(root: there, cloud: cloud, account: account)
        for id in ids {
            _ = try await NotebookPackage(root: there, id: id).updateManifest {
                $0.title += ", written in"
                $0.modifiedAt = $0.modifiedAt.addingTimeInterval(60)
            }
        }
        _ = try await LibrarySync.run(root: there, cloud: cloud, account: account)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        return (ids[0], ids[1])
    }

    private func isWrittenIn(_ id: UUID) async throws -> Bool {
        try await NotebookPackage(root: root, id: id).readManifest().manifest.title.hasSuffix(", written in")
    }

    func testANotebookOpenedAfterThePassBeganIsLeftAlone() async throws {
        let (first, second) = try await twoNotebooksWrittenInElsewhere()
        let center = SyncCenter(root: root, defaults: defaults), registry = DocumentRegistry.shared
        let document = try await NotebookDocument.open(second, root: root)
        addTeardownBlock { @MainActor in registry.unregister(second, document: document) }
        // Wired as the app does. The second notebook is opened in an editor while the first pass is busy with the first.
        var opened = false
        center.take = { registry.take($0) }
        center.release = { id in
            registry.release(id)
            if id == first, !opened {
                registry.register(document, scene: nil)
                opened = true
            }
        }
        await center.use(cloud, account: nil)
        await center.syncNow()
        XCTAssertEqual(center.lastReport?.pulled, [first])
        XCTAssertEqual(center.lastReport?.waiting, [second], "it is asked about when its turn comes, not when the pass began")
        let untouched = try await isWrittenIn(second)
        XCTAssertFalse(untouched, "so nothing is copied over a notebook under its open editor")

        registry.unregister(second, document: document)
        await center.syncNow()
        XCTAssertEqual(center.lastReport?.pulled, [second], "and it syncs once it is closed")
    }

    func testOpeningANotebookWaitsWhileASyncHasItInHand() async throws {
        let (first, _) = try await twoNotebooksWrittenInElsewhere()
        let center = SyncCenter(root: root, defaults: defaults), registry = DocumentRegistry.shared, root = root!
        var opening: Task<NotebookDocument, Error>?
        // Tapped open just as the pass takes the notebook in hand.
        center.take = { id in
            let taken = registry.take(id)
            if id == first { opening = Task { try await registry.open(first, root: root, scene: nil) { _ in } } }
            return taken
        }
        center.release = { registry.release($0) }
        await center.use(cloud, account: nil)
        await center.syncNow()
        let document = try await XCTUnwrap(opening).value
        addTeardownBlock { @MainActor in registry.unregister(first, document: document) }
        XCTAssertEqual(center.lastReport?.pulled.contains(first), true)
        XCTAssertTrue(document.title.hasSuffix(", written in"), "the editor opens what the sync brought in, not the files it was replacing")
        XCTAssertFalse(registry.take(first), "and once it is open a sync can't take it")
    }

    func testTurningSyncOffStopsAPassPartWay() async throws {
        let (first, second) = try await twoNotebooksWrittenInElsewhere()
        let center = SyncCenter(root: root, defaults: defaults)
        var finished = 0
        center.onSynced = { _ in finished += 1 }
        center.take = { [weak center] id in
            if id == first { center?.isEnabled = false }
            return true
        }
        await center.use(cloud, account: nil)
        await center.syncNow()
        let inHand = try await isWrittenIn(first), next = try await isWrittenIn(second)
        XCTAssertTrue(inHand, "the notebook in hand is finished")
        XCTAssertFalse(next, "and the pass goes no further")
        XCTAssertNil(center.lastError, "being stopped isn't a failure")
        XCTAssertEqual(finished, 0)
    }

    func testAPassUnderWayStopsWhenAnotherAccountSignsIn() async throws {
        let (first, second) = try await twoNotebooksWrittenInElsewhere(account: "one")
        let other = CloudFolder(url: temporaryRoot(self).url)
        let center = SyncCenter(root: root, defaults: defaults)
        var change: Task<Void, Never>?
        center.take = { [weak center] id in
            if id == first { change = Task { await center?.use(other, account: "two") } }
            return true
        }
        await center.use(cloud, account: "one")
        await center.syncNow()
        await change?.value
        XCTAssertEqual(center.question, .accountChanged)
        let next = try await isWrittenIn(second)
        XCTAssertFalse(next, "the pass begun under the first account stops while the question is asked")
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.library.path(percentEncoded: false)), "and nothing reaches the other account's iCloud unasked")
        await center.syncNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.library.path(percentEncoded: false)))
    }

    // MARK: A notebook reopened, or open, after another device wrote in it

    func testAReopenedNotebookWaitsForItsNewerVersionSoNoConflictedCopyIsMade() async throws {
        let (first, second) = try await twoNotebooksWrittenInElsewhere()
        let center = SyncCenter(root: root, defaults: defaults), registry = DocumentRegistry.shared, root = root!
        center.take = { registry.take($0) }
        center.release = { registry.release($0) }
        // The window asks as the app becomes ready, before iCloud has been found.
        let window = Task {
            await center.pullNewer([first], within: SyncCenter.reopenLimit)
            return try await registry.open(first, root: root, scene: nil) { _ in }
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(registry.document(for: first), "nothing is reopened while iCloud is still being looked for")
        XCTAssertFalse(registry.isOpening(first))
        await center.use(cloud, account: nil)
        // The launch pass is asked for at once, and waits for the window's notebook.
        let launch = Task { await center.syncNow() }
        let document = try await window.value
        await launch.value
        addTeardownBlock { @MainActor in registry.unregister(first, document: document) }
        XCTAssertTrue(document.title.hasSuffix(", written in"), "the window opens the version written on the other device")
        XCTAssertEqual(center.lastReport?.pulled, [second])

        document.rename("Written here")
        await document.flush()
        registry.unregister(first, document: document)
        await center.syncNow()
        XCTAssertEqual(center.lastReport?.pushed, [first], "written in and closed, it goes to the other device as it is")
        XCTAssertEqual(center.lastReport?.conflictCopies, [])
    }

    func testAReopenedNotebookWaitsAFewSecondsAtMostAndNotAtAllWithSyncOff() async throws {
        let (first, _) = try await twoNotebooksWrittenInElsewhere()
        // iCloud is never found.
        let center = SyncCenter(root: root, defaults: defaults)
        let began = ContinuousClock.now
        let outcome = await center.pullNewer([first], within: .milliseconds(500))
        let waited = ContinuousClock.now - began
        XCTAssertTrue(outcome.isEmpty)
        XCTAssertGreaterThanOrEqual(waited, .milliseconds(500))
        XCTAssertLessThan(waited, .seconds(3), "it gives up, and the window opens what is on the device")
        let untouched = try await isWrittenIn(first)
        XCTAssertFalse(untouched)

        defaults.set(false, forKey: SettingsKey.syncsWithICloud)
        let off = SyncCenter(root: root, defaults: defaults)
        let start = ContinuousClock.now
        await off.pullNewer([first], within: SyncCenter.reopenLimit)
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(200), "with sync off there is nothing to wait for")
        await off.use(cloud, account: nil)
        await off.pullNewer([first], within: SyncCenter.reopenLimit)
        let stillUntouched = try await isWrittenIn(first)
        XCTAssertFalse(stillUntouched)
    }

    func testACleanOpenNotebookTakesTheNewerVersionAndIsOpenedAgain() async throws {
        let (first, _) = try await twoNotebooksWrittenInElsewhere()
        let center = SyncCenter(root: root, defaults: defaults), registry = DocumentRegistry.shared, root = root!
        center.take = { registry.take($0) }
        center.release = { registry.release($0) }
        let old = try await registry.open(first, root: root, scene: nil) { _ in }
        addTeardownBlock { @MainActor in registry.unregister(first, document: old) }
        // As the editor does on opening: where the notebook was left off reading isn't writing in it.
        old.noteOpened()
        let reopen = expectation(forNotification: .mathNotesReopenNotebook, object: nil) { ($0.object as? UUID) == first }
        await center.use(cloud, account: nil)
        await center.catchUp(open: registry)
        await fulfillment(of: [reopen], timeout: 1)
        XCTAssertTrue(old.isSetAside)
        XCTAssertNil(registry.document(for: first), "the editor lets go of the copy it had")
        let pulled = try await isWrittenIn(first)
        XCTAssertTrue(pulled)
        let fresh = try await registry.open(first, root: root, scene: nil) { _ in }
        addTeardownBlock { @MainActor in registry.unregister(first, document: fresh) }
        XCTAssertFalse(fresh === old)
        XCTAssertTrue(fresh.title.hasSuffix(", written in"), "and opens the newer version in its place")
        XCTAssertTrue(old.notices.isEmpty)

        old.rename("Too late")
        await old.flush()
        let kept = try await isWrittenIn(first)
        XCTAssertTrue(kept, "the copy set aside writes nothing over the newer files")
        registry.unregister(first, document: fresh)
        await center.syncNow()
        XCTAssertEqual(center.lastReport?.pulled.contains(first), false)
        XCTAssertEqual(center.lastReport?.conflictCopies, [])
    }

    func testAnOpenNotebookWrittenInHereIsToldANewerVersionIsWaiting() async throws {
        let (first, _) = try await twoNotebooksWrittenInElsewhere()
        let center = SyncCenter(root: root, defaults: defaults), registry = DocumentRegistry.shared, root = root!
        center.take = { registry.take($0) }
        center.release = { registry.release($0) }
        let document = try await registry.open(first, root: root, scene: nil) { _ in }
        addTeardownBlock { @MainActor in registry.unregister(first, document: document) }
        document.rename("Written here")
        await center.use(cloud, account: nil)
        await center.catchUp(open: registry)
        XCTAssertFalse(document.isSetAside)
        XCTAssertTrue(registry.document(for: first) === document, "the editor keeps what it has")
        XCTAssertEqual(document.notices.map(\.kind), [.newerVersion])
        let here = try await NotebookPackage(root: root, id: first).readManifest().manifest.title
        XCTAssertEqual(here, "Written here", "nothing is written over it")
        await center.catchUp(open: registry)
        XCTAssertEqual(document.notices.count, 1, "it is said once")

        registry.unregister(first, document: document)
        await center.syncNow()
        XCTAssertEqual(center.lastReport?.conflictCopies.count, 1, "once it is closed, both versions are kept")
    }

    func testAnOpenNotebookIsLetGoOfOnlyWithNothingToSave() async throws {
        let id = try await makeNotebook("Physics", on: root), registry = DocumentRegistry.shared
        let document = try await registry.open(id, root: root, scene: nil) { _ in }
        addTeardownBlock { @MainActor in
            registry.release(id)
            registry.unregister(id, document: document)
        }
        document.rename("Physics II")
        XCTAssertFalse(registry.takeOpen(id), "a change not yet saved keeps it open")
        XCTAssertFalse(document.isSetAside)
        await document.flush()
        XCTAssertTrue(registry.takeOpen(id))
        XCTAssertTrue(document.isSetAside)
        XCTAssertNil(registry.document(for: id))
    }

    // MARK: Recently Deleted and the launch sync

    private var container: ModelContainer?

    private func makeStore() throws -> LibraryStore {
        let container = try ModelContainer(for: LibraryIndex.schema, configurations: ModelConfiguration(schema: LibraryIndex.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        self.container = container
        return LibraryStore(root: root, context: container.mainContext)
    }

    private func file(_ id: UUID, on root: StorageRoot, deletedAt: Date?, stamped: Date) async throws {
        _ = try await NotebookPackage(root: root, id: id).updateManifest {
            $0.library.deletedAt = deletedAt
            $0.library.setChangedAt(stamped, for: .deleted)
        }
    }

    func testTheThirtyDaysAreCountedAfterTheLaunchSync() async throws {
        let store = try makeStore(), there = temporaryRoot(self)
        let restored = try await makeNotebook("Restored", on: root), written = try await makeNotebook("Written in", on: root)
        let expired = try await makeNotebook("Expired", on: root)
        _ = try await LibrarySync.run(root: root, cloud: cloud)
        _ = try await LibrarySync.run(root: there, cloud: cloud)
        // Deleted here long ago, and this device hasn't been opened since.
        let longAgo = Date.now.addingTimeInterval(-40 * 86_400)
        for id in [restored, written, expired] { try await file(id, on: root, deletedAt: longAgo, stamped: longAgo) }
        _ = try await LibrarySync.run(root: root, cloud: cloud)
        // On the other device one is written in before it hears of that, and one is taken back out afterwards.
        _ = try await NotebookPackage(root: there, id: written).updateManifest { $0.modifiedAt = $0.modifiedAt.addingTimeInterval(60) }
        _ = try await LibrarySync.run(root: there, cloud: cloud)
        try await file(restored, on: there, deletedAt: nil, stamped: .now)
        _ = try await LibrarySync.run(root: there, cloud: cloud)

        await store.reloadFromDisk()
        XCTAssertEqual(store.record(restored)?.isTrashed, true)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults), purge = TrashPurge(library: store, sync: center)
        center.onLibraryChanged = { _ in await store.reloadFromDisk() }
        await center.use(cloud, account: nil)
        await center.syncNow()
        await purge.launchSyncTried()
        XCTAssertEqual(store.record(restored)?.isTrashed, false, "a notebook restored on another device is heard of before its 30 days are counted here")
        XCTAssertEqual(store.record(written)?.isTrashed, false, "and so is one written in there")
        XCTAssertNil(store.record(expired), "one that nobody wanted back still goes")

        await center.syncNow()
        let report = try await LibrarySync.run(root: there, cloud: cloud)
        XCTAssertEqual(report.removedHere, [], "its time ran out here, and the other device may keep Recently Deleted longer")
        XCTAssertEqual(Set(there.packageIDs()), [restored, written, expired], "and nothing wanted is removed from the device that wanted it")
    }

    /// A notebook put in Recently Deleted 40 days ago, as its own manifest and the index both have it.
    private func expiredNotebook(_ title: String, in store: LibraryStore) async throws -> UUID {
        let id = try await makeNotebook(title, on: root), longAgo = Date.now.addingTimeInterval(-40 * 86_400)
        try await file(id, on: root, deletedAt: longAgo, stamped: longAgo)
        await store.reloadFromDisk()
        XCTAssertEqual(store.record(id)?.isTrashed, true)
        return id
    }

    private func isOnDisk(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: root.package(id).path(percentEncoded: false))
    }

    func testNothingIsPurgedUntilTheLaunchSyncHasFinished() async throws {
        let store = try makeStore()
        let expired = try await expiredNotebook("Expired", in: store)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults), purge = TrashPurge(library: store, sync: center)
        // The launch sync is tried while iCloud is still being looked for.
        await center.syncNow()
        let launch = Task { await purge.launchSyncTried() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(store.record(expired), "a pass may be about to follow, so nothing is counted yet")
        await center.use(cloud, account: nil)
        await launch.value
        XCTAssertNotNil(store.record(expired), "and with a sync to wait for, nothing goes before it")

        await center.syncNow()
        XCTAssertNil(store.record(expired), "what is past its 30 days goes once the sync has finished")
        XCTAssertFalse(isOnDisk(expired))
    }

    func testWithNothingToSyncWithRecentlyDeletedIsEmptiedAtOnce() async throws {
        let store = try makeStore()
        let expired = try await expiredNotebook("Expired", in: store), recent = try await makeNotebook("Recent", on: root)
        try await file(recent, on: root, deletedAt: Date.now.addingTimeInterval(-5 * 86_400), stamped: .now)
        await store.reloadFromDisk()
        // Sync has never been allowed on this device.
        let center = SyncCenter(root: root, defaults: defaults), purge = TrashPurge(library: store, sync: center)
        await center.use(cloud, account: nil)
        await center.syncNow()
        await purge.launchSyncTried()
        XCTAssertNil(store.record(expired))
        XCTAssertNotNil(store.record(recent), "a notebook still inside its 30 days stays")

        let later = try await expiredNotebook("Later", in: store)
        await purge.launchSyncTried()
        XCTAssertNotNil(store.record(later), "and it happens once a launch")
    }

    func testANotebookTheSyncLeftWaitingIsNotPurged() async throws {
        let store = try makeStore()
        let waiting = try await expiredNotebook("Waiting", in: store), expired = try await expiredNotebook("Expired", in: store)
        _ = try await LibrarySync.run(root: root, cloud: cloud)
        // Its manifest in the synced copy is still arriving, so this device can't tell whether it was restored elsewhere.
        try Data("{".utf8).write(to: cloud.package(waiting).appending(path: "manifest.json"))
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults), purge = TrashPurge(library: store, sync: center)
        await center.use(cloud, account: nil)
        await center.syncNow()
        await purge.launchSyncTried()
        XCTAssertEqual(center.lastReport?.waiting, [waiting])
        XCTAssertNotNil(store.record(waiting), "a notebook the sync couldn't settle isn't counted as still deleted")
        XCTAssertTrue(isOnDisk(waiting))
        XCTAssertNil(store.record(expired), "the rest of Recently Deleted is emptied as usual")
    }

    func testANotebookRestoredInItsOwnFilesIsNotPurgedOnTheIndexsWord() async throws {
        let store = try makeStore()
        let restored = try await expiredNotebook("Restored", in: store), expired = try await expiredNotebook("Expired", in: store)
        // Taken back out by a sync the index hasn't been told of, as a pass stopped part-way leaves it.
        try await file(restored, on: root, deletedAt: nil, stamped: .now)
        XCTAssertEqual(store.record(restored)?.isTrashed, true)
        await store.purgeExpiredTrash()
        XCTAssertNotNil(store.record(restored), "each notebook's own manifest has the last word")
        XCTAssertTrue(isOnDisk(restored))
        XCTAssertNil(store.record(expired))
    }

    func testRecentlyDeletedKeepsNotebooksForTheLengthChosen() async throws {
        let store = try makeStore()
        func binned(_ title: String, daysAgo: Double) async throws -> UUID {
            let id = try await makeNotebook(title, on: root), when = Date.now.addingTimeInterval(-daysAgo * 86_400)
            try await file(id, on: root, deletedAt: when, stamped: when)
            return id
        }
        let ten = try await binned("Ten days", daysAgo: 10), forty = try await binned("Forty days", daysAgo: 40)
        let hundred = try await binned("A hundred days", daysAgo: 100), two = try await binned("Two days", daysAgo: 2)
        await store.reloadFromDisk()
        XCTAssertEqual(TrashLength.current(defaults), .month, "30 days until it is changed")

        defaults.set(TrashLength.season.rawValue, forKey: SettingsKey.trashLength)
        let center = SyncCenter(root: root, defaults: defaults), purge = TrashPurge(library: store, sync: center, defaults: defaults)
        await center.use(cloud, account: nil)
        await purge.launchSyncTried()
        XCTAssertNil(store.record(hundred))
        XCTAssertNotNil(store.record(forty), "kept for 90 days")

        defaults.set(TrashLength.month.rawValue, forKey: SettingsKey.trashLength)
        await purge.lengthChanged()
        XCTAssertNil(store.record(forty), "a shorter length counts from when each went in, and doesn't wait for the next launch")
        XCTAssertNotNil(store.record(ten))
        defaults.set(TrashLength.week.rawValue, forKey: SettingsKey.trashLength)
        await purge.lengthChanged()
        XCTAssertNil(store.record(ten))
        XCTAssertNotNil(store.record(two))
        XCTAssertFalse(isOnDisk(ten))
        XCTAssertEqual(Set(ExpiredTrash.read(root).notebooks.keys), [forty, ten],
                       "each is noted as this device's own running out, but one past 90 days that no device keeps any longer")
    }

    // MARK: A pass that stops part-way

    func testAPassStoppedPartWayStillTellsTheLibrary() async throws {
        let (first, _) = try await twoNotebooksWrittenInElsewhere()
        let center = SyncCenter(root: root, defaults: defaults)
        var reports: [SyncReport] = []
        center.onLibraryChanged = { reports.append($0) }
        center.take = { [weak center] id in
            if id == first { center?.isEnabled = false }
            return true
        }
        await center.use(cloud, account: nil)
        await center.syncNow()
        XCTAssertEqual(reports.map(\.pulled), [[first]], "what arrived before the pass stopped is in the library now, not at the next launch")
        XCTAssertNil(center.lastError)
    }

    func testAFollowUpPassThatFailsDoesNotDropWhatTheFirstDid() async throws {
        let id = try await makeNotebook("Notes", on: root), there = temporaryRoot(self)
        _ = try await LibrarySync.run(root: root, cloud: cloud)
        _ = try await LibrarySync.run(root: there, cloud: cloud)
        _ = try await NotebookPackage(root: root, id: id).updateManifest { $0.modifiedAt = $0.modifiedAt.addingTimeInterval(60) }
        _ = try await NotebookPackage(root: there, id: id).updateManifest { $0.modifiedAt = $0.modifiedAt.addingTimeInterval(120) }
        _ = try await LibrarySync.run(root: there, cloud: cloud)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults), copyFile = cloud.copyFile.path(percentEncoded: false)
        var reports: [SyncReport] = []
        center.onLibraryChanged = { reports.append($0) }
        // The pass that uploads the conflicted copy can't read the synced copy's name.
        center.release = { _ in try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: copyFile) }
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: copyFile) }
        await center.use(cloud, account: nil)
        await center.syncNow()
        XCTAssertEqual(reports.map(\.conflictCopies.count), [1], "the library hears of the copy and the newer version the first pass brought in")
        XCTAssertEqual(reports.first?.pulled, [id])
        XCTAssertNotNil(center.lastError)
    }

    // MARK: A library change while a sync has the notebook in hand

    private func title(of id: UUID) async throws -> String {
        try await NotebookPackage(root: root, id: id).readManifest().manifest.title
    }

    func testASyncLeavesANotebookWhoseLibraryChangeIsStillBeingWritten() async throws {
        let store = try makeStore(), registry = DocumentRegistry.shared
        let id = try await makeNotebook("Diary", on: root)
        let write = store.update(id) { $0.title = "Renamed" }
        let taken = registry.take(id)
        if taken { registry.release(id) }
        XCTAssertFalse(taken, "its manifest is about to be rewritten, so a pass leaves it for next time")
        await write.value
        XCTAssertTrue(registry.take(id), "and takes it once the change is on disk")
        registry.release(id)
    }

    func testALibraryChangeWaitsWhileASyncHasTheNotebookInHand() async throws {
        let store = try makeStore(), registry = DocumentRegistry.shared
        let id = try await makeNotebook("Diary", on: root)
        XCTAssertTrue(registry.take(id))
        addTeardownBlock { @MainActor in registry.release(id) }
        let write = store.update(id) { $0.title = "Renamed" }
        try await Task.sleep(for: .milliseconds(300))
        let during = try await title(of: id)
        XCTAssertEqual(during, "Diary", "nothing is written into a notebook a pull may be about to replace")
        registry.release(id)
        await write.value
        let after = try await title(of: id)
        XCTAssertEqual(after, "Renamed", "the change is made once the notebook is let go")
    }

    func testALockSetWhileItsNotebookIsBeingPulledIsKept() async throws {
        let (first, _) = try await twoNotebooksWrittenInElsewhere()
        let store = try makeStore(), registry = DocumentRegistry.shared
        await store.reloadFromDisk()
        let record = try XCTUnwrap(store.record(first))
        let center = SyncCenter(root: root, defaults: defaults)
        // Locked from the library just as the pass takes the notebook in hand.
        center.take = { id in
            let taken = registry.take(id)
            if id == first { store.setLocked(true, for: [record]) }
            return taken
        }
        center.release = { registry.release($0) }
        center.onLibraryChanged = { _ in await store.reloadFromDisk() }
        await center.use(cloud, account: nil)
        await center.syncNow()
        XCTAssertEqual(center.lastReport?.pulled.contains(first), true)
        try await Task.sleep(for: .milliseconds(300))
        let manifest = try await NotebookPackage(root: root, id: first).readManifest().manifest
        XCTAssertTrue(manifest.title.hasSuffix(", written in"))
        XCTAssertTrue(manifest.library.isLocked, "the lock lands on the notebook the sync brought in")
        XCTAssertEqual(store.record(first)?.isLocked, true, "and the library still has it locked")
    }

    func testOnlyAPassThatFinishedIsFollowedUp() async throws {
        try await makeNotebook("Physics", on: root)
        _ = try await LibrarySync.run(root: root, cloud: cloud)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults), copyFile = cloud.copyFile.path(percentEncoded: false)
        var finished = 0
        center.onSynced = { _ in finished += 1 }
        await center.use(cloud, account: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: copyFile)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: copyFile) }
        await center.syncNow()
        XCTAssertNotNil(center.lastError)
        XCTAssertEqual(finished, 0, "a sync that couldn't reach the copy has heard nothing from the other devices")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: copyFile)
        await center.syncNow()
        XCTAssertNil(center.lastError)
        XCTAssertEqual(finished, 1)
    }

    func testALockThatArrivesTellsTheLibrary() async throws {
        let id = try await makeNotebook("Diary", on: root)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let there = temporaryRoot(self)
        _ = try await LibrarySync.run(root: there, cloud: cloud)
        let center = SyncCenter(root: root, defaults: defaults)
        var reports: [SyncReport] = []
        center.onLibraryChanged = { reports.append($0) }
        await center.use(cloud, account: nil)
        await center.syncNow()
        _ = try await LibrarySync.run(root: there, cloud: cloud)
        XCTAssertEqual(reports, [], "sending changes nothing here")

        _ = try await NotebookPackage(root: there, id: id).updateManifest {
            $0.library.isLocked = true
            $0.library.setChangedAt(.now, for: .locked)
        }
        _ = try await LibrarySync.run(root: there, cloud: cloud)
        await center.syncNow()
        XCTAssertEqual(reports.map(\.stateReceived), [[id]], "the hook that refreshes the index, Spotlight and the widgets runs for a lock alone")
        XCTAssertEqual(center.lastReport?.summary, "1 notebook received")
    }

    func testAnAccountsMarkerSaysOnlyWhetherItIsTheSame() {
        let one = SyncCenter.marker(for: Data([1, 2, 3]) as NSData), again = SyncCenter.marker(for: Data([1, 2, 3]) as NSData)
        let two = SyncCenter.marker(for: Data([1, 2, 4]) as NSData)
        XCTAssertEqual(one, again)
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(one?.count, 64, "a digest, not the token")
        XCTAssertNil(SyncCenter.marker(for: nil))
        XCTAssertEqual(SyncCenter.marker(for: "account" as NSString), SyncCenter.marker(for: "account" as NSString), "a token of another kind is archived first")
    }

    // MARK: What Settings and the library are told

    func testTheLastSyncSurvivesARelaunchAndShowsItsDay() async throws {
        try await makeNotebook("Physics", on: root)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults)
        await center.use(cloud, account: nil)
        await center.syncNow()
        let synced = try XCTUnwrap(center.lastSynced)

        let relaunched = SyncCenter(root: root, defaults: defaults)
        XCTAssertEqual(relaunched.lastSynced, synced, "it is known before the new launch has synced")
        XCTAssertNil(relaunched.status, "what that pass did isn't")

        let day = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 14, minute: 5)))
        let shown = SyncCenter.formatted(day, now: day)
        XCTAssertTrue(shown.contains(day.formatted(.dateTime.month(.abbreviated))), "the day is shown, not the time alone")
        XCTAssertTrue(shown.contains(day.formatted(date: .omitted, time: .shortened)))
        XCTAssertFalse(shown.contains("2026"))
        XCTAssertTrue(SyncCenter.formatted(day, now: day.addingTimeInterval(400 * 86_400)).contains("2026"), "and the year once it isn't this one")
    }

    func testAFailedNotebookIsListedWithWhyAndThePassIsNotUpToDate() async throws {
        let id = try await makeNotebook("Physics", on: root)
        _ = try await LibrarySync.run(root: root, cloud: cloud)
        let synced = cloud.package(id).appending(path: "manifest.json")
        let whole = try Data(contentsOf: synced)
        try Data("{".utf8).write(to: synced)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults)
        await center.use(cloud, account: nil)
        await center.syncNow()
        let failure = SyncFailure(id: id, reason: .unreadable(inICloud: true))
        XCTAssertEqual(center.lastReport?.failed, [failure])
        XCTAssertEqual(center.lastReport?.open, [])
        XCTAssertEqual(center.lastReport?.arriving, [], "a copy that is there and won't read isn't waited for")
        XCTAssertFalse(center.isUpToDate)
        XCTAssertEqual(center.status, "1 notebook didn't sync")
        XCTAssertEqual(center.news.failed, [failure], "the library hears of it too")

        center.putAwayNews()
        XCTAssertTrue(center.news.isEmpty)
        await center.syncNow()
        XCTAssertTrue(center.news.isEmpty, "once put away, the same failure isn't shown again")

        try whole.write(to: synced)
        await center.syncNow()
        XCTAssertTrue(center.isUpToDate)
        XCTAssertEqual(center.status, "Everything is up to date")
        try Data("{".utf8).write(to: synced)
        await center.syncNow()
        XCTAssertEqual(center.news.failed, [failure], "after it has synced, failing again is news again")
    }

    func testANotebookNotYetUploadedOrAnUploadErrorIsNotUpToDate() async throws {
        let id = try await makeNotebook("Physics", on: root)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults)
        let uploads = OSAllocatedUnfairLock(initialState: CloudUploads(pending: [id]))
        center.readUploads = { _ in uploads.withLock { $0 } }
        await center.use(cloud, account: nil)
        await center.syncNow()
        XCTAssertEqual(center.lastReport?.pushed, [id])
        XCTAssertFalse(center.isUpToDate, "copied into the container isn't the same as in iCloud")
        XCTAssertEqual(center.status, "1 notebook sent, 1 notebook still uploading to iCloud")
        XCTAssertTrue(center.news.isEmpty, "still uploading isn't a failure")

        uploads.withLock { $0 = CloudUploads(pending: [id], problem: .full) }
        await center.syncNow()
        XCTAssertFalse(center.isUpToDate)
        XCTAssertEqual(center.status, "1 notebook not uploaded to iCloud")
        XCTAssertEqual(center.uploads.problem, .full)
        XCTAssertTrue(CloudUploads.Problem.full.message.contains("iCloud storage is full"), "it says plainly that iCloud is full")
        XCTAssertEqual(center.news.uploadProblem, .full)

        uploads.withLock { $0 = CloudUploads() }
        await center.syncNow()
        XCTAssertTrue(center.isUpToDate)
        XCTAssertEqual(center.status, "Everything is up to date")
        XCTAssertNil(center.news.uploadProblem)
    }

    func testWhatIsStillToUploadIsReadFromEveryFileInTheSyncedCopy() async throws {
        let id = try await makeNotebook("Physics", on: root), other = try await makeNotebook("Chemistry", on: root)
        var folders = FolderFile()
        folders.folders = [FolderEntry(id: UUID(), name: "Science", clothRaw: "jade", createdAt: .now, sortIndex: 0)]
        try folders.write(root)
        _ = try await LibrarySync.run(root: root, cloud: cloud)
        try Data().write(to: cloud.package(other).appending(path: ".page.json.icloud"))
        let notUploaded = cloud.package(id).appending(path: "manifest.json").standardizedFileURL
        func read(_ word: (URL) -> (uploaded: Bool?, error: (any Error)?)) -> CloudUploads { CloudUploads.read(cloud, values: word) }

        XCTAssertEqual(read { _ in (nil, nil) }, CloudUploads(), "a plain folder has nothing to upload")
        XCTAssertEqual(read { _ in (true, nil) }, CloudUploads())
        XCTAssertEqual(read { ($0.standardizedFileURL == notUploaded ? false : true, nil) }, CloudUploads(pending: [id]))
        let full = NSError(domain: NSCocoaErrorDomain, code: NSUbiquitousFileNotUploadedDueToQuotaError)
        XCTAssertEqual(read { $0.standardizedFileURL == notUploaded ? (false, full) : (true, nil) }, CloudUploads(pending: [id], problem: .full))
        let away = NSError(domain: NSCocoaErrorDomain, code: NSUbiquitousFileUbiquityServerNotAvailable)
        XCTAssertEqual(read { $0.lastPathComponent == "folders.json" ? (false, away) : (true, nil) }, CloudUploads(othersPending: true, problem: .unreachable))
        XCTAssertEqual(read { $0.lastPathComponent.hasSuffix(".icloud") ? (false, full) : (true, nil) }, CloudUploads(), "a placeholder stands for a file iCloud has")
    }

    func testAConflictedCopyIsNewsForTheLibraryUntilPutAway() async throws {
        let id = try await makeNotebook("Notes", on: root), there = temporaryRoot(self)
        _ = try await LibrarySync.run(root: root, cloud: cloud)
        _ = try await LibrarySync.run(root: there, cloud: cloud)
        _ = try await NotebookPackage(root: root, id: id).updateManifest { $0.modifiedAt = $0.modifiedAt.addingTimeInterval(60) }
        _ = try await NotebookPackage(root: there, id: id).updateManifest { $0.modifiedAt = $0.modifiedAt.addingTimeInterval(120) }
        _ = try await LibrarySync.run(root: there, cloud: cloud)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults)
        await center.use(cloud, account: nil)
        await center.syncNow()
        let copy = try XCTUnwrap(center.lastReport?.conflictCopies.first)
        XCTAssertEqual(center.news.conflictCopies, [copy])
        XCTAssertTrue(center.news.failed.isEmpty)

        await center.syncNow()
        XCTAssertEqual(center.news.conflictCopies, [copy], "a pass with nothing new doesn't take it down")
        XCTAssertEqual(SyncCenter(root: root, defaults: defaults).news.conflictCopies, [copy], "nor does quitting before it was seen")
        center.putAwayNews()
        XCTAssertTrue(center.news.isEmpty)
        await center.syncNow()
        XCTAssertTrue(center.news.isEmpty)
        XCTAssertTrue(SyncCenter(root: root, defaults: defaults).news.isEmpty)
    }

    func testAJournalThatGaveWayIsSaidOnceUntilPutAway() async throws {
        let id = try await makeNotebook("Journal", on: root)
        let center = SyncCenter(root: root, defaults: defaults)
        center.noteJournalSetAside(id)
        center.noteJournalSetAside(id)
        XCTAssertEqual(center.news.journals, [id], "said once")
        XCTAssertEqual(center.news.count, 1)
        XCTAssertFalse(center.news.isTrouble, "it is worth knowing, not something wrong")
        XCTAssertEqual(SyncCenter(root: root, defaults: defaults).news.journals, [id], "a quit before it was seen doesn't lose it")
        XCTAssertTrue(center.news.keeping { $0 != id }.isEmpty, "a notebook deleted since has nothing to show")
        center.putAwayNews()
        XCTAssertTrue(center.news.isEmpty)
        XCTAssertTrue(SyncCenter(root: root, defaults: defaults).news.isEmpty)
    }

    func testNotebooksHeldBackFromDeletingAreTroubleUntilKept() async throws {
        var ids: [UUID] = []
        for title in ["One", "Two", "Three", "Four"] { ids.append(try await makeNotebook(title, on: root)) }
        _ = try await LibrarySync.run(root: root, cloud: cloud)
        for id in ids { try FileManager.default.removeItem(at: root.package(id)) }
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults)
        await center.use(cloud, account: nil)
        await center.syncNow()
        XCTAssertEqual(Set(center.news.held), Set(ids))
        XCTAssertTrue(center.news.isTrouble)
        XCTAssertEqual(center.news.count, 1, "said in one row")
        XCTAssertFalse(center.isUpToDate)
        XCTAssertEqual(center.status, "4 deletions held back")
        XCTAssertTrue(ids.allSatisfy { synced($0, in: cloud) })

        await center.keepHeld()
        XCTAssertEqual(Set(root.packageIDs()), Set(ids), "kept, they come back")
        XCTAssertTrue(center.news.isEmpty)
        XCTAssertTrue(center.isUpToDate)

        for id in ids { try FileManager.default.removeItem(at: root.package(id)) }
        await center.syncNow()
        XCTAssertEqual(Set(center.news.held), Set(ids))
        center.putAwayNews()
        await center.syncNow()
        XCTAssertTrue(center.news.isEmpty, "once put away, the same ones aren't shown again")
        XCTAssertTrue(ids.allSatisfy { synced($0, in: cloud) }, "and they are still held")
    }

    func testNotebooksHeldBackFromDeletingCanBeLetGo() async throws {
        var ids: [UUID] = []
        for title in ["One", "Two", "Three", "Four"] { ids.append(try await makeNotebook(title, on: root)) }
        _ = try await LibrarySync.run(root: root, cloud: cloud)
        for id in ids { try FileManager.default.removeItem(at: root.package(id)) }
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults)
        await center.use(cloud, account: nil)
        await center.syncNow()
        XCTAssertEqual(Set(center.news.held), Set(ids))

        await center.letHeldGo()
        XCTAssertEqual(Set(center.lastReport?.removedThere ?? []), Set(ids), "let go, the deletes are carried over")
        XCTAssertFalse(ids.contains { synced($0, in: cloud) })
        XCTAssertTrue(center.news.isEmpty)
        XCTAssertTrue(center.isUpToDate)
        XCTAssertEqual(center.status, "4 deletions carried over")
        await center.syncNow()
        XCTAssertTrue(center.news.isEmpty, "and they aren't held again")
        XCTAssertEqual(root.packageIDs(), [])
        XCTAssertEqual(center.status, "Everything is up to date")
    }

    func testAFolderListInICloudThatCannotBeReadIsTroubleUntilPutAway() async throws {
        var folders = FolderFile()
        folders.folders = [FolderEntry(id: UUID(), name: "Science", clothRaw: "jade", createdAt: .now, sortIndex: 0)]
        try folders.write(root)
        _ = try await LibrarySync.run(root: root, cloud: cloud)
        let good = try Data(contentsOf: cloud.foldersFile)
        try Data("damaged".utf8).write(to: cloud.foldersFile)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults)
        await center.use(cloud, account: nil)
        await center.syncNow()
        XCTAssertTrue(center.news.foldersUnreadable)
        XCTAssertTrue(center.news.isTrouble)
        XCTAssertEqual(center.news.count, 1)
        XCTAssertFalse(center.isUpToDate)
        XCTAssertEqual(center.status, "Folders aren't syncing")

        center.putAwayNews()
        await center.syncNow()
        XCTAssertTrue(center.news.isEmpty, "once put away, it isn't shown again while it lasts")
        XCTAssertFalse(center.isUpToDate, "though Settings still says so")

        try good.write(to: cloud.foldersFile)
        await center.syncNow()
        XCTAssertTrue(center.isUpToDate)
        try Data("damaged".utf8).write(to: cloud.foldersFile)
        await center.syncNow()
        XCTAssertTrue(center.news.foldersUnreadable, "damaged again, it is news again")
    }

    func testAFolderListInICloudThatCannotBeReadIsReplacedWhenAsked() async throws {
        var folders = FolderFile()
        folders.folders = [FolderEntry(id: UUID(), name: "Science", clothRaw: "jade", createdAt: .now, sortIndex: 0)]
        try folders.write(root)
        _ = try await LibrarySync.run(root: root, cloud: cloud)
        try Data("damaged".utf8).write(to: cloud.foldersFile)
        defaults.set(true, forKey: SettingsKey.syncsWithICloud)
        let center = SyncCenter(root: root, defaults: defaults)
        await center.use(cloud, account: nil)
        await center.syncNow()
        XCTAssertTrue(center.news.foldersUnreadable)

        await center.replaceFolders()
        XCTAssertTrue(center.news.isEmpty)
        XCTAssertTrue(center.isUpToDate)
        XCTAssertEqual(FolderFile(try Data(contentsOf: cloud.foldersFile))?.folders.map(\.name), ["Science"])

        try Data("damaged".utf8).write(to: cloud.foldersFile)
        await center.syncNow()
        XCTAssertTrue(center.news.foldersUnreadable, "replaced once, it isn't replaced again unasked")
        XCTAssertEqual(try String(contentsOf: cloud.foldersFile, encoding: .utf8), "damaged")
    }
}
