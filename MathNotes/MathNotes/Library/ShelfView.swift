import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct Shelf: Identifiable {
    let id: String
    let title: String
    let records: [NotebookRecord]
    var cloth: ClothColor?
}

struct ShelfView: View {
    let scope: LibraryScope
    let zoomNamespace: Namespace.ID
    let onOpen: (NotebookRecord) -> Void
    let onOpenPage: (NotebookRecord, UUID) -> Void
    let onOpenZoomed: (NotebookRecord, UUID?, String) -> Void
    let onCreate: () -> Void
    let onQuickNote: () -> Void
    let onWhiteboard: () -> Void
    let isCovered: Bool

    @Environment(LibraryStore.self) private var store
    @Environment(FlashcardLibrary.self) private var flashcards
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.undoManager) private var undoManager
    @Environment(LibraryChangeCenter.self) private var changes
    @Environment(AppModel.self) private var app: AppModel?
    @Query private var records: [NotebookRecord]
    @Query(sort: \FolderRecord.sortIndex) private var folders: [FolderRecord]
    @AppStorage(SettingsKey.librarySort) private var sort: LibrarySortOrder = .modified
    @AppStorage(SettingsKey.librarySortReversed) private var sortReversed = false
    @AppStorage("libraryLayout.goodnotes.v1") private var layout: LibraryLayout = .shelf
    @AppStorage("libraryGrouping") private var grouping: LibraryGrouping = .recency
    @AppStorage(SettingsKey.dailyJournalID) private var journalID = ""
    @AppStorage(SettingsKey.trashLength) private var trashLength: TrashLength = .initial
    @State private var searchText = ""
    @State private var matches: Set<UUID>?
    @State private var pageHits: [UUID: [PageHit]] = [:]
    @State private var hitsQuery = ""
    @State private var tagPages: [UUID: [PageHit]] = [:]
    @State private var tagging: NotebookRecord?
    @State private var taggingSelection: SelectionTags?
    @State private var searchPending = false
    @State private var export: ExportJob?
    @State private var editingCover: NotebookRecord?
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var importingPDF = false
    @State private var scanning = false
    @State private var renaming: NotebookRecord?
    @State private var renameText = ""
    @State private var confirmingEmptyTrash = false
    @State private var errorMessage: String?
    @State private var shelfWidth: CGFloat?
    @State private var listWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    @State private var showsBarTitle = false
    @FocusState private var searchFocused: Bool
    @State private var barRoom = CGFloat.infinity
    @State private var actionsWidth: CGFloat = 0
    @State private var openingJournal = false

    private var folder: FolderRecord? {
        if case .folder(let id) = scope { return folders.first { $0.id == id } }
        return nil
    }

    private var title: String {
        switch scope {
        case .all: String(localized: "Notes")
        case .favorites: String(localized: "Favorites")
        case .trash: String(localized: "Recently Deleted")
        case .folder: folder?.name ?? String(localized: "Folder")
        case .tag(let name): name
        case .smart(let id): store.smartShelves.first { $0.id == id }?.name ?? String(localized: "Smart Shelf")
        }
    }

    /// What a tag shelf or a smart shelf looks for. A smart shelf that has been deleted looks for nothing.
    private var rule: TagRule? {
        switch scope {
        case .tag(let name): TagRule(tags: [name])
        case .smart(let id): store.smartShelves.first { $0.id == id }?.rule ?? TagRule(tags: [])
        case .all, .favorites, .trash, .folder: nil
        }
    }

    private var tree: FolderTree { FolderTree(folders: folders) }

    private var filter: ShelfFilter { ShelfFilter(scope: scope, tree: tree, rule: rule, matches: matches, sort: sort, reversed: sortReversed) }

    private var visible: [NotebookRecord] { filter.shown(records) }

    /// Matches titles and handwriting on a background context, a moment after typing stops, so neither the
    /// keystroke nor a library full of PDF text ever scans on the main thread.
    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            matches = nil
            pageHits = [:]
            searchPending = false
            return
        }
        if query != hitsQuery { pageHits = [:] }
        searchPending = true
        defer { if !Task.isCancelled { searchPending = false } }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let container = context.container
        let found = await Task.detached(priority: .userInitiated) { () -> Set<UUID> in
            LibraryIndex.notebookIDs(matching: query, in: ModelContext(container))
        }.value
        guard !Task.isCancelled else { return }
        // What is written in a locked notebook isn't searched: only its title and its own tags can match.
        let locked = records.filter(\.isLocked)
        let tag = Tags.normalized(query) ?? query
        let hidden = Set(locked.filter { record in
            !record.title.localizedStandardContains(query) && !record.tags.contains { $0.localizedStandardContains(tag) }
        }.map(\.id))
        matches = found.subtracting(hidden)
        guard scope != .trash else { pageHits = [:]; return }
        let closed = Set(locked.map(\.id))
        let ordered = visible.map(\.id).filter { found.contains($0) && !closed.contains($0) }
        let hits = await PageSearch.hits(for: query, in: ordered, root: store.root)
        guard !Task.isCancelled else { return }
        withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { pageHits = hits }
        hitsQuery = query
    }

    /// The tagged pages under a tag shelf. Manifests are read off the main thread, an open notebook's pages come from
    /// its document, and a locked notebook's pages are never listed.
    private func loadTagPages() async {
        guard let rule, !rule.tags.isEmpty else {
            if !tagPages.isEmpty { tagPages = [:] }
            return
        }
        let sources = records.filter { record in !record.isTrashed && !record.isLocked && rule.tags.contains { Tags.contains(record.pageTags, $0) } }
            .sorted(by: sort, reversed: sortReversed)
            .map { TagPages.Source(id: $0.id, tags: $0.tags, pages: DocumentRegistry.shared.document(for: $0.id)?.pages) }
        let hits = await TagPages.hits(for: rule, in: sources, root: store.root)
        guard !Task.isCancelled, hits != tagPages else { return }
        withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { tagPages = hits }
    }

    /// Tagged pages show under their notebooks, but not while searching.
    private var showsTagPages: Bool { rule != nil && searchText.isEmpty && !tagPages.isEmpty }

    private var tagPagesKey: String {
        "\(scope)|\(store.indexVersion)|" + (rule.map { "\($0.match.rawValue)|\(Tags.joined($0.tags))" } ?? "")
    }

    var body: some View {
        let visible = visible
        Group {
            if layout == .list {
                list(visible)
            } else if dynamicTypeSize.isAccessibilitySize {
                accessibleList(visible)
            } else {
                shelves(visible)
            }
        }
        .background(layout == .list ? Color(uiColor: .systemBackground) : Color.paper)
        .overlay { if visible.isEmpty, !showsTagPages, !searchPending { emptyState } }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !searchInBar {
                searchField
                    .padding(.horizontal, Space.x8)
                    .padding(.bottom, Space.x2)
                    .background(layout == .list ? Color(uiColor: .systemBackground) : Color.paper)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            let frame = proxy.frame(in: .global)
            return frame.width - (frame.minX > 1 ? 0 : 130)
        } action: { barRoom = $0 }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarTitleDisplayMode(.large)
        .barGround(Color(uiColor: .systemBackground))
        .background(SearchActivator(isSearching: searchFocused, isCovered: isCovered) { searchFocused = true })
        .toolbar { toolbar(visible) }
        .toolbar { if isSelecting { selectionBar(visible) } }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            Task { await importPDFs(result) }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                importScan(images)
            }
            .ignoresSafeArea()
        }
        .notice("Rename Notebook", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
        } actions: {
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let renaming { store.rename(renaming, to: renameText) } }
        }
        .notice("Delete all notebooks in Recently Deleted?", isPresented: $confirmingEmptyTrash, message: Text("This can't be undone.")) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) { store.deletePermanently(visible) }
        }
        .notice("Something went wrong", isPresented: Binding(get: { errorMessage != nil || store.lastError != nil || flashcards.lastError != nil },
                                                             set: { if !$0 { errorMessage = nil; store.clearError(); flashcards.clearError() } }),
                message: Text(errorMessage ?? store.lastError ?? flashcards.lastError ?? "")) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: scope) { _, _ in
            endSelection()
            tagPages = [:]
        }
        .onChange(of: sort) { _, _ in sortReversed = false }
        .task(id: "\(store.searchVersion)|\(records.count)|\(scope)|\(searchText)") { await runSearch() }
        .task(id: tagPagesKey) { await loadTagPages() }
        .sheet(item: $export) { job in ExportSheet(job: job).presentationCornerRadius(Radius.sheet) }
        .sheet(item: $editingCover) { record in CoverEditorView(record: record).presentationCornerRadius(Radius.sheet) }
        .sheet(item: $tagging) { record in
            TagSheet(subject: record.title.isEmpty ? String(localized: "Untitled") : record.title, initial: record.tags) { tags in
                changes.setTags(tags, for: record, in: store, undoManager: undoManager)
            }
            .presentationCornerRadius(Radius.sheet)
        }
        .sheet(item: $taggingSelection) { tagging in
            TagSheet(subject: String(localized: "\(tagging.ids.count) notebooks"), initial: tagging.common, mixed: tagging.mixed) { tags, stillMixed in
                let edit = TagEdit(before: (tagging.common, tagging.mixed), tags: tags, stillMixed: stillMixed)
                changes.editTags(edit, for: records.filter { tagging.ids.contains($0.id) }, in: store, undoManager: undoManager)
                endSelection()
            }
            .presentationCornerRadius(Radius.sheet)
        }
        .notice(Text(permanentDeleteTitle), isPresented: Binding(get: { !changes.pendingPermanentDelete.isEmpty },
                                                                 set: { if !$0 { changes.pendingPermanentDelete = [] } }),
                message: Text("This can't be undone.")) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive) { confirmPermanentDelete() }
        }
        .overlay(alignment: .bottom) { slip }
        .task(id: changes.current?.id) {
            guard changes.current != nil, !voiceOver else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { changes.dismiss() }
        }
        .onChange(of: isCovered) { _, covered in if covered { changes.dismiss() } }
    }

    // MARK: Shelves

    private func shelves(_ visible: [NotebookRecord]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.x6) {
                LibraryHeader(title: title, summary: subtitle(visible), showsRhythm: showsRhythm, onOpenPage: onOpenPage)
                if scope == .all, searchText.isEmpty, !isSelecting { DeskCards(records: records, zoomNamespace: zoomNamespace, onOpen: onOpenZoomed) }
                if !searchText.isEmpty, !pageHits.isEmpty, scope != .trash {
                    PageHitsSection(records: visible, hits: pageHits, query: hitsQuery, zoomNamespace: zoomNamespace, onOpen: onOpenZoomed)
                        .transition(.opacity)
                }
                ForEach(groups(visible)) { shelf in
                    ShelfLabel(title: shelf.title, cloth: shelf.cloth)
                        .padding(.top, Space.x2)
                    if let shelfWidth {
                        // A plain cover grid: no ledges under the rows.
                        let metrics = ShelfMetrics.fit(width: shelfWidth)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(metrics.coverWidth), spacing: metrics.gap, alignment: .top),
                                                 count: metrics.columns),
                                  alignment: .leading, spacing: Space.x8) {
                            ForEach(shelf.records) { record in item(record, width: metrics.coverWidth) }
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 188), spacing: Space.x6, alignment: .top)],
                                  alignment: .leading, spacing: Space.x8) {
                            ForEach(shelf.records) { record in item(record, width: CoverWidth.shelf) }
                        }
                    }
                }
                if showsTagPages {
                    PageHitsSection(records: taggedNotebooks, hits: tagPages, query: "", zoomNamespace: zoomNamespace, onOpen: onOpenZoomed)
                        .padding(.top, Space.x2)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { shelfWidth = $0 }
            .padding(.horizontal, Space.x8)
            .padding(.vertical, Space.x6)
        }
        .scrollDismissesKeyboard(.immediately)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 56 } action: { showsBarTitle = $1 }
    }

    /// Rows in columns, a board for each run, with as many columns as the pane and the text size leave room for.
    private func list(_ visible: [NotebookRecord]) -> some View {
        List {
            if !searchText.isEmpty, !pageHits.isEmpty, scope != .trash {
                pageRows(visible, hits: pageHits, query: hitsQuery)
            }
            ForEach(groups(visible)) { group in
                Section(group.title) {
                    ForEach(group.records) { record in
                        row(record, columns: [])
                    }
                }
            }
            if showsTagPages { pageRows(taggedNotebooks, hits: tagPages, query: "") }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
        .scrollDismissesKeyboard(.immediately)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 56 } action: { showsBarTitle = $1 }
    }

    private func row(_ record: NotebookRecord, columns: ShelfColumns) -> some View {
        NotebookListRow(record: record, columns: columns, isSelecting: isSelecting, isSelected: selection.contains(record.id)) {
            if isSelecting { toggle(record) } else if !record.isTrashed { onOpen(record) }
        }
        .accessibilityLabel(record.accessibilityDescription)
        .accessibilityHint(record.accessibilityHint(isSelecting: isSelecting))
        .accessibilityAddTraits(selection.contains(record.id) ? .isSelected : [])
        .accessibilityIdentifier("notebook.\(record.title)")
        .accessibilityActions { if !isSelecting { trashActions(for: record) } }
        .heldMenu(Text(record.title), when: !isSelecting, draggable: true) { menu(for: record) }
        .onDrag { NotebookDrag.provider(for: record, root: store.root) } preview: { dragPreview(record) }
    }

    private func dragPreview(_ record: NotebookRecord) -> some View {
        Text(record.title).padding(Space.x2).background(Color.surface, in: RoundedRectangle.plate)
    }

    /// The notebooks whose pages a tag shelf lists, whether or not they are on the shelf themselves.
    private var taggedNotebooks: [NotebookRecord] { records.filter { tagPages[$0.id] != nil }.sorted(by: sort, reversed: sortReversed) }

    /// A view that mixes shelves says which shelf a notebook is on.
    private var showsFolder: Bool {
        switch scope {
        case .all, .favorites, .tag, .smart: true
        case .trash, .folder: false
        }
    }

    private func item(_ record: NotebookRecord, width: CGFloat) -> some View {
        NotebookCoverItem(record: record, width: width, isSelecting: isSelecting, isSelected: selection.contains(record.id),
                          zoomNamespace: zoomNamespace, showsFolder: showsFolder) {
            if isSelecting { toggle(record) } else if !record.isTrashed { onOpen(record) }
        }
        .overlay(alignment: .topTrailing) {
            if record.id.uuidString == journalID { JournalBadge().offset(x: 6, y: -6) }
        }
        .heldMenu(Text(record.title), when: !isSelecting, draggable: true) { menu(for: record) }
        .onDrag { NotebookDrag.provider(for: record, root: store.root) } preview: { dragPreview(record) }
    }

    // MARK: Journal

    /// The journal isn't on any shelf: the Journal button (in the bar, and in the middle of an empty shelf) is the way in.
    /// It starts a journal if there isn't one, then opens the whole journal on today's page; the other days are a page turn away.
    private func openJournal() {
        guard !openingJournal else { return }
        openingJournal = true
        Task {
            defer { openingJournal = false }
            do {
                let id = try await store.journalForToday()
                guard let record = store.record(id) else { return }
                if let page = await store.prepareTodayPage(id) { onOpenPage(record, page) } else { onOpen(record) }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func accessibleList(_ visible: [NotebookRecord]) -> some View {
        List {
            if showsRhythm { WeekSummarySection(onOpenPage: onOpenPage) }
            if scope == .all, searchText.isEmpty, !isSelecting { DeskCards(records: records, zoomNamespace: zoomNamespace, asRows: true, onOpen: onOpenZoomed) }
            ForEach(visible) { record in
                Button {
                    if isSelecting { toggle(record) } else if !record.isTrashed { onOpen(record) }
                } label: {
                    HStack(spacing: Space.x4) {
                        RecordCover(record: record, width: CoverWidth.row, showsShadow: false).frame(width: 48)
                        VStack(alignment: .leading, spacing: Space.x1) {
                            Text(record.title).font(.headline).foregroundStyle(Color.ink)
                            Text(record.metaLine).font(.subheadline).foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        if isSelecting {
                            Image(systemName: selection.contains(record.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityLabel(record.accessibilityDescription)
                .accessibilityHint(record.accessibilityHint(isSelecting: isSelecting))
                .accessibilityIdentifier("notebook.\(record.title)")
                .accessibilityAddTraits(selection.contains(record.id) ? .isSelected : [])
                .accessibilityActions { if !isSelecting { trashActions(for: record) } }
                .heldMenu(Text(record.title), when: !isSelecting, draggable: true) { menu(for: record) }
                .onDrag { NotebookDrag.provider(for: record, root: store.root) }
                .listRowBackground(Color.surface)
            }
            if !searchText.isEmpty, !pageHits.isEmpty, scope != .trash { pageRows(visible, hits: pageHits, query: hitsQuery) }
            if showsTagPages { pageRows(taggedNotebooks, hits: tagPages, query: "") }
        }
        .scrollContentBackground(.hidden)
    }

    private func pageRows(_ records: [NotebookRecord], hits: [UUID: [PageHit]], query: String) -> some View {
        Section {
            ForEach(records.flatMap { record in (hits[record.id] ?? []).map { (record, $0) } }, id: \.1.id) { record, hit in
                Button { onOpenPage(record, hit.page.id) } label: {
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Text(hit.title(in: record.title)).font(.headline).foregroundStyle(Color.ink)
                        Text(PageSearch.highlighted(hit.snippet, query: query)).font(.subheadline).foregroundStyle(Color.textSecondary)
                    }
                }
                .accessibilityLabel(Text(hit.label(in: record.title)))
                .accessibilityHint(Text("Opens the notebook at this page"))
                .listRowBackground(Color.surface)
            }
        } header: {
            Text("Pages").metaStyle(.footnote)
        }
    }

    private func subtitle(_ visible: [NotebookRecord]) -> String {
        if isSelecting { return String(localized: "Select notebooks to move, favourite or delete") }
        if scope == .trash { return String(localized: "Deleted notebooks stay here for \(trashLength.days) days") }
        let count = visible.count
        let notebooks = String(localized: "\(count) notebooks")
        // On a tag shelf the pages counted are the tagged ones it lists, not every page of its notebooks.
        if rule != nil {
            let tagged = tagPages.values.reduce(0) { $0 + $1.count }
            let order = sort.summary(reversed: sortReversed)
            return tagged == 0 ? "\(notebooks) · \(order)" : "\(notebooks) · \(String(localized: "\(tagged) pages")) · \(order)"
        }
        let pageCount = visible.reduce(0) { $0 + $1.pageCount }
        let pages = String(localized: "\(pageCount) pages")
        return "\(notebooks) · \(pages) · \(sort.summary(reversed: sortReversed))"
    }

    /// This week's writing shows at the top of All notebooks, but not while searching or selecting.
    private var showsRhythm: Bool { scope == .all && searchText.isEmpty && !isSelecting }

    private func groups(_ visible: [NotebookRecord]) -> [Shelf] {
        guard !visible.isEmpty else { return [] }
        if !searchText.isEmpty { return [Shelf(id: "results", title: String(localized: "Results"), records: visible)] }
        if scope == .trash || sort == .title {
            return [Shelf(id: "all", title: sort == .title ? sort.directionName(reversed: sortReversed) : title, records: visible)]
        }
        let tree = tree
        var root: UUID?
        if case .folder(let id) = scope { root = id }
        // Inside a folder with nothing but its own notebooks, shelves by folder would be one shelf: recency says more.
        if grouping == .folder, root == nil || visible.contains(where: { $0.folder?.id != root }) {
            let byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var shelves: [Shelf] = tree.ordered.compactMap { id in
                guard let folder = byID[id] else { return nil }
                let items = visible.filter { $0.folder?.id == id }
                return items.isEmpty ? nil : Shelf(id: id.uuidString, title: id == root ? folder.name : tree.path(of: id, from: root), records: items, cloth: folder.cloth)
            }
            let loose = visible.filter { $0.folder == nil }
            if !loose.isEmpty { shelves.append(Shelf(id: "loose", title: String(localized: "Not in a folder"), records: loose)) }
            return shelves
        }
        let calendar = Calendar.current
        let now = Date.now
        var buckets: [(key: String, date: Date, records: [NotebookRecord])] = []
        var positions: [String: Int] = [:]
        for record in visible {
            let date = sort.date(of: record)
            let key = ShelfGrouping.bucket(for: date, now: now, calendar: calendar)
            if let index = positions[key] {
                buckets[index].records.append(record)
            } else {
                positions[key] = buckets.count
                buckets.append((key, date, [record]))
            }
        }
        return buckets.map { bucket in
            let title = switch bucket.key {
            case "today": String(localized: "Today")
            case "yesterday": String(localized: "Yesterday")
            case "week": String(localized: "This week")
            case "month": String(localized: "Earlier this month")
            default: bucket.date.formatted(.dateTime.month(.wide).year())
            }
            return Shelf(id: bucket.key, title: title, records: bucket.records)
        }
    }

    // MARK: Selection

    private func toggle(_ record: NotebookRecord) {
        if selection.contains(record.id) { selection.remove(record.id) } else { selection.insert(record.id) }
    }

    private func endSelection() {
        isSelecting = false
        selection = []
    }

    private func selected(_ visible: [NotebookRecord]) -> [NotebookRecord] { visible.filter { selection.contains($0.id) } }

    @ToolbarContentBuilder
    private func selectionBar(_ visible: [NotebookRecord]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if scope == .trash {
                Button("Restore") { changes.restore(selected(visible), in: store, undoManager: undoManager); endSelection() }
                    .buttonStyle(.mathNotes(.secondary, inBar: true))
                    .disabled(selection.isEmpty)
                Spacer()
                BarGroup {
                    Button(role: .destructive) { changes.requestPermanentDelete(selected(visible).map(\.id)) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .disabled(selection.isEmpty)
            } else {
                let chosen = selected(visible)
                BarGroup {
                    Button { changes.setFavorite(true, for: chosen, in: store, undoManager: undoManager); endSelection() } label: {
                        Label("Favourite", systemImage: "star")
                    }
                    .accessibilityIdentifier("library.selection.favourite")
                    Button { tagSelection(chosen) } label: { Label("Tags…", systemImage: "tag") }
                        .disabled(!chosen.contains { !$0.isReadOnly })
                        .accessibilityIdentifier("library.selection.tags")
                    MathNotesMenu {
                        Button("Not on a shelf") { move(chosen, to: nil); endSelection() }
                        ForEach(folders) { folder in Button(tree.path(of: folder.id)) { move(chosen, to: folder); endSelection() } }
                    } label: { Label("Move", systemImage: "folder") }
                    .accessibilityIdentifier("library.selection.move")
                    Button { lockSelection(chosen) } label: { Label("Lock", systemImage: "lock") }
                        .disabled(!chosen.contains { !$0.isLocked && !$0.isReadOnly })
                        .accessibilityIdentifier("library.selection.lock")
                    Button { exportSelection(chosen) } label: { Label("Export as PDFs", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("library.selection.export")
                }
                .disabled(chosen.isEmpty)
                Spacer()
                BarGroup {
                    Button(role: .destructive) { changes.moveToTrash(chosen, in: store, undoManager: undoManager); endSelection() } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("library.selection.delete")
                }
                .disabled(chosen.isEmpty)
            }
        }
        .boardBackground()
    }

    /// The tags every chosen notebook has are on, the ones only some have are shown as mixed.
    private func tagSelection(_ chosen: [NotebookRecord]) {
        let writable = chosen.filter { !$0.isReadOnly }
        let shared = TagEdit.shared(writable.map(\.tags))
        taggingSelection = SelectionTags(ids: writable.map(\.id), common: shared.common, mixed: shared.mixed)
    }

    private func lockSelection(_ chosen: [NotebookRecord]) {
        Task {
            if let failure = await store.lock(chosen) { errorMessage = failure } else { endSelection() }
        }
    }

    private func exportSelection(_ chosen: [NotebookRecord]) {
        Task {
            do {
                export = try await ExportJob.pdfs(of: chosen, root: store.root)
                endSelection()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Toolbar and menus

    private var searchField: some View {
        MathNotesSearchField("Search", text: $searchText, capsTextSize: searchInBar, identifier: "library.search", focus: $searchFocused)
    }

    /// A bar without room for the search field would drop it into the overflow menu, so there it sits under the bar.
    private var searchInBar: Bool { barRoom >= actionsWidth + 308 && !dynamicTypeSize.isAccessibilitySize }

    @ToolbarContentBuilder
    private func toolbar(_ visible: [NotebookRecord]) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            let shows = showsBarTitle || dynamicTypeSize.isAccessibilitySize
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .fixedSize(horizontal: dynamicTypeSize.isAccessibilitySize, vertical: false)
                .opacity(shows ? 1 : 0)
                .accessibilityHidden(!shows)
                .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: shows)
        }
        ToolbarItem(placement: .primaryAction) {
            if isSelecting {
                let count = selected(visible).count, everything = !visible.isEmpty && count == visible.count
                HStack(spacing: Space.x2) {
                    Button(everything ? String(localized: "Deselect All") : String(localized: "Select All")) {
                        selection = everything ? [] : filter.selectingAll(records)
                    }
                    .buttonStyle(.mathNotes(.secondary, inBar: true))
                    .disabled(visible.isEmpty)
                    .accessibilityIdentifier("library.selectAll")
                    Button("Done") { endSelection() }
                        .buttonStyle(.mathNotes(.primary, inBar: true))
                        .accessibilityLabel(count == 0 ? String(localized: "Done") : String(localized: "\(count) selected, done"))
                }
            } else {
                HStack(spacing: Space.x2) {
                    if let sync = app?.sync, !sync.news.isEmpty { SyncNoticeButton(sync: sync, onOpen: onOpen) }
                    if scope == .trash {
                        Button("Empty") { confirmingEmptyTrash = true }.disabled(visible.isEmpty)
                    } else {
                        MathNotesMenu {
                            MathNotesPicker("Sort By", selection: $sort) {
                                ForEach(LibrarySortOrder.allCases) { Text($0.displayName).tag($0) }
                            }
                            MathNotesPicker("Order", selection: $sortReversed) {
                                ForEach([false, true], id: \.self) { Text(sort.directionName(reversed: $0)).tag($0) }
                            }
                            MathNotesPicker("Group By", selection: $grouping) {
                                ForEach(LibraryGrouping.allCases) { Text($0.displayName).tag($0) }
                            }
                        } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                    }
                    Button("Select") { isSelecting = true }.disabled(visible.isEmpty)
                    if scope != .trash {
                        Button { importingPDF = true } label: { Label("Import PDF", systemImage: "doc.richtext") }
                            .accessibilityIdentifier("library.importPDF")
                        Button(action: openJournal) { Label("Journal", systemImage: "calendar") }
                            .disabled(openingJournal)
                            .accessibilityIdentifier("library.journal")
                        MathNotesMenu {
                            Button { onCreate() } label: { Label("New Notebook", systemImage: "book.closed") }
                            Button { onWhiteboard() } label: { Label("Whiteboard", systemImage: "scribble.variable") }
                                .accessibilityIdentifier("library.new.board")
                            Button { importingPDF = true } label: { Label("Import PDF…", systemImage: "doc.richtext") }
                            if DocumentScan.isAvailable {
                                Button(action: startScan) { Label("Scan Documents…", systemImage: "doc.viewfinder") }
                            }
                        } label: {
                            Label("New Note", systemImage: "square.and.pencil")
                        } primaryAction: {
                            onQuickNote()
                        }
                        .buttonStyle(.mathNotes(.primary, inBar: true))
                    }
                }
                .buttonStyle(.mathNotes(.secondary, inBar: true))
                .labelStyle(.titleAndIcon)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { actionsWidth = $0 }
            }
        }
        .boardBackground()
        if searchInBar {
            ToolbarItem(placement: .primaryAction) { searchField.frame(width: 260) }
                .boardBackground()
        }
        if isSelecting {
            ToolbarItem(placement: .status) {
                Text("\(selected(visible).count) selected")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.ink)
            }
            .boardBackground()
        }
    }

    @ViewBuilder
    private func trashActions(for record: NotebookRecord) -> some View {
        if record.isTrashed {
            Button("Restore") { changes.restore([record], in: store, undoManager: undoManager) }
            Button("Delete Permanently") { changes.requestPermanentDelete([record.id]) }
        }
    }

    @ViewBuilder
    private func menu(for record: NotebookRecord) -> some View {
        if record.isTrashed {
            Button { changes.restore([record], in: store, undoManager: undoManager) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            Button(role: .destructive) { changes.requestPermanentDelete([record.id]) } label: { Label("Delete Permanently", systemImage: "trash") }
        } else if record.isReadOnly {
            Button { onOpen(record) } label: { Label("Open", systemImage: "book") }
            Button { startExport(record, as: .pdf) } label: { Label("Export as PDF", systemImage: "square.and.arrow.up") }
            Button { startExport(record, as: .images) } label: { Label("Export as Images", systemImage: "photo.on.rectangle") }
            MenuBreak()
            Button(role: .destructive) { changes.moveToTrash([record], in: store, undoManager: undoManager) } label: { Label("Delete", systemImage: "trash") }
                .accessibilityIdentifier("notebook.menu.delete")
            Text("Made with a newer version of MathNotes, so it can only be read here.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .padding(Space.x3)
        } else {
            Button { onOpen(record) } label: { Label("Open", systemImage: "book") }
            Button { renameText = record.title; renaming = record } label: { Label("Rename", systemImage: "pencil") }
            Button { changes.setFavorite(!record.isFavorite, for: [record], in: store, undoManager: undoManager) } label: {
                Label(record.isFavorite ? "Unfavourite" : "Favourite", systemImage: record.isFavorite ? "star.slash" : "star")
            }
            MathNotesMenu {
                Button { move([record], to: nil) } label: { Label("Not in a Folder", systemImage: record.folder == nil ? "checkmark" : "tray") }
                ForEach(folders) { folder in
                    Button { move([record], to: folder) } label: {
                        Label(tree.path(of: folder.id), systemImage: record.folder?.id == folder.id ? "checkmark" : "folder")
                    }
                }
            } label: { Label("Move to Folder", systemImage: "folder") }
            Button {
                Task { do { try await store.duplicate(record) } catch { errorMessage = error.localizedDescription } }
            } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { changeCover(record) } label: { Label("Change Cover…", systemImage: "book.closed") }
            Button { tagging = record } label: { Label("Tags…", systemImage: "tag") }
            Button { startExport(record, as: .pdf) } label: { Label("Export as PDF", systemImage: "square.and.arrow.up") }
            Button { startExport(record, as: .images) } label: { Label("Export as Images", systemImage: "photo.on.rectangle") }
            Toggle(isOn: Binding(get: { journalID == record.id.uuidString }, set: { store.setDailyJournal($0 ? record.id : nil) })) {
                Label("Use as Daily Journal", systemImage: "calendar")
            }
            Button { toggleLock(record) } label: {
                Label(record.isLocked ? "Remove Lock…" : "Lock…", systemImage: record.isLocked ? "lock.open" : "lock")
            }
            MenuBreak()
            Button(role: .destructive) { changes.moveToTrash([record], in: store, undoManager: undoManager) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func startExport(_ record: NotebookRecord, as format: ExportJob.Format) {
        let id = record.id, title = record.title, locked = record.isLocked
        Task {
            if locked, !(await NotebookLock.shared.confirm(String(localized: "Export “\(title)”"))) { return }
            do { export = try await ExportJob.forNotebook(id, root: store.root, format: format) } catch { errorMessage = error.localizedDescription }
        }
    }

    /// The cover editor can show a notebook's first page, so a locked notebook asks first.
    private func changeCover(_ record: NotebookRecord) {
        guard record.isLocked else { return editingCover = record }
        let title = record.title
        Task { if await NotebookLock.shared.confirm(String(localized: "Unlock “\(title)”")) { editingCover = record } }
    }

    private func toggleLock(_ record: NotebookRecord) {
        Task { if let failure = await store.toggleLock(record) { errorMessage = failure } }
    }

    // MARK: Safety net

    private func move(_ records: [NotebookRecord], to folder: FolderRecord?) {
        changes.move(records, to: folder, in: store, undoManager: undoManager)
    }

    private var permanentDeleteTitle: String {
        let ids = changes.pendingPermanentDelete
        guard let first = ids.first else { return "" }
        if ids.count > 1 { return String(localized: "Delete \(ids.count) notebooks permanently?") }
        let title = records.first { $0.id == first }?.title ?? ""
        return String(localized: "Delete “\(title)” permanently?")
    }

    private func confirmPermanentDelete() {
        let ids = Set(changes.pendingPermanentDelete)
        changes.confirmPermanentDelete(in: store)
        selection.subtract(ids)
        if isSelecting, selection.isEmpty { endSelection() }
    }

    private var slip: some View {
        ZStack {
            if let change = changes.current {
                LibrarySlipView(change: change) { changes.dismiss() }
                    .padding(.bottom, Space.x4)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: changes.current?.id)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if scope == .trash {
            ContentUnavailableView("Recently Deleted", systemImage: "trash",
                                    description: Text("Deleted notes stay here for \\(trashLength.days) days."))
        } else if scope == .favorites {
            ContentUnavailableView("No Favorites", systemImage: "star",
                                    description: Text("Notes you favorite will appear here."))
        } else if case .tag(let name) = scope {
            ContentUnavailableView("No Notes Tagged \(name)", systemImage: "tag",
                                    description: Text("Tag a note or page to find it here."))
        } else if case .smart = scope {
            ContentUnavailableView("No Notes Yet", systemImage: "folder.badge.gearshape",
                                    description: Text("Notes matching this Smart Folder will appear here."))
        } else if case .folder = scope, let name = folder?.name {
            ContentUnavailableView {
                Label("No Notes in \(name)", systemImage: "folder")
            } description: {
                Text("Create a note in this folder to get started.")
            } actions: {
                Button("New Note", action: onQuickNote).buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("No Notes", systemImage: "note.text")
            } description: {
                Text("Create a note or import a PDF to get started.")
            } actions: {
                Button("New Note", action: onQuickNote).buttonStyle(.borderedProminent)
                Button("Import PDF", action: { importingPDF = true }).buttonStyle(.bordered)
            }
        }
    }

    private func startScan() {
        #if DEBUG
        if LaunchOptions.arguments.contains("-fakeScan") { return importScan(DocumentScan.samples()) }
        #endif
        scanning = true
    }

    private func importScan(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        Task {
            do {
                try await store.importScan(images, folder: folder)
                AccessibilityNotification.Announcement(String(localized: "\(images.count) pages scanned into a new notebook")).post()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importPDFs(_ result: Result<[URL], Error>) async {
        do {
            for url in try result.get() { _ = try await store.importPDF(from: url, folder: folder) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension LibrarySortOrder {
    func date(of record: NotebookRecord) -> Date {
        switch self {
        case .opened: record.lastOpenedAt ?? record.modifiedAt
        case .modified, .title: record.modifiedAt
        case .created: record.createdAt
        }
    }
}

extension Array where Element == NotebookRecord {
    /// Reads each record's sort key once, rather than twice per comparison. Turned round, the oldest come first, or Z.
    func sorted(by order: LibrarySortOrder, reversed: Bool = false) -> [NotebookRecord] {
        switch order {
        case .title:
            let first: ComparisonResult = reversed ? .orderedDescending : .orderedAscending
            return map { ($0, $0.title) }.sorted { $0.1.localizedStandardCompare($1.1) == first }.map(\.0)
        default:
            return map { ($0, order.date(of: $0)) }.sorted { reversed ? $0.1 < $1.1 : $0.1 > $1.1 }.map(\.0)
        }
    }
}

struct ShelfLabel: View {
    let title: String
    var cloth: ClothColor?
    var body: some View {
        HStack(spacing: Space.x3) {
            if let cloth { SpineChip(cloth: cloth) }
            Text(title).metaStyle(.footnote).fixedSize().accessibilityAddTraits(.isHeader)
            Rectangle().fill(Color.hairline).frame(height: 1).accessibilityHidden(true)
        }
    }
}

struct EmptyShelf<Actions: View, Illustration: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let message: String
    @ViewBuilder var actions: Actions
    @ViewBuilder var illustration: Illustration

    init(title: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() },
         @ViewBuilder illustration: () -> Illustration = { EmptyView() }) {
        self.title = title
        self.message = message
        self.actions = actions()
        self.illustration = illustration()
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content.frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(spacing: Space.x4) {
            illustration
            Text(title)
                .displayFont(30, relativeTo: .title)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .displayTextFont(17, relativeTo: .body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Space.x3)) : AnyLayout(HStackLayout(spacing: Space.x3))) {
                actions
            }
            .controlSize(.large)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 420)
        .padding(Space.x8)
        .frame(maxWidth: .infinity)
    }
}

/// Holds first responder while the library is in front, so ⌘F reaches the search field and ⌘Z the library's undo.
private struct SearchActivator: UIViewRepresentable {
    let isSearching: Bool
    let isCovered: Bool
    let onFind: () -> Void
    @Environment(\.undoManager) private var undoManager

    func makeUIView(context: Context) -> ActivatorView { ActivatorView() }

    /// Acts only on changes, so ordinary library updates never move first responder.
    func updateUIView(_ view: ActivatorView, context: Context) {
        view.onFind = onFind
        view.libraryUndoManager = undoManager
        if isCovered != view.wasCovered {
            view.wasCovered = isCovered
            view.isCovered = isCovered
            DispatchQueue.main.async { if isCovered { view.resignFirstResponder() } else { view.reclaimFirstResponder() } }
        }
        guard isSearching != view.wasSearching else { return }
        view.wasSearching = isSearching
        if !isSearching { DispatchQueue.main.async { view.reclaimFirstResponder() } }
    }

    final class ActivatorView: UIView {
        var onFind: (() -> Void)?
        var wasSearching = false
        var wasCovered = false
        var isCovered = false
        weak var libraryUndoManager: UndoManager?

        override var canBecomeFirstResponder: Bool { !isCovered }

        override var keyCommands: [UIKeyCommand]? {
            guard !isCovered else { return [] }
            let commands = [
                UIKeyCommand(title: String(localized: "Search Library"), action: #selector(findRequested), input: "f", modifierFlags: .command),
                UIKeyCommand(title: String(localized: "Undo"), action: #selector(undoLibraryChange), input: "z", modifierFlags: .command),
                UIKeyCommand(title: String(localized: "Redo"), action: #selector(redoLibraryChange), input: "z", modifierFlags: [.command, .shift]),
            ]
            for command in commands { command.wantsPriorityOverSystemBehavior = true }
            return commands
        }

        @objc private func findRequested() { if !isCovered { onFind?() } }

        @objc private func undoLibraryChange() { libraryUndoManager?.undo() }

        @objc private func redoLibraryChange() { libraryUndoManager?.redo() }

        override func find(_ sender: Any?) { findRequested() }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            switch action {
            case #selector(undoLibraryChange): !isCovered && libraryUndoManager?.canUndo == true
            case #selector(redoLibraryChange): !isCovered && libraryUndoManager?.canRedo == true
            default: (action == #selector(find(_:)) && !isCovered) || super.canPerformAction(action, withSender: sender)
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            NotificationCenter.default.removeObserver(self, name: UITextField.textDidEndEditingNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(textDidEndEditing(_:)), name: UITextField.textDidEndEditingNotification, object: nil)
            DispatchQueue.main.async { self.reclaimFirstResponder() }
        }

        @objc private func textDidEndEditing(_ note: Notification) {
            guard (note.object as? UIView)?.window === window else { return }
            DispatchQueue.main.async { self.reclaimFirstResponder() }
        }

        /// Takes ⌘F back once a field stops editing, unless the user has gone straight into another one.
        func reclaimFirstResponder() {
            guard !isCovered, let window else { return }
            if let field = UIResponder.current as? UIView, field is UITextInput, field.window === window { return }
            becomeFirstResponder()
        }
    }
}

private extension UIResponder {
    private static weak var found: UIResponder?

    /// Whatever holds first responder in the app right now.
    static var current: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(mathNotesCaptureFirstResponder), to: nil, from: nil, for: nil)
        return found
    }

    @objc private func mathNotesCaptureFirstResponder() { UIResponder.found = self }
}

/// The mark on the daily journal's cover: it is a notebook like the others, and this says which one opens on today.
private struct JournalBadge: View {
    var body: some View {
        Image(systemName: "calendar")
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.onPrimaryCloth)
            .frame(width: 26, height: 26)
            .background(Color.primaryCloth, in: Circle())
            .overlay { Circle().strokeBorder(Color.paper, lineWidth: 2) }
            .accessibilityLabel(Text("Daily Journal"))
    }
}
