import SwiftUI

/// What a shelf shows: its scope, narrowed by a search, in the order chosen.
struct ShelfFilter {
    var scope: LibraryScope
    var tree: FolderTree
    /// What a tag shelf or a smart shelf looks for.
    var rule: TagRule?
    /// The notebooks a search found; nil when nothing is searched for.
    var matches: Set<UUID>?
    var sort: LibrarySortOrder
    var reversed = false

    /// A folder shows what is in it and in the folders inside it.
    func shown(_ records: [NotebookRecord]) -> [NotebookRecord] {
        let inside: Set<UUID> = if case .folder(let id) = scope { tree.subtree(id) } else { [] }
        // The daily journal lives behind the Journal button, not on the shelves or in folders.
        let scoped = records.filter { record in !record.isJournal || scope == .trash }.filter { record in
            switch scope {
            case .all: !record.isTrashed
            case .favorites: !record.isTrashed && record.isFavorite
            case .trash: record.isTrashed
            case .folder: !record.isTrashed && record.folder.map { inside.contains($0.id) } ?? false
            case .tag, .smart: !record.isTrashed && rule?.matches(notebook: record.tags) == true
            }
        }
        let searched = matches.map { found in scoped.filter { found.contains($0.id) } } ?? scoped
        return searched.sorted(by: sort, reversed: reversed)
    }

    /// Select All takes what is shown, and nothing the scope or the search leaves out.
    func selectingAll(_ records: [NotebookRecord]) -> Set<UUID> { Set(shown(records).map(\.id)) }
}

/// The columns a row of the list has room for. The title always shows; the others go, tags first, as the pane narrows
/// or the text grows, and what they said moves into a line under the title.
struct ShelfColumns: OptionSet, Hashable {
    let rawValue: Int

    static let pages = ShelfColumns(rawValue: 1 << 0)
    static let changed = ShelfColumns(rawValue: 1 << 1)
    static let folder = ShelfColumns(rawValue: 1 << 2)
    static let tags = ShelfColumns(rawValue: 1 << 3)
    static let all: ShelfColumns = [.pages, .changed, .folder, .tags]

    /// What each takes at the standard text size, before it is scaled with the text.
    static let titleMinimum: CGFloat = 180
    static let spacing = Space.x3
    /// The cover, the selection box and the row's own margins, which don't grow with the text.
    static let fixed: CGFloat = 32 + 24 + spacing * 2 + Space.x3 * 2

    static func width(of column: ShelfColumns) -> CGFloat {
        switch column {
        case .pages: 72
        case .changed: 112
        case .folder: 128
        default: 140
        }
    }

    private static let dropped: [ShelfColumns] = [.tags, .folder, .pages, .changed]

    /// At the accessibility sizes a row is the title with everything else under it.
    static func fitting(width: CGFloat, scale: CGFloat, isAccessibilitySize: Bool) -> ShelfColumns {
        guard !isAccessibilitySize else { return [] }
        var columns = ShelfColumns.all
        for column in dropped where needs(columns, scale: scale) > width { columns.remove(column) }
        return columns
    }

    private static func needs(_ columns: ShelfColumns, scale: CGFloat) -> CGFloat {
        let shown = dropped.filter(columns.contains)
        return fixed + (titleMinimum + shown.reduce(0) { $0 + width(of: $1) + spacing }) * scale
    }
}

/// A run of the list's rows on one board, ruled apart in ink under a well band naming the run, as a ledger is.
struct ShelfListBoard<Rows: View>: View {
    let title: String
    var cloth: ClothColor?
    @ViewBuilder var rows: Rows

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.x2) {
                if let cloth { SpineChip(cloth: cloth).scaleEffect(0.7) }
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, Space.x3)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.well)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            rows
        }
        .clipShape(RoundedRectangle.plate)
        .plate(in: RoundedRectangle.plate, fill: .board)
    }
}

/// The names over the list's columns. Title and Last changed sort by themselves; touched again, they turn the order round.
struct ShelfListHeadings: View {
    let columns: ShelfColumns
    let isSelecting: Bool
    @Binding var sort: LibrarySortOrder
    @Binding var reversed: Bool
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: ShelfColumns.spacing) {
            Color.clear.frame(width: isSelecting ? 32 + 24 + ShelfColumns.spacing : 32, height: 1)
            heading(String(localized: "Title"), sorts: .title)
                .frame(maxWidth: .infinity, alignment: .leading)
            if columns.contains(.pages) {
                Text("Pages").frame(width: ShelfColumns.width(of: .pages) * scale, alignment: .trailing)
            }
            if columns.contains(.changed) {
                heading(String(localized: "Last changed"), sorts: .modified)
                    .frame(width: ShelfColumns.width(of: .changed) * scale, alignment: .leading)
            }
            if columns.contains(.folder) {
                Text("Folder").frame(width: ShelfColumns.width(of: .folder) * scale, alignment: .leading)
            }
            if columns.contains(.tags) {
                Text("Tags").frame(width: ShelfColumns.width(of: .tags) * scale, alignment: .leading)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, Space.x3)
    }

    private func heading(_ name: String, sorts order: LibrarySortOrder) -> some View {
        let chosen = sort == order
        return Button {
            if chosen { reversed.toggle() } else { sort = order; reversed = false }
        } label: {
            HStack(spacing: Space.x1) {
                Text(name)
                if chosen {
                    Image(systemName: (order == .title) != reversed ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold))
                }
            }
            .foregroundStyle(chosen ? Color.ink : Color.textSecondary)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(Text("Sort by \(name)"))
        .accessibilityValue(chosen ? Text(order.summary(reversed: reversed)) : Text(""))
        .accessibilityIdentifier("library.list.sort.\(order.rawValue)")
    }
}

/// One notebook in the list: its cover, its title, and a column each for its pages, when it last changed, its folder
/// and its tags, as many as there is room for.
struct NotebookListRow: View {
    let record: NotebookRecord
    let columns: ShelfColumns
    let isSelecting: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title.isEmpty ? String(localized: "Untitled") : record.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(record.pageCountText)
                        if !record.tags.isEmpty {
                            Text("·")
                            Text(Tags.line(record.tags)).lineLimit(1)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(record.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(uiColor: .systemBackground))
        .hoverEffect(.highlight)
    }
}
/// A row is touched across its whole width and darkens under the finger. Chosen, it has a mustard edge.
private struct ShelfListRowStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Space.x3)
            .padding(.vertical, Space.x2)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background { if configuration.isPressed || isSelected { Color.well } }
            .overlay(alignment: .leading) { if isSelected { Rectangle().fill(Color.mustard).frame(width: 3) } }
            .contentShape(Rectangle())
    }
}

/// A square box, ticked in mustard when its row is chosen: never colour alone.
private struct SelectionBox: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle.thumb
                .fill(isSelected ? Color.mustard : Color.clear)
            RoundedRectangle.thumb
                .strokeBorder(isSelected ? Color.mustard : Color.textSecondary, lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.onMustard)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// The chosen notebooks the tag sheet is open over, with the tags all of them carry and those only some do.
struct SelectionTags: Identifiable {
    let id = UUID()
    let ids: [UUID]
    let common: [String]
    let mixed: [String]
}
