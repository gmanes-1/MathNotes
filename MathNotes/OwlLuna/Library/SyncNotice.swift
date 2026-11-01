import SwiftUI

/// The library's word on sync when something needs a look: a plate in the bar, which opens a card listing each thing.
struct SyncNoticeButton: View {
    let sync: SyncCenter
    let onOpen: (NotebookRecord) -> Void
    @Environment(LibraryStore.self) private var store
    @State private var showing = false
    @State private var confirmingDelete = false
    @State private var confirmingReplace = false

    var body: some View {
        // A conflicted copy deleted before it was seen has nothing left to show.
        let news = sync.news.keeping { store.record($0) != nil }
        if !news.isEmpty { plate(news) }
    }

    private func plate(_ news: SyncNews) -> some View {
        Button { showing = true } label: {
            HStack(spacing: Space.x2) {
                Text(news.count, format: .number)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(news.isTrouble ? Color.onTomato : Color.onPrimaryCloth)
                    .frame(minWidth: 20, minHeight: 20)
                    .padding(.horizontal, news.count > 9 ? Space.x1 : 0)
                    .background(news.isTrouble ? Color.tomato : Color.primaryCloth, in: RoundedRectangle.thumb)
                    .accessibilityHidden(true)
                Text("iCloud")
            }
        }
        .accessibilityLabel(Text("iCloud"))
        .accessibilityValue(Text("\(news.count) notices"))
        .accessibilityIdentifier("library.sync.notice")
        .panel("iCloud", isPresented: $showing) {
            SyncNoticeCard(sync: sync, onOpen: onOpen, onDelete: { confirmingDelete = true }, onReplace: { confirmingReplace = true })
        }
        .notice(Text("Delete \(news.held.count) notebooks?"), isPresented: $confirmingDelete,
                message: Text("Any device that still has them moves them to Recently Deleted, where they stay as long as that device keeps deleted notebooks.")) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await sync.letHeldGo() } }
        }
        .notice(Text("Replace the folder list in iCloud?"), isPresented: $confirmingReplace,
                message: Text("A new one is made from this iPad's folders, and your other devices add theirs to it, so no folder is lost. A folder deleted while folders weren't syncing may come back.")) {
            Button("Cancel", role: .cancel) {}
            Button("Replace") { Task { await sync.replaceFolders() } }
        }
    }
}

/// Each thing sync has to say, ruled like an index card, over when it last synced and what can be done.
private struct SyncNoticeCard: View {
    let sync: SyncCenter
    let onOpen: (NotebookRecord) -> Void
    let onDelete: () -> Void
    let onReplace: () -> Void
    @Environment(LibraryStore.self) private var store
    @Environment(\.panelClose) private var close

    var body: some View {
        let news = sync.news
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Group(subviews: rows(news)) { rows in
                        ForEach(rows) { row in
                            if row.id != rows.first?.id { Rectangle().fill(Color.hairline).frame(height: 1) }
                            row
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 420)
            Rectangle().fill(Color.hairline).frame(height: 1)
            HStack(spacing: Space.x2) {
                if let date = sync.lastSynced {
                    Text("Last synced \(SyncCenter.formatted(date)).")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: Space.x2)
                Button("Dismiss") { closing(then: sync.putAwayNews) }
                    .buttonStyle(.mathNotes(.secondary, compact: true))
                    .accessibilityIdentifier("library.sync.dismiss")
                if news.isTrouble {
                    Button("Try Again") { closing { Task { await sync.syncNow() } } }
                    .buttonStyle(.mathNotes(.primary, compact: true))
                    .disabled(sync.isSyncing)
                    .accessibilityIdentifier("library.sync.retry")
                }
            }
            .padding(Space.x3)
        }
        .frame(width: 380)
        .foregroundStyle(Color.ink)
    }

    private func closing(then action: @escaping () -> Void) {
        if let close { close(then: action) } else { action() }
    }

