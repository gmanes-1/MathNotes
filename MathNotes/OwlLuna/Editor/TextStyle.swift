import SwiftUI

private enum Emphasis: CaseIterable, Identifiable {
    case bold, italic, underline

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        }
    }

    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .bold: "b"
        case .italic: "i"
        case .underline: "u"
        }
    }

    var path: WritableKeyPath<TextBox, Bool> {
        switch self {
        case .bold: \.isBold
        case .italic: \.isItalic
        case .underline: \.isUnderlined
        }
    }

    var identifier: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        }
    }
}

/// A text box's controls in the arrange bar: bold, italic and underline where the bar has room, and the Text Style
/// card that holds everything at once.
struct TextStyleControls: View {
    let session: EditorSession
    let box: TextBox
    let roomy: Bool
    let shortcuts: Bool
    @State private var showing = false

    var body: some View {
        HStack(spacing: 0) {
            if roomy {
                ForEach(Emphasis.allCases) { emphasis in
                    let on = box[keyPath: emphasis.path]
                    Button { session.updateText { $0[keyPath: emphasis.path].toggle() } } label: {
                        Label(emphasis.title, systemImage: emphasis.symbol)
                    }
                    .background { if on { RoundedRectangle.thumb.fill(Color.well).padding(.horizontal, 3).padding(.vertical, 5) } }
                    .keyboardShortcut(shortcuts ? KeyboardShortcut(emphasis.key) : nil)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("editor.arrange.\(emphasis.identifier)")
                }
            }
            Button { showing = true } label: { Label("Text Style", systemImage: "textformat.size") }
                .panel("Text Style", isPresented: $showing) { TextStylePanel(session: session) }
                .accessibilityIdentifier("editor.arrange.style")
        }
    }
}

/// All of a text box's look on one card, nothing behind another: typeface, size, emphasis, alignment, list, and the
/// colours of the words and of the wash behind them.
struct TextStylePanel: View {
    let session: EditorSession
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var height: CGFloat?

    /// As tall as it needs, and scrolls where the screen is shorter than that.
    var body: some View {
        if let box = session.selectedItem?.text {
            ScrollView {
                card(box).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: 344)
            .frame(idealHeight: height)
        }
    }

