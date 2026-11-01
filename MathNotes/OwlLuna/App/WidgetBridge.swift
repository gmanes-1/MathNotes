import SwiftUI
import WidgetKit

/// Keeps the widgets' snapshot current. Nothing leaves the device: the snapshot sits in the app's own shared container.
@MainActor
enum WidgetBridge {
    private static var lastWritten: WidgetSnapshot?
    private static var lastCoverKey: String?

    static func snapshot(library: LibraryStore, activity: WritingActivity, now: Date = .now, calendar: Calendar = .current) async -> WidgetSnapshot {
        var snapshot = WidgetSnapshot()
        if let record = library.lastOpenedNotebook(includingLocked: false) {
            snapshot.notebook = .init(id: record.id, title: record.title.isEmpty ? String(localized: "Untitled") : record.title,
                                      page: min(record.currentPage + 1, max(record.pageCount, 1)), pageCount: record.pageCount, clothHex: record.cloth.hex)
        }
        if activity.isEnabled, let start = calendar.date(byAdding: .day, value: -60, to: now) {
            let first = WidgetSnapshot.dayKey(for: start, calendar: calendar)
            for (key, day) in activity.log.days where key >= first && day.pageCount > 0 { snapshot.pagesByDay[key] = day.pageCount }
        }
        let today = WidgetSnapshot.dayKey(for: now, calendar: calendar)
        if await journalHasWriting(on: today, library: library) { snapshot.journalWrittenDay = today }
        return snapshot
    }

    /// Read from the open journal, ink not yet saved included, or else from its manifest. A locked journal says nothing.
    private static func journalHasWriting(on day: String, library: LibraryStore) async -> Bool {
        guard let journal = library.dailyJournal, !journal.isLocked else { return false }
        if let document = DocumentRegistry.shared.document(for: journal.id) {
            guard let page = document.pages.last(where: { $0.day == day }) else { return false }
            return document.loadedInk(page.id).map { !$0.strokes.isEmpty } ?? (page.inkHash != nil)
        }
        let pages = try? await NotebookPackage(root: library.root, id: journal.id).readManifest().manifest.pages
        return pages?.last(where: { $0.day == day })?.inkHash != nil
    }

    /// Writes the cover of the notebook the widget names, and takes the last one away when it names none, so a notebook
    /// that was locked or deleted doesn't leave its cover behind. Returns whether the file changed.
    static func writeCover(of record: NotebookRecord?, root: StorageRoot, to directory: URL) async -> Bool {
        let file = directory.appending(path: WidgetSnapshot.coverFile)
        guard let record else {
            lastCoverKey = nil
            guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return false }
            try? FileManager.default.removeItem(at: file)
            return true
        }
        let request = record.coverRequest(width: 176, scale: 2, colorScheme: .light, contrast: .standard, root: root)
        guard request.key != lastCoverKey, let png = await CoverCache.shared.image(for: request)?.pngData() else { return false }
        try? png.write(to: file, options: .atomic)
        lastCoverKey = request.key
        return true
    }

    /// UI-test libraries never reach the widgets.
    static func update(_ app: AppModel) async {
        guard app.phase == .ready, !LaunchOptions.usesTestStorage, let directory = WidgetSnapshot.directory else { return }
        let snapshot = await snapshot(library: app.library, activity: app.activity)
        let coverChanged = await writeCover(of: app.library.lastOpenedNotebook(includingLocked: false), root: app.root, to: directory)
        guard snapshot != lastWritten || coverChanged else { return }
        do {
            try snapshot.write(to: directory)
            lastWritten = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            return
        }
    }
}
