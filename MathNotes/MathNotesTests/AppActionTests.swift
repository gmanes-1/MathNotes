import XCTest
import PencilKit
import SwiftData
@testable import OwlLuna

/// Widget links and shortcuts, and the snapshot the widgets read.
@MainActor
final class AppActionTests: XCTestCase {
    private var container: ModelContainer?

    private func makeStore() throws -> LibraryStore {
        let schema = LibraryIndex.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        self.container = container
        return LibraryStore(root: temporaryRoot(self), context: container.mainContext)
    }

    private func makeNotebook(_ title: String, in store: LibraryStore, opened: Date?, pages: Int = 3, currentPage: Int = 0) async throws -> UUID {
        let paper = PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter)
        var manifest = NotebookManifest(title: title, cover: CoverSpec(style: .cloth, cloth: .moss, inks: (.teal, .pink), seed: 1), defaults: paper,
                                        pages: (0..<pages).map { _ in paper.newPage() })
        manifest.library.lastOpenedAt = opened
        manifest.library.currentPage = currentPage
        try await NotebookPackage(root: store.root, id: manifest.id).create(manifest)
        store.index(manifest)
        return manifest.id
    }

    func testLinksBecomeActions() throws {
        let id = UUID()
        XCTAssertEqual(AppAction(url: URL(string: "owlluna://today")!), .today)
        XCTAssertEqual(AppAction(url: URL(string: "owlluna://quicknote")!), .quickNote)
        XCTAssertEqual(AppAction(url: URL(string: "owlluna://continue")!), .continueWriting)
        XCTAssertEqual(AppAction(url: URL(string: "owlluna://notebook/\(id.uuidString)")!), .open(id))
        let page = UUID()
        XCTAssertEqual(AppAction(url: try XCTUnwrap(AppAction.url(forNotebook: id, page: page))), .open(id, page: page), "a link in an exported PDF comes back to its page")
        XCTAssertEqual(AppAction(url: try XCTUnwrap(AppAction.url(forNotebook: id))), .open(id))
        XCTAssertNil(AppAction(url: URL(string: "owlluna://notebook/not-an-id")!))
        XCTAssertNil(AppAction(url: URL(string: "owlluna://delete-everything")!))
        XCTAssertNil(AppAction(url: URL(string: "https://today")!))
    }

    func testTheSnapshotNamesTheNotebookLastOpenedAndRecentDaysOnly() async throws {
        let store = try makeStore()
        let now = Date.now, calendar = Calendar.current
        _ = try await makeNotebook("Older", in: store, opened: now.addingTimeInterval(-86_400))
        let latest = try await makeNotebook("Cell Biology", in: store, opened: now, pages: 12, currentPage: 4)
        let binned = try await makeNotebook("Binned", in: store, opened: now.addingTimeInterval(60))
        store.moveToTrash([try XCTUnwrap(store.record(binned))])
        _ = try await makeNotebook("Never opened", in: store, opened: nil)

        let suite = "widget-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let activity = WritingActivity(root: store.root, defaults: defaults)
        activity.record(notebook: latest, pages: [UUID(), UUID()], at: now)
        activity.record(notebook: latest, pages: [UUID()], at: try XCTUnwrap(calendar.date(byAdding: .day, value: -100, to: now)))

        var snapshot = await WidgetBridge.snapshot(library: store, activity: activity, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.notebook, .init(id: latest, title: "Cell Biology", page: 5, pageCount: 12, clothHex: ClothColor.moss.hex))
        XCTAssertEqual(snapshot.pagesByDay, [WidgetSnapshot.dayKey(for: now, calendar: calendar): 2], "a day from months ago isn't sent")
        XCTAssertFalse(snapshot.journalIsWritten(on: now, calendar: calendar), "writing in another notebook doesn't tick today's page")
        XCTAssertEqual(store.notebooks().count, 3)

        activity.isEnabled = false
        snapshot = await WidgetBridge.snapshot(library: store, activity: activity, now: now, calendar: calendar)
        XCTAssertTrue(snapshot.pagesByDay.isEmpty, "with writing history off, the widgets get no days")
    }

    private func keepJournalSetting() {
        let saved = UserDefaults.standard.object(forKey: SettingsKey.dailyJournalID)
        addTeardownBlock { UserDefaults.standard.set(saved, forKey: SettingsKey.dailyJournalID) }
    }

    private func journalDay() throws -> (Date, Calendar) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        return (try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9))), calendar)
    }

    private var line: PKDrawing { PKDrawing(strokes: [stroke(from: CGPoint(x: 80, y: 200), to: CGPoint(x: 300, y: 210))]) }

    func testTodaysPageTicksForInkOnTheJournalsPageWhateverWritingHistoryKeeps() async throws {
        let store = try makeStore()
        keepJournalSetting()
        let (now, calendar) = try journalDay()
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let suite = "widget-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let activity = WritingActivity(root: store.root, defaults: defaults)
        let biology = try await makeNotebook("Biology", in: store, opened: now)
        activity.record(notebook: biology, pages: [UUID()], at: now)
        let journal = try await store.createDailyJournal(now: now, calendar: calendar)

        var snapshot = await WidgetBridge.snapshot(library: store, activity: activity, now: now, calendar: calendar)
        XCTAssertFalse(snapshot.pagesByDay.isEmpty)
        XCTAssertNil(snapshot.journalWrittenDay, "today's page is still blank, whatever was written elsewhere")

        let package = NotebookPackage(root: store.root, id: journal)
        let manifest = try await package.readManifest().manifest
        store.index(try await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: line])).manifest)
        activity.isEnabled = false
        snapshot = await WidgetBridge.snapshot(library: store, activity: activity, now: now, calendar: calendar)
        XCTAssertTrue(snapshot.pagesByDay.isEmpty)
        XCTAssertEqual(snapshot.journalWrittenDay, "2026-10-14", "with writing history off, today's page still ticks")
        XCTAssertTrue(snapshot.journalIsWritten(on: now, calendar: calendar))
        XCTAssertFalse(snapshot.journalIsWritten(on: tomorrow, calendar: calendar), "the tick comes off at midnight")

        snapshot = await WidgetBridge.snapshot(library: store, activity: activity, now: tomorrow, calendar: calendar)
        XCTAssertNil(snapshot.journalWrittenDay, "yesterday's page doesn't count for today")

        store.setLocked(true, for: [try XCTUnwrap(store.record(journal))])
        snapshot = await WidgetBridge.snapshot(library: store, activity: activity, now: now, calendar: calendar)
        XCTAssertNil(snapshot.journalWrittenDay, "a locked journal tells the widgets nothing")
    }

    func testAnOpenJournalTicksForInkNotYetSaved() async throws {
        let store = try makeStore()
        keepJournalSetting()
        let (now, calendar) = try journalDay()
        let activity = WritingActivity(root: store.root)
        let journal = try await store.createDailyJournal(now: now, calendar: calendar)
        let document = try await DocumentRegistry.shared.open(journal, root: store.root, scene: nil) { _ in }
        addTeardownBlock { @MainActor in DocumentRegistry.shared.unregister(journal, document: document) }
        let page = try XCTUnwrap(document.pages.first)
        _ = await document.ink(page.id)

        var snapshot = await WidgetBridge.snapshot(library: store, activity: activity, now: now, calendar: calendar)
        XCTAssertNil(snapshot.journalWrittenDay)
        document.canvasDidChangeInk(page.id, to: line)
        XCTAssertNil(document.pages[0].inkHash, "not saved yet")
        snapshot = await WidgetBridge.snapshot(library: store, activity: activity, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.journalWrittenDay, "2026-10-14")
        document.canvasDidChangeInk(page.id, to: PKDrawing())
        snapshot = await WidgetBridge.snapshot(library: store, activity: activity, now: now, calendar: calendar)
        XCTAssertNil(snapshot.journalWrittenDay, "rubbed out again")
        await document.flush()
    }

    func testASnapshotSavedByAnEarlierBuildStillReads() throws {
        let directory = temporaryRoot(self).url, id = UUID()
        let earlier = #"{"notebook":{"id":"\#(id.uuidString)","title":"Cell Biology","page":5,"pageCount":12,"clothHex":4020800},"pagesByDay":{"2026-10-01":2},"hasJournal":true}"#
        try Data(earlier.utf8).write(to: directory.appending(path: "widget.json"))
        let snapshot = try XCTUnwrap(WidgetSnapshot.read(from: directory))
        XCTAssertEqual(snapshot.notebook, .init(id: id, title: "Cell Biology", page: 5, pageCount: 12, clothHex: 0x3D5A40))
        XCTAssertEqual(snapshot.pagesByDay, ["2026-10-01": 2])
        XCTAssertNil(snapshot.journalWrittenDay)
    }

    func testTheSnapshotRoundTripsAndCountsTheWeekAndTheRun() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        calendar.firstWeekday = 1
        let thursday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9)))
        XCTAssertEqual(WidgetSnapshot.dayKey(for: thursday, calendar: calendar), "2026-10-01")
        XCTAssertEqual(WidgetSnapshot.dayKey(for: thursday, calendar: calendar), ActivityFile.dayKey(for: thursday, calendar: calendar))

        var snapshot = WidgetSnapshot()
        snapshot.pagesByDay = ["2026-09-28": 3, "2026-09-29": 1, "2026-09-30": 2]
        let week = snapshot.week(containing: thursday, calendar: calendar)
        XCTAssertEqual(week.map(\.pages), [0, 3, 1, 2, 0, 0, 0])
        XCTAssertEqual(week.map(\.isToday), [false, false, false, false, true, false, false])
        XCTAssertEqual(snapshot.run(endingAt: thursday, calendar: calendar), 3, "today is still blank, so the run ends yesterday")
        snapshot.pagesByDay["2026-10-01"] = 1
        XCTAssertEqual(snapshot.run(endingAt: thursday, calendar: calendar), 4)
        snapshot.pagesByDay["2026-09-29"] = nil
        XCTAssertEqual(snapshot.run(endingAt: thursday, calendar: calendar), 2)
        XCTAssertEqual(WidgetSnapshot().run(endingAt: thursday, calendar: calendar), 0)

        XCTAssertFalse(snapshot.journalIsWritten(on: thursday, calendar: calendar), "pages written today don't tick the journal's page")
        snapshot.journalWrittenDay = "2026-10-01"
        XCTAssertTrue(snapshot.journalIsWritten(on: thursday, calendar: calendar))
        XCTAssertFalse(snapshot.journalIsWritten(on: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: thursday)), calendar: calendar))

        let directory = temporaryRoot(self).url
        try snapshot.write(to: directory)
        XCTAssertEqual(WidgetSnapshot.read(from: directory), snapshot)
        XCTAssertNil(WidgetSnapshot.read(from: directory.appending(path: "missing")))
    }

    func testSiriIsOfferedNeitherLockedNorDeletedNotebooks() async throws {
        let store = try makeStore()
        let biology = try await makeNotebook("Biology", in: store, opened: .now)
        let untitled = try await makeNotebook("", in: store, opened: .now.addingTimeInterval(-3_600))
        let diary = try await makeNotebook("Diary", in: store, opened: .now)
        let binned = try await makeNotebook("Binned", in: store, opened: .now)
        store.setLocked(true, for: [try XCTUnwrap(store.record(diary))])
        store.moveToTrash([try XCTUnwrap(store.record(binned))])

        let suggested = NotebookQuery.suggested(store)
        XCTAssertEqual(suggested.map(\.id), [biology, untitled])
        XCTAssertEqual(suggested.map(\.title), ["Biology", "Untitled"])
        XCTAssertEqual(Set(NotebookQuery.identified([biology, diary, binned], in: store).map(\.id)), [biology, diary],
                       "a shortcut made before its notebook was locked still finds it, but not one in Recently Deleted")
    }

    func testSiriLearnsTheNotebookNamesOnceAfterStartThenOncePerChangeToThem() async throws {
        let store = try makeStore()
        let biologyID = try await makeNotebook("Biology", in: store, opened: .now)
        let chemistryID = try await makeNotebook("Chemistry", in: store, opened: nil)
        let physics = try await makeNotebook("Physics", in: store, opened: nil)
        let biology = try XCTUnwrap(store.record(biologyID)), chemistry = try XCTUnwrap(store.record(chemistryID))
        var updates = 0
        let parameters = ShortcutParameters(isLive: true, delay: .milliseconds(20)) { updates += 1 }
        func settle() async throws { try await Task.sleep(for: .milliseconds(200)) }

        parameters.start(store)
        XCTAssertEqual(updates, 1, "once the library is ready")
        parameters.start(store)
        XCTAssertEqual(updates, 1)

        store.setTags(["exam"], for: [biology])
        store.setCover(CoverSpec(style: .cloth, cloth: .plum, inks: (.teal, .pink), seed: 2), for: chemistry)
        try await settle()
        XCTAssertEqual(updates, 1, "a save that leaves the names alone isn't passed on")

        store.rename(biology, to: "Cell Biology")
        store.rename(chemistry, to: "Organic Chemistry")
        store.setLocked(true, for: [biology])
        try await settle()
        XCTAssertEqual(updates, 2, "changes made together are told once")

        store.moveToTrash([chemistry])
        try await settle()
        XCTAssertEqual(updates, 3)

        try await Task.sleep(for: .milliseconds(20))
        _ = try await NotebookPackage(root: store.root, id: physics).updateManifest { $0.title = "Astrophysics"; $0.modifiedAt = .now }
        await store.reloadFromDisk()
        try await settle()
        XCTAssertEqual(updates, 4, "a name changed on another device")
        XCTAssertEqual(NotebookQuery.suggested(store).map(\.title), ["Astrophysics"])

        await store.reloadFromDisk()
        try await settle()
        XCTAssertEqual(updates, 4, "a sync that changed nothing")
    }

    func testAWindowRemembersWhatItHasOpenUntilItIsGone() {
        let scene = "test-\(UUID().uuidString)", other = "test-\(UUID().uuidString)"
        let notebook = UUID(), beside = UUID()
        XCTAssertNil(WindowMemory.remembered(in: scene), "a window never seen falls back to what iPadOS saved for it")
        WindowMemory.remember(notebook, beside: beside, in: scene)
        WindowMemory.remember(nil, beside: beside, in: other)
        XCTAssertEqual(WindowMemory.remembered(in: scene)?.notebook, notebook)
        XCTAssertEqual(WindowMemory.remembered(in: scene)?.beside, beside)
        let closed = WindowMemory.remembered(in: other)
        XCTAssertNotNil(closed, "a window whose notebook was closed says so, so an older saved state can't reopen one")
        XCTAssertNil(closed?.notebook)
        XCTAssertNil(closed?.beside)
        WindowMemory.keep(only: [other])
        XCTAssertNil(WindowMemory.remembered(in: scene))
        WindowMemory.keep(only: Set(UIApplication.shared.openSessions.map(\.persistentIdentifier)))
        XCTAssertNil(WindowMemory.remembered(in: other))
    }
}
