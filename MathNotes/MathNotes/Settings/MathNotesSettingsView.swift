import SwiftUI

struct MathNotesSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var store
    @Environment(WritingActivity.self) private var activity
    @Environment(AppModel.self) private var app: AppModel?
    @AppStorage(SettingsKey.drawingInput) private var drawingInput: DrawingInput = .initial
    @AppStorage(SettingsKey.defaultTemplate) private var template: PaperTemplate = .narrowRuled
    @AppStorage(SettingsKey.defaultPaperColor) private var color: PaperColor = .white
    @AppStorage(SettingsKey.defaultPageSize) private var size: PageSize = .letter
    @AppStorage(SettingsKey.darkPaper) private var darkPaper = true
    @AppStorage(SettingsKey.dailyJournalID) private var journalID = ""
    @AppStorage(SettingsKey.showsOnThisDay) private var showsOnThisDay = true
    @AppStorage(SettingsKey.snapsShapes) private var snapsShapes = true
    @AppStorage(SettingsKey.snapsHighlighter) private var snapsHighlighter = true
    @AppStorage(SettingsKey.scribbleErases) private var scribbleErases = true
    @AppStorage(SettingsKey.circleSelects) private var circleSelects = true
    @AppStorage(SettingsKey.pencilDoubleTap) private var pencilDoubleTap: PencilAction = .system
    @AppStorage(SettingsKey.pencilSqueeze) private var pencilSqueeze: PencilAction = .system
    @AppStorage(SettingsKey.journalAgenda) private var printsAgenda = false
    @AppStorage(SettingsKey.spotlight) private var showsInSpotlight = true
    @AppStorage(SettingsKey.appearance) private var appearance: AppAppearance = .initial
    @AppStorage(SettingsKey.leftHanded) private var leftHanded = false
    @AppStorage(SettingsKey.trashLength) private var trashLength: TrashLength = .initial
    @AppStorage(SettingsKey.transcriptLanguage) private var transcriptLanguage = ""
    @State private var transcriptLanguages: [Locale] = []
    @State private var toolbox = Toolbox.shared
    @State private var confirmingPenReset = false
    @State private var agendaMessage: String?
    @State private var confirmingHistoryClear = false
    @State private var backupWork: BackupWork?
    @State private var backingUp: Task<Void, Never>?
    @State private var lastBackup: URL?
    @State private var sharedBackup: SharedFile?
    @State private var choosingBackup = false
    @State private var backupMessage: String?

    private enum BackupWork { case backingUp, restoring }

    private struct SharedFile: Identifiable {
        let id = UUID()
        let url: URL
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x8) {
                    appearanceSection
                    inputSection
                    pencilSection
                    penTraySection
                    paperSection
                    recordingsSection
                    journalSection
                    historySection
                    trashSection
                    searchSection
                    syncSection
                    backupSection
                    aboutSection
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Space.x5)
                .padding(.top, Space.x4)
                .padding(.bottom, Space.x10)
            }
            .toggleStyle(.mathNotes)
            .foregroundStyle(Color.ink)
            .background(Color.paper)
            .navigationTitle("Settings")
            .barGround(.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.buttonStyle(.mathNotes(.primary, inBar: true))
                }
                .boardBackground()
            }
        }
        .tint(Color.accentColor)
        .presentationSizing(.page)
        .sheet(item: $sharedBackup) { file in ShareSheet(items: [file.url]).presentationCornerRadius(Radius.sheet) }
        // The backup is kept to share again while Settings is open.
        .onDisappear {
            backingUp?.cancel()
            if let lastBackup { ExportFolder.discard([lastBackup]) }
        }
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.mathNotesBackup, .legacyBackup, .appleArchive]) { result in
            if case .success(let url) = result { restore(url) }
        }
        .notice("Backup", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } }),
                message: Text(backupMessage ?? "")) {
            Button("OK", role: .cancel) {}
        }
    }

    private var appearanceSection: some View {
        SettingsSection("Appearance", note: "“System” follows the iPad's Light or Dark appearance. With Keep Paper Light on, pages, paper colours and templates stay light in Dark Mode, and ink looks as it does on light paper. A PDF, a photo and everything you export keep their own colours.") {
            MathNotesSegmentedPicker("Appearance", selection: $appearance, options: AppAppearance.allCases,
                                   identifier: { "settings.appearance.\($0.rawValue)" }) { Text($0.displayName) }
                .accessibilityIdentifier("settings.appearance")
                .padding(.vertical, Space.x2)
                .settingsRow()
            Toggle("Keep Paper Light", isOn: Binding(get: { !darkPaper }, set: { darkPaper = !$0 }))
                .accessibilityIdentifier("settings.appearance.paperLight")
                .settingsRow()
        }
    }

    private var inputSection: some View {
        SettingsSection("Input", note: "“System Setting” follows Settings › Apple Pencil › Only Draw with Apple Pencil. With Left-Handed on, the page ribbon, the zoom window's buttons and the panels beside the page are on the left.") {
            VStack(alignment: .leading, spacing: Space.x2) {
                Text("Draw With")
                MathNotesSegmentedPicker("Draw With", selection: $drawingInput, options: DrawingInput.allCases) { Text($0.displayName) }
            }
            .padding(.vertical, Space.x2)
            .settingsRow()
            Toggle("Left-Handed", isOn: $leftHanded)
                .accessibilityIdentifier("settings.input.leftHanded")
                .settingsRow()
        }
    }

    private var penTraySection: some View {
        SettingsSection("Pen Tray") {
            SettingsActionRow(title: "Reset Pen Tray…", systemImage: "arrow.counterclockwise", role: .destructive) { confirmingPenReset = true }
                .disabled(toolbox.shelf.isAsItStarted)
                .accessibilityIdentifier("settings.pens.reset")
                .notice("Reset the pen tray?", isPresented: $confirmingPenReset,
                        message: Text("It goes back to the four it started with: a black, a blue and a red pen and a yellow highlighter. Pens you added or changed are taken off it.")) {
                    Button("Cancel", role: .cancel) {}
                }
        }
    }

    private var recordingsSection: some View {
        let chosen = transcriptLanguage.isEmpty ? nil : Locale(identifier: transcriptLanguage)
        return SettingsSection("Recordings", note: "Recordings are transcribed on this iPad, in this language unless you pick another for one. Only the languages this iPad can transcribe without sending a recording away are listed.") {
            SettingsChoiceRow(title: "Transcription Language", value: chosen.map(Transcription.name(of:)) ?? String(localized: "Same as iPad"),
                              selection: $transcriptLanguage) {
                Section { Text("Same as iPad").tag("") }
                if !transcriptLanguages.isEmpty {
                    Section {
                        ForEach(transcriptLanguages, id: \.identifier) { Text(Transcription.name(of: $0)).tag($0.identifier(.bcp47)) }
                    }
                }
            }
            .accessibilityIdentifier("settings.transcription.language")
        }
        .task { transcriptLanguages = await Task.detached(priority: .userInitiated) { Transcription.onDeviceLanguages() }.value }
    }

    private var trashSection: some View {
        SettingsSection("Recently Deleted", note: "Notebooks in Recently Deleted are deleted for good once they have been there this long. Each iPad keeps to its own setting: with iCloud sync on, a notebook whose time runs out here stays on another iPad set to keep it longer, until its time there runs out too.") {
            VStack(alignment: .leading, spacing: Space.x2) {
                Text("Keep Deleted Notebooks For")
                MathNotesSegmentedPicker("Keep Deleted Notebooks For", selection: $trashLength, options: TrashLength.allCases,
                                       identifier: { "settings.trash.\($0.days)" }) { Text($0.displayName) }
                    .accessibilityIdentifier("settings.trash.length")
            }
            .padding(.vertical, Space.x2)
            .settingsRow()
            .onChange(of: trashLength) { _, _ in
                if let app { Task { await app.trash.lengthChanged() } }
            }
        }
    }

    private var pencilSection: some View {
        SettingsSection("Apple Pencil", note: "Draw a line, circle, rectangle or triangle and hold still before lifting to straighten it, or draw a loop round ink and hold still to select it. Scribble back and forth over ink with a pen to erase it; Undo brings it back. A highlighter drawn along a line of a PDF's text is laid straight over that line. For Double-Tap and Squeeze, “System Setting” follows Settings › Apple Pencil.") {
            Toggle("Straighten Shapes", isOn: $snapsShapes).settingsRow()
            Toggle("Snap Highlighter to PDF Text", isOn: $snapsHighlighter).settingsRow()
            Toggle("Circle and Hold to Select", isOn: $circleSelects)
                .accessibilityIdentifier("settings.pencil.circle")
                .settingsRow()
            Toggle("Scribble to Erase", isOn: $scribbleErases)
                .accessibilityIdentifier("settings.pencil.scribble")
                .settingsRow()
            SettingsChoiceRow(title: "Double-Tap", value: pencilDoubleTap.displayName, selection: $pencilDoubleTap) {
                ForEach(PencilAction.allCases) { Text($0.displayName).tag($0) }
            }
            .accessibilityIdentifier("settings.pencil.doubleTap")
            SettingsChoiceRow(title: "Squeeze", value: pencilSqueeze.displayName, selection: $pencilSqueeze) {
                ForEach(PencilAction.allCases) { Text($0.displayName).tag($0) }
            }
            .accessibilityIdentifier("settings.pencil.squeeze")
        }
    }

    private var paperSection: some View {
        SettingsSection("New Notebooks") {
            SettingsChoiceRow(title: "Template", value: template.displayName, selection: $template) {
                ForEach(PaperFamily.allCases) { family in
                    Section(family.displayName) {
                        ForEach(family.templates) { Text($0.displayName).tag($0) }
                    }
                }
            }
            SettingsChoiceRow(title: "Paper Colour", value: color.displayName, selection: $color) {
                ForEach(PaperColor.allCases) { Text($0.displayName).tag($0) }
            }
            SettingsChoiceRow(title: "Page Size", value: size.displayName, selection: $size) {
                ForEach(PageSize.allCases) { Text($0.displayName).tag($0) }
            }
        }
    }

    private var journalSection: some View {
        let journal = journalID.isEmpty ? nil : store.dailyJournal
        return SettingsSection("Daily Journal", note: "Touch and hold a notebook, then choose Use as Daily Journal. Press ⌘T in the library to open today's page. With Print Today's Events on, each new day's page starts with that day's events from your calendar, as text you can move or delete. They are read on this iPad.") {
            SettingsValueRow(title: "Journal", value: journal?.title ?? String(localized: "None"))
            Toggle("Show On This Day", isOn: $showsOnThisDay).settingsRow()
            Toggle("Print Today's Events", isOn: Binding(get: { printsAgenda }, set: setPrintsAgenda))
                .accessibilityIdentifier("settings.journal.agenda")
                .settingsRow()
            if journal != nil {
                SettingsActionRow(title: "Stop Using Daily Journal", systemImage: "calendar.badge.minus") { store.setDailyJournal(nil) }
            }
        }
        .notice("Calendar", isPresented: Binding(get: { agendaMessage != nil }, set: { if !$0 { agendaMessage = nil } }),
                message: Text(agendaMessage ?? "")) {
            Button("OK", role: .cancel) {}
        }
    }

    private var historySection: some View {
        SettingsSection("Writing History", note: "MathNotes keeps a list of the days you wrote and which pages. It is not synced, but it is part of every backup you make.") {
            Toggle("Keep Writing History", isOn: Bindable(activity).isEnabled).settingsRow()
            SettingsActionRow(title: "Clear Writing History…", systemImage: "trash", role: .destructive) { confirmingHistoryClear = true }
                .disabled(!activity.hasHistory)
                .notice("Clear your writing history?", isPresented: $confirmingHistoryClear,
                        message: Text("The week strip and calendar start afresh. Your notebooks and pages aren't affected.")) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear Writing History", role: .destructive) { Task { await activity.clear() } }
                }
        }
    }

    private var searchSection: some View {
        SettingsSection("Search", note: "Notebooks can be found from the Home Screen by their title or by the words in them. That index is kept by iPadOS on this iPad. Locked notebooks are never in it.") {
            Toggle("Find Notebooks in Spotlight", isOn: $showsInSpotlight)
                .accessibilityIdentifier("settings.spotlight")
                .settingsRow()
                .onChange(of: showsInSpotlight) { _, _ in
                    if let app { app.spotlight.schedule(app.library, after: .zero) }
                }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        if let sync = app?.sync {
            SettingsSection("iCloud", note: "Each notebook is copied whole to your private iCloud storage and from there to your other iPads. A notebook open here syncs when you close it. If one was changed on two devices before they could sync, the newer version is kept and the older is saved beside it as a conflicted copy. Writing history is not synced. Turning sync off leaves the copy in iCloud. To remove it, turn sync off on every device, then delete MathNotes's data in Settings › your name › iCloud.") {
                Toggle("Sync with iCloud", isOn: Bindable(sync).isEnabled)
                    .accessibilityIdentifier("settings.sync.toggle")
                    .settingsRow()
                if case .unavailable(let reason) = sync.availability {
                    Text(reason).font(.subheadline).foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("settings.sync.unavailable")
                        .settingsRow()
                } else if sync.question == .accountChanged {
                    Text(SyncQuestion.accountChangedMessage).font(.subheadline).foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("settings.sync.account")
                        .settingsRow()
                    SettingsActionRow(title: "Sync with This Account", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await sync.answer(true) }
                    }
                    .accessibilityIdentifier("settings.sync.account.allow")
                    SettingsActionRow(title: "Turn Off Sync", systemImage: "icloud.slash") {
                        Task { await sync.answer(false) }
                    }
                    .accessibilityIdentifier("settings.sync.account.refuse")
                } else if sync.isEnabled {
                    SettingsActionRow(title: "Sync Now", systemImage: "arrow.triangle.2.circlepath", isBusy: sync.isSyncing) {
                        Task { await sync.syncNow() }
                    }
                    .disabled(sync.isSyncing)
                    .accessibilityIdentifier("settings.sync.now")
                    if let date = sync.lastSynced {
                        let when = SyncCenter.formatted(date)
                        // What a pass did is shown once one has finished since launch, and not beside an error.
                        if let status = sync.status, sync.lastError == nil {
                            Text("\(status). Last synced \(when).").syncStatusRow("settings.sync.status")
                        } else {
                            Text("Last synced \(when).").syncStatusRow("settings.sync.last")
                        }
                    }
                    if let error = sync.lastError {
                        Text(error).font(.subheadline).foregroundStyle(Color.tomato)
                            .accessibilityIdentifier("settings.sync.error")
                            .settingsRow()
                    }
                    if let problem = sync.uploads.problem {
                        Text(problem.message).font(.subheadline).foregroundStyle(Color.tomato)
                            .accessibilityIdentifier("settings.sync.uploads")
                            .settingsRow()
                    }
                    ForEach(sync.lastReport?.failed ?? [], id: \.id) { failure in
                        SyncFailureRow(failure: failure, title: store.record(failure.id)?.title)
                    }
                }
            }
        }
    }

    private var backupSection: some View {
        SettingsSection("Backup", note: "A backup is one file holding your whole library: every notebook, locked or recently deleted ones included, with your folders, smart shelves, stickers and writing history. It is not encrypted, so keep it somewhere you trust. Restoring adds what is missing and never replaces a notebook: one that differs from the backup comes back beside yours as a copy.") {
            SettingsActionRow(title: "Back Up Library…", systemImage: "externaldrive", isBusy: backupWork == .backingUp, action: backUp)
                .accessibilityIdentifier("settings.backup.create")
            if let lastBackup {
                SettingsActionRow(title: "Share the Backup Again", systemImage: "square.and.arrow.up") { shareAgain(lastBackup) }
                    .accessibilityIdentifier("settings.backup.share")
            }
            SettingsActionRow(title: "Restore from a Backup…", systemImage: "arrow.counterclockwise", isBusy: backupWork == .restoring) {
                choosingBackup = true
            }
            .accessibilityIdentifier("settings.backup.restore")
        }
        .disabled(backupWork != nil)
    }

    private var aboutSection: some View {
        SettingsSection("About") {
            Colophon()
            NavigationLink {
                AcknowledgementsView()
            } label: {
                HStack(spacing: Space.x3) {
                    Label("Acknowledgements", systemImage: "text.book.closed")
                    Spacer(minLength: 0)
                    SettingsRowGlyph(systemName: "chevron.forward")
                }
            }
            .buttonStyle(.settingsRow)
        }
    }

    /// Turning it on asks for the calendar there and then, so a new day's page never has to.
    private func setPrintsAgenda(_ on: Bool) {
        printsAgenda = on
        guard on else { return }
        Task {
            do {
                _ = try await Agenda.calendar.events(on: .now, calendar: .current)
            } catch {
                printsAgenda = false
                agendaMessage = error.localizedDescription
            }
        }
    }

    private func backUp() {
        backupWork = .backingUp
        backingUp = Task {
            defer { backupWork = nil }
            do {
                guard let url = try await store.backupToShare() else { return }
                guard !Task.isCancelled else { return ExportFolder.discard([url]) }
                if let lastBackup { ExportFolder.discard([lastBackup]) }
                lastBackup = url
                sharedBackup = SharedFile(url: url)
            } catch {
                backupMessage = error.localizedDescription
            }
        }
    }

    private func shareAgain(_ made: URL) {
        Task {
            do {
                if let url = try await store.backupToShare(made) { sharedBackup = SharedFile(url: url) }
            } catch {
                backupMessage = error.localizedDescription
            }
        }
    }

    private func restore(_ url: URL) {
        backupWork = .restoring
        Task {
            defer { backupWork = nil }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let summary = try await store.restoreBackup(from: url)
                await activity.load()
                await AppModel.shared.flashcards.load()
                backupMessage = summary.message
            } catch {
                backupMessage = error.localizedDescription
            }
        }
    }
}