    @ViewBuilder
    private func rows(_ news: SyncNews) -> some View {
        if let stopped = news.stopped {
            SyncNoticeRow(systemImage: "exclamationmark.triangle", trouble: true, title: Text("Sync stopped"), message: Text(stopped))
        }
        if let problem = news.uploadProblem {
            SyncNoticeRow(systemImage: "icloud.slash", trouble: true, title: Text(problem.title), message: Text(problem.message))
                .accessibilityIdentifier("library.sync.uploads")
        }
        ForEach(news.failed, id: \.self) { failure in
            SyncNoticeRow(systemImage: "exclamationmark.triangle", trouble: true,
                          title: Text("\(store.record(failure.id)?.title ?? String(localized: "A notebook from iCloud")) didn't sync"),
                          message: Text(failure.reason.message))
                .accessibilityIdentifier("library.sync.failed")
        }
        if !news.held.isEmpty {
            SyncNoticeRow(systemImage: "trash.slash", trouble: true, title: Text("\(news.held.count) notebooks weren't deleted"),
                          message: Text("They went missing from this iPad or another device all at once, which looks like a mistake, so sync left them as they are. Keep brings them back everywhere, and Delete lets the deletions go through.")) {
                VStack(spacing: 0) {
                    Button { closing { Task { await sync.keepHeld() } } } label: { Text("Keep").frame(maxWidth: .infinity) }
                        .buttonStyle(.mathNotes(.secondary, compact: true))
                    Button { closing(then: onDelete) } label: { Text("Delete").frame(maxWidth: .infinity) }
                        .buttonStyle(.mathNotes(.destructive, compact: true))
                        .accessibilityIdentifier("library.sync.delete")
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .accessibilityIdentifier("library.sync.held")
        }
        if news.foldersUnreadable {
            SyncNoticeRow(systemImage: "folder.badge.questionmark", trouble: true, title: Text("Folders aren't syncing"),
                          message: Text("The folder list in iCloud can't be read, so folder changes aren't sent or received. Folders on this iPad stay as they are, and notebooks still sync.")) {
                Button("Replace") { closing(then: onReplace) }
                    .buttonStyle(.mathNotes(.secondary, compact: true))
                    .accessibilityIdentifier("library.sync.replaceFolders")
            }
            .accessibilityIdentifier("library.sync.folders")
        }
        ForEach(news.conflictCopies.compactMap { store.record($0) }, id: \.id) { copy in
            SyncNoticeRow(systemImage: "doc.on.doc", trouble: false, title: Text(copy.title),
                          message: Text("Changed on two devices before they could sync. The older version was kept as this copy.")) {
                Button("Open") { closing { onOpen(copy) } }
                    .buttonStyle(.mathNotes(.secondary, compact: true))
            }
            .accessibilityIdentifier("library.sync.copy")
        }
        ForEach(news.journals.compactMap { store.record($0) }, id: \.id) { notebook in
            SyncNoticeRow(systemImage: "calendar", trouble: false, title: Text(notebook.title),
                          message: Text("Two devices each had a daily journal. The one begun first is now the journal on every device, and this one, which this iPad was using, is kept as an ordinary notebook.")) {
                Button("Open") { closing { onOpen(notebook) } }
                    .buttonStyle(.mathNotes(.secondary, compact: true))
            }
            .accessibilityIdentifier("library.sync.journal")
        }
    }
}

private struct SyncNoticeRow<Action: View>: View {
    let systemImage: String
    let trouble: Bool
    let title: Text
    let message: Text
    @ViewBuilder var action: Action

    private let tile = RoundedRectangle.plate

    var body: some View {
        HStack(spacing: Space.x3) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(trouble ? Color.tomato : Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.well, in: tile)
                .overlay { tile.strokeBorder(Color.hairline) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.subheadline.weight(.semibold))
                message.font(.footnote).foregroundStyle(Color.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            action
        }
        .padding(.horizontal, Space.x3)
        .padding(.vertical, Space.x2 + 2)
    }
}

extension SyncNoticeRow where Action == EmptyView {
    init(systemImage: String, trouble: Bool, title: Text, message: Text) {
        self.init(systemImage: systemImage, trouble: trouble, title: title, message: message) { EmptyView() }
    }
}

extension CloudUploads.Problem {
    var title: String {
        switch self {
        case .full: String(localized: "iCloud storage is full")
        case .unreachable: String(localized: "iCloud can't be reached")
        case .other: String(localized: "Some files didn't upload")
        }
    }
}
