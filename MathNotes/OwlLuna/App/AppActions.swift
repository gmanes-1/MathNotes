import AppIntents
import SwiftData
import Observation

/// Something asked of the app from outside its windows: a widget link, a shortcut, Siri.
enum AppAction: Equatable, Sendable {
    case today, quickNote, continueWriting
    case open(UUID, page: UUID? = nil)

    static let scheme = "owlluna"

    /// The address that opens a notebook, at one of its pages if given. Links in exported PDFs use it.
    static func url(forNotebook id: UUID, page: UUID? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "notebook"
        components.path = "/\(id.uuidString)"
        if let page { components.queryItems = [URLQueryItem(name: "page", value: page.uuidString)] }
        return components.url
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host() {
        case "today": self = .today
        case "quicknote": self = .quickNote
        case "continue": self = .continueWriting
        case "notebook":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value
            self = .open(id, page: page.flatMap(UUID.init(uuidString:)))
        default: return nil
        }
    }
}

extension Notification.Name {
    /// Asks the editor showing a notebook (object: its ID) to save and close.
    static let mathNotesCloseEditor = Notification.Name("MathNotesCloseEditor")
    /// Tells the editor showing a notebook (object: its ID) that a sync set its document aside for a newer version, to open again.
    static let mathNotesReopenNotebook = Notification.Name("MathNotesReopenNotebook")
}

extension LibraryStore {
    /// The notebook last opened that is still on the shelves.
    var lastOpenedNotebook: NotebookRecord? { lastOpenedNotebook(includingLocked: true) }

    /// A locked notebook is never what a widget shows.
    func lastOpenedNotebook(includingLocked: Bool) -> NotebookRecord? {
        notebooks().filter { $0.lastOpenedAt != nil && (includingLocked || !$0.isLocked) }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    /// Every notebook that isn't in Recently Deleted.
    func notebooks() -> [NotebookRecord] {
        ((try? context.fetch(FetchDescriptor<NotebookRecord>())) ?? []).filter { !$0.isTrashed }
    }
}

// MARK: Shortcuts

struct NotebookEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Notebook"
    static let defaultQuery = NotebookQuery()

    let id: UUID
    let title: String
    let pages: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(pages) pages")
    }

    @MainActor
    init(_ record: NotebookRecord) {
        id = record.id
        title = record.title.isEmpty ? String(localized: "Untitled") : record.title
        pages = record.pageCount
    }
}

struct NotebookQuery: EntityStringQuery {
    @MainActor
    private func library() async -> LibraryStore {
        await AppModel.shared.start()
        return AppModel.shared.library
    }

    /// The notebooks out of Recently Deleted, last used first.
    @MainActor
    static func recent(_ library: LibraryStore) -> [NotebookRecord] {
        library.notebooks().sorted { ($0.lastOpenedAt ?? $0.modifiedAt) > ($1.lastOpenedAt ?? $1.modifiedAt) }
    }

    /// What Siri and Shortcuts are offered to choose from. A locked notebook's name isn't handed out, as it isn't to Spotlight.
    @MainActor
    static func offered(_ records: [NotebookRecord], matching string: String? = nil) -> [NotebookRecord] {
        records.filter { !$0.isLocked && (string.map($0.title.localizedCaseInsensitiveContains) ?? true) }
    }

    /// The names Siri learns for "Open ‹notebook› in MathNotes".
    @MainActor
    static func suggested(_ library: LibraryStore) -> [NotebookEntity] {
        offered(recent(library)).prefix(24).map(NotebookEntity.init)
    }

    /// A shortcut made before its notebook was locked still finds it; opening it asks as the library does.
    @MainActor
    static func identified(_ identifiers: [UUID], in library: LibraryStore) -> [NotebookEntity] {
        recent(library).filter { identifiers.contains($0.id) }.map(NotebookEntity.init)
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [NotebookEntity] {
        Self.identified(identifiers, in: await library())
    }

    @MainActor
    func suggestedEntities() async throws -> [NotebookEntity] {
        Self.suggested(await library())
    }

    @MainActor
    func entities(matching string: String) async throws -> [NotebookEntity] {
        Self.offered(Self.recent(await library()), matching: string).map(NotebookEntity.init)
    }
}

/// Tells Siri the names "Open ‹notebook› in MathNotes" can take: once the library is ready, then after a run of index
/// saves that changes them. UI-test libraries never reach Siri.
@MainActor
final class ShortcutParameters {
    private let isLive: Bool
    private let delay: Duration
    private let update: () -> Void
    private weak var library: LibraryStore?
    private var told: [UUID: String]?
    private var pending: Task<Void, Never>?

    init(isLive: Bool = !LaunchOptions.usesTestStorage, delay: Duration = .seconds(2),
         update: @escaping () -> Void = { MathNotesShortcuts.updateAppShortcutParameters() }) {
        self.isLive = isLive
        self.delay = delay
        self.update = update
    }

    func start(_ library: LibraryStore) {
        guard isLive, self.library == nil else { return }
        self.library = library
        tellIfChanged()
        watch()
    }

    private func watch() {
        guard let library else { return }
        withObservationTracking { _ = library.indexVersion } onChange: { [weak self] in
            Task { @MainActor in self?.indexSaved() }
        }
    }

    private func indexSaved() {
        watch()
        pending?.cancel()
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.tellIfChanged()
        }
    }

    private func tellIfChanged() {
        guard let library else { return }
        let names = Dictionary(NotebookQuery.suggested(library).map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        guard names != told else { return }
        told = names
        update()
    }
}

struct OpenTodayPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Today's Journal Page"
    static let description = IntentDescription("Opens today's page in your daily journal, starting a journal if you don't have one yet.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.pendingAction = .today
        return .result()
    }
}

struct QuickNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Quick Note"
    static let description = IntentDescription("Starts a new notebook on your default paper and opens it, ready to write.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.pendingAction = .quickNote
        return .result()
    }
}

struct ContinueWritingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Writing"
    static let description = IntentDescription("Opens the notebook you last wrote in, at the page you left.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.pendingAction = .continueWriting
        return .result()
    }
}

struct OpenNotebookIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Notebook"
    static let description = IntentDescription("Opens one of your notebooks.")
    static let openAppWhenRun = true

    @Parameter(title: "Notebook")
    var notebook: NotebookEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.pendingAction = .open(notebook.id)
        return .result()
    }
}

struct MathNotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenTodayPageIntent(),
                    phrases: ["Open today's page in \(.applicationName)", "Write in my \(.applicationName) journal"],
                    shortTitle: "Today's Page", systemImageName: "calendar")
        AppShortcut(intent: QuickNoteIntent(),
                    phrases: ["New quick note in \(.applicationName)", "Start a note in \(.applicationName)"],
                    shortTitle: "Quick Note", systemImageName: "square.and.pencil")
        AppShortcut(intent: ContinueWritingIntent(),
                    phrases: ["Continue writing in \(.applicationName)"],
                    shortTitle: "Continue Writing", systemImageName: "book")
        AppShortcut(intent: OpenNotebookIntent(),
                    phrases: ["Open a notebook in \(.applicationName)", "Open \(\.$notebook) in \(.applicationName)"],
                    shortTitle: "Open Notebook", systemImageName: "books.vertical")
    }
}