/// The app's mark, its name and its version.
private struct Colophon: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–" }

    var body: some View {
        VStack(spacing: Space.x3) {
            Image("LaunchIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityLabel("MathNotes")
                .accessibilityAddTraits(.isImage)
            VStack(spacing: Space.x1) {
                Text(verbatim: "MathNotes").displayFont(28, relativeTo: .title)
                Text(verbatim: "\(String(localized: "Version")) \(version)").metaStyle()
            }
            .accessibilityElement(children: .combine)
            Text("Handwrite math with Apple Pencil and turn it into clean LaTeX. Your notes stay on your iPad, and in your own iCloud if you turn sync on.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.x5)
        .padding(.top, Space.x6)
        .padding(.bottom, Space.x3)
    }
}

struct AcknowledgementsView: View {
    private struct Entry: Identifiable {
        let id: String
        let name: String
        let use: String
        let license: String
    }

    private var entries: [Entry] {
        [("Fraunces", String(localized: "Library headings, cloth labels and empty states"), "OFL-Fraunces"),
         ("Bricolage Grotesque", String(localized: "Print cover titles"), "OFL-BricolageGrotesque"),
         ("Archivo", String(localized: "The opening screen"), "OFL-Archivo")].map { name, use, file in
            let url = Bundle.main.url(forResource: file, withExtension: "txt")
            return Entry(id: file, name: name, use: use, license: url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x8) {
                ForEach(entries) { entry in
                    SettingsSection(title: Text(verbatim: entry.name)) {
                        Text(entry.use).foregroundStyle(Color.textSecondary).settingsRow()
                        DisclosureGroup("SIL Open Font License 1.1") {
                            Text(entry.license)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, Space.x2)
                        }
                        .settingsRow()
                    }
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Space.x5)
            .padding(.top, Space.x4)
            .padding(.bottom, Space.x10)
        }
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        .navigationTitle("Acknowledgements")
        .barGround(.paper)
    }
}

@MainActor private extension Text {
    func syncStatusRow(_ identifier: String) -> some View {
        font(.subheadline).foregroundStyle(Color.textSecondary).accessibilityIdentifier(identifier).settingsRow()
    }
}

/// A notebook the last sync couldn't copy, and why.
struct SyncFailureRow: View {
    let failure: SyncFailure
    let title: String?

    private let tile = RoundedRectangle.plate

    var body: some View {
        HStack(spacing: Space.x3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.tomato)
                .frame(width: 30, height: 30)
                .background(Color.well, in: tile)
                .overlay { tile.strokeBorder(Color.hairline) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title ?? String(localized: "A notebook from iCloud")) didn't sync")
                Text(failure.reason.message).font(.subheadline).foregroundStyle(Color.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .settingsRow()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.sync.failed")
    }
}