    private func card(_ box: TextBox) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            MathNotesSegmentedPicker("Typeface", selection: Binding(get: { box.face }, set: { face in session.updateText { $0.face = face } }),
                                   options: TextBox.Face.allCases) { face in
                VStack(spacing: 0) {
                    Text(verbatim: "Ag").font(Font(sample(box, face: face)))
                    Text(face.displayName).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(face.displayName))
            }
            .accessibilityIdentifier("editor.text.face")
            sizes(box)
            let stacked = textSize.isAccessibilitySize
            (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x3)) : AnyLayout(HStackLayout(spacing: Space.x3))) {
                emphasis(box)
                alignment(box)
            }
            MathNotesSegmentedPicker("List", selection: Binding(get: { box.list }, set: { list in
                session.updateText {
                    $0.list = list
                    if list != nil { $0.alignment = .leading }
                }
            }), options: [nil] + TextBox.List.allCases.map(Optional.some)) { list in
                Label(list?.displayName ?? String(localized: "No List"), systemImage: list?.symbol ?? "text.alignleft").labelStyle(.iconOnly)
            }
            .accessibilityIdentifier("editor.text.list")
            colours(box)
        }
        .padding(Space.x4)
    }

    /// The face as it would be set, at a size to compare them by.
    private func sample(_ box: TextBox, face: TextBox.Face) -> UIFont {
        var sample = box
        sample.face = face
        sample.fontSize = 20
        return sample.font()
    }

    /// The four sizes, and the box's own when it has been scaled to one of its own.
    private func sizes(_ box: TextBox) -> some View {
        let presets = TextBox.sizes.map(\.points)
        return MathNotesSegmentedPicker("Size", selection: Binding(get: { box.fontSize }, set: { size in session.updateText { $0.fontSize = size } }),
                                      options: presets.contains(box.fontSize) ? presets : presets + [box.fontSize]) { points in
            Text(TextBox.sizes.first { $0.points == points }?.name ?? String(localized: "\(Int(points.rounded())) pt"))
        }
        .accessibilityIdentifier("editor.text.size")
    }

    private func emphasis(_ box: TextBox) -> some View {
        HStack(spacing: 0) {
            ForEach(Emphasis.allCases) { emphasis in
                let on = box[keyPath: emphasis.path]
                Button { session.updateText { $0[keyPath: emphasis.path].toggle() } } label: {
                    Label(emphasis.title, systemImage: emphasis.symbol)
                        .labelStyle(.iconOnly)
                        .font(.body.weight(on ? .semibold : .medium))
                        .foregroundStyle(on ? Color.ink : Color.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .background { if on { thumb } }
                        .contentShape(Rectangle())
                        .contentShape(.hoverEffect, RoundedRectangle.thumb.inset(by: 4))
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("editor.text.\(emphasis.identifier)")
            }
        }
        .background { Color.clear.well(in: RoundedRectangle.track) }
        .fixedSize()
    }

    /// What a segment that is on stands on, as the segmented pickers' chosen one does.
    private var thumb: some View {
        let shape = RoundedRectangle.thumb
        return Color.clear
            .board(in: shape)
            .overlay { if scheme == .dark { shape.fill(Color.ink.opacity(0.10)) } }
            .overlay { if contrast == .increased { shape.strokeBorder(Color.inkSecondary, lineWidth: 1) } }
            .padding(4)
    }

    /// A list keeps to the left, so turning one of the others on takes the list away.
    private func alignment(_ box: TextBox) -> some View {
        MathNotesSegmentedPicker("Alignment", selection: Binding(get: { box.alignment }, set: { alignment in
            session.updateText {
                $0.alignment = alignment
                if alignment != .leading { $0.list = nil }
            }
        }), options: TextBox.Alignment.allCases) {
            Label($0.displayName, systemImage: $0.symbol).labelStyle(.iconOnly)
        }
        .accessibilityIdentifier("editor.text.alignment")
    }

    /// Shown as they will look on the page, over its paper.
    private func colours(_ box: TextBox) -> some View {
        let onDark = session.inkIsLight || session.paperIsNight
        let paper = Color(uiColor: session.inkIsLight ? PageRenderer.paperColor(.charcoal) : PageRenderer.paperColor(.white, night: session.paperIsNight))
        return HStack(spacing: Space.x4) {
            blot(box, onDark: onDark, paper: paper)
            VStack(alignment: .leading, spacing: Space.x1) {
                heading("Text Colour")
                PaletteStrip(title: "Text Colour", selection: box.tint, options: TextBox.Tint.allCases, paper: paper, name: \.displayName,
                             identifier: { "editor.text.colour.\($0.rawValue)" }, color: { Color(uiColor: $0.color(onDark: onDark)) }) { tint in
                    session.updateText { $0.tint = tint }
                }
                heading("Highlight Colour")
                PaletteStrip(title: "Highlight Colour", selection: box.highlight, options: [nil] + TextBox.Highlight.allCases.map(Optional.some), paper: paper,
                             name: { $0?.displayName ?? String(localized: "No Highlight") },
                             identifier: { "editor.text.highlight.\($0?.rawValue ?? "none")" },
                             color: { $0.map { Color(uiColor: $0.color(onDark: onDark)) } }) { highlight in
                    session.updateText { $0.highlight = highlight }
                }
            }
        }
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    /// The box's words as they stand on its page, in its colour over its wash.
    private func blot(_ box: TextBox, onDark: Bool, paper: Color) -> some View {
        var sample = box
        sample.fontSize = 22
        return Text(verbatim: "Aa")
            .font(Font(sample.font()))
            .underline(box.isUnderlined)
            .foregroundStyle(Color(uiColor: box.tint.color(onDark: onDark)))
            .padding(.horizontal, 2)
            .background { if let highlight = box.highlight { Color(uiColor: highlight.color(onDark: onDark)) } }
            .frame(width: 56, height: 56)
            .background(paper, in: RoundedRectangle.plate)
            .plate(in: RoundedRectangle.plate)
            .accessibilityHidden(true)
    }
}

/// The palette laid along a strip with a square knob on the chosen colour, the way a pen's own ink is mixed. A tap
/// picks a colour; the knob can also be slid along, and picks where it is let go.
private struct PaletteStrip<Value: Hashable>: View {
    let title: LocalizedStringKey
    let selection: Value
    let options: [Value]
    let paper: Color
    let name: (Value) -> String
    let identifier: (Value) -> String
    /// Nil for none, which the strip shows struck through.
    let color: (Value) -> Color?
    let choose: (Value) -> Void
    @State private var sliding: Value?
    @State private var width: CGFloat = 0
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shown = sliding ?? selection
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button { choose(option) } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay { if option == shown { knob } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(name(option)))
                .accessibilityAddTraits(option == selection ? .isSelected : [])
                .accessibilityIdentifier(identifier(option))
            }
        }
        .background { band.frame(height: 16) }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .simultaneousGesture(DragGesture(minimumDistance: 6)
            .onChanged { sliding = option(at: $0.location.x) }
            .onEnded { drag in
                let picked = option(at: drag.location.x)
                sliding = nil
                if picked != selection { choose(picked) }
            })
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    private func option(at x: CGFloat) -> Value {
        let index = Int((x / max(width, 1) * CGFloat(options.count)).rounded(.down))
        return options[min(max(index, 0), options.count - 1)]
    }

    private var band: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                if let fill = color(option) {
                    fill
                } else {
                    Color.clear.overlay {
                        GeometryReader { proxy in
                            Path { path in
                                path.move(to: CGPoint(x: proxy.size.width * 0.3, y: proxy.size.height))
                                path.addLine(to: CGPoint(x: proxy.size.width * 0.7, y: 0))
                            }
                            .stroke(Color.tomato, lineWidth: 1.5)
                        }
                    }
                }
            }
        }
        .background(paper)
        .clipShape(RoundedRectangle.thumb)
        .overlay { RoundedRectangle.thumb.strokeBorder(plateEdge(contrast), lineWidth: 1) }
    }

    private var knob: some View {
        RoundedRectangle.thumb
            .fill(Color.board)
            .overlay { RoundedRectangle.thumb.strokeBorder(Color.ink, lineWidth: 1.5) }
            .frame(width: 14, height: 28)
            .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
    }
}
