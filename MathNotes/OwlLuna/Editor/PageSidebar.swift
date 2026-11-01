import SwiftUI

/// The pages of the notebook down the side of the editor, as in Notability: a thumbnail of each that follows the
/// writing, a tap to turn to it, a drag to put it somewhere else, and a hold for adding, duplicating and deleting.
/// It is shown and put away from the bar, and stays as it was left.
struct PageSidebar: View {
    let session: EditorSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingDelete: UUID?
    @State private var dragging: UUID?
    @State private var dropTarget: UUID?

    static let width: CGFloat = 164

    private var document: NotebookDocument { session.document }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.hairline).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Space.x4) {
                        ForEach(Array(document.pages.enumerated()), id: \.element.id) { index, page in
                            cell(page, at: index)
                        }
                    }
                    .padding(.vertical, Space.x4)
                    .padding(.horizontal, Space.x3)
                }
                .scrollIndicators(.hidden)
                .onAppear { scrollToCurrent(proxy, animated: false) }
                .onChange(of: session.currentPage) { scrollToCurrent(proxy, animated: true) }
            }
        }
        .frame(width: Self.width)
        .background(Color.desk)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.hairline).frame(width: 1) }
        .sensoryFeedback(.alignment, trigger: dropTarget) { _, target in target != nil }
        .notice("Delete this page?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                message: Text("You can undo this.")) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Page", role: .destructive) { if let pendingDelete { document.removePages([pendingDelete]) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Pages"))
        .accessibilityIdentifier("editor.sidebar")
    }

    private var header: some View {
        HStack(spacing: Space.x2) {
            Text(document.pageCountText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .accessibilityIdentifier("editor.sidebar.count")
            Spacer(minLength: 0)
            Button { session.addPage(after: session.currentPage) } label: { Label("Add Page", systemImage: "plus") }
                .buttonStyle(.plateIcon)
                .disabled(document.isReadOnly)
                .accessibilityHint(Text("Adds a page after the one on show"))
                .accessibilityIdentifier("editor.sidebar.add")
        }
        .padding(.leading, Space.x3)
        .padding(.trailing, Space.x1)
        .frame(height: 52)
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        guard document.pages.indices.contains(session.currentPage) else { return }
        let id = document.pages[session.currentPage].id
        if animated {
            withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: .center) }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func cell(_ page: NotebookPage, at index: Int) -> some View {
        let isCurrent = index == session.currentPage
        return Button { session.go(to: index) } label: {
            SidebarThumbnail(document: document, page: page, index: index, isCurrent: isCurrent)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .overlay { if dropTarget == page.id { insertionBar(after: dropsAfter(index)) } }
        .heldMenu(Text("Page \(index + 1)"), when: !document.isReadOnly, draggable: true) { menu(for: page, at: index) }
        .onDrag {
            dragging = page.id
            let provider = NSItemProvider()
            provider.register(PageReference(id: page.id))
            return provider
        }
        .dropDestination(for: PageReference.self) { items, _ in
            dropTarget = nil
            guard !document.isReadOnly, let item = items.first, let destination = document.index(of: page.id) else { return false }
            return move(item.id, to: destination)
        } isTargeted: { targeted in
            if targeted { dropTarget = page.id } else if dropTarget == page.id { dropTarget = nil }
        }
        .accessibilityLabel(isCurrent ? Text("Page \(index + 1) of \(document.pages.count), current") : Text("Page \(index + 1) of \(document.pages.count)"))
        .accessibilityHint(Text("Turns to this page"))
        .accessibilityActions {
            if !document.isReadOnly, index > 0 { Button("Move earlier") { move(page.id, to: index - 1) } }
            if !document.isReadOnly, index < document.pages.count - 1 { Button("Move later") { move(page.id, to: index + 1) } }
        }
        .accessibilityIdentifier("editor.sidebar.page.\(index + 1)")
        .id(page.id)
    }

    /// A page dropped on a later page takes its place and lands after it; on an earlier one, before it.
    private func dropsAfter(_ index: Int) -> Bool {
        guard let dragging, let from = document.index(of: dragging) else { return false }
        return from < index
    }

    private func insertionBar(after: Bool) -> some View {
        let shift = (Space.x4 / 2 + 1.5) * (after ? 1 : -1)
        return InsertionRule(vertical: false)
            .stroke(Color.mustard, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
            .frame(height: 3)
            .offset(y: shift)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: after ? .bottom : .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @discardableResult
    private func move(_ pageID: UUID, to destination: Int) -> Bool {
        guard !document.isReadOnly, let from = document.index(of: pageID), from != destination,
              document.pages.indices.contains(destination) else { return false }
        withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) {
            document.movePage(from: from, to: destination)
        }
        AccessibilityNotification.Announcement(String(localized: "Moved to page \(destination + 1)")).post()
        return true
    }

    @ViewBuilder
    private func menu(for page: NotebookPage, at index: Int) -> some View {
        Button { session.addPage(after: index) } label: { Label("Insert Page After", systemImage: "doc.badge.plus") }
        Button { Task { await session.duplicatePage(at: index) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        if index > 0 {
            Button { move(page.id, to: index - 1) } label: { Label("Move Earlier", systemImage: "arrow.up") }
        }
        if index < document.pages.count - 1 {
            Button { move(page.id, to: index + 1) } label: { Label("Move Later", systemImage: "arrow.down") }
        }
        MenuBreak()
        Button(role: .destructive) { pendingDelete = page.id } label: { Label("Delete", systemImage: "trash") }
    }
}

/// One page in the sidebar: its thumbnail, drawn again a moment after the ink on it changes, and its number.
private struct SidebarThumbnail: View {
    let document: NotebookDocument
    let page: NotebookPage
    let index: Int
    let isCurrent: Bool
    @PaperNight private var night
    @State private var image: UIImage?

    var body: some View {
        let revision = document.inkRevision[page.id] ?? 0
        VStack(spacing: Space.x1) {
            Group {
                if let image {
                    Image(uiImage: image).resizable()
                } else {
                    Rectangle().fill(Color(uiColor: page.paperShown(night: night)))
                }
            }
            .aspectRatio(page.shownSize.width / max(page.shownSize.height, 1), contentMode: .fit)
            .overlay { Rectangle().strokeBorder(Color.hairline, lineWidth: 1) }
            .overlay { if isCurrent { StitchedSelection() } }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .padding(3)
            Text(index + 1, format: .number)
                .font(.caption.weight(isCurrent ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isCurrent ? Color.ink : Color.textSecondary)
        }
        .contentShape(Rectangle())
        .task(id: "\(page.id)-\(page.inkHash ?? "")-\(page.appearanceKey)-\(night)-\(revision)") {
            // Writing changes the ink with every stroke: the thumbnail waits for the pen to rest before it is drawn again.
            if revision > 0, image != nil {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
            }
            image = await document.thumbnail(for: page, night: night)
        }
    }
}
