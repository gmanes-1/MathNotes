import SwiftUI
import PencilKit

/// The menu that stands beside the ink the lasso has selected, and nowhere else on screen: Style, Copy, Cut,
/// Duplicate, Paste, Turn into Text, Make Flashcard and Delete. Style opens inline, below the buttons, with the colour,
/// the width and the opacity of the selected strokes; the ink changes as the knob moves and is kept when it is let go.
struct InkSelectionMenu: View {
    /// The style of the selected ink, read when the menu appears and whenever other ink is selected.
    let initialStyle: () -> ToolPreset?
    /// Changes when other ink is selected.
    let selectionToken: Int
    let canPaste: Bool
    let canMakeCard: Bool
    let onTurnIntoText: () -> Void
    let onMakeCard: () -> Void
    let onCopy: () -> Void
    let onCut: () -> Void
    let onPaste: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    /// The style asked for, as a pen: the ink follows it.
    let onRestyle: (ToolPreset) -> Void
    /// The style asked for is to be kept.
    let onSettle: () -> Void

    @State private var styling = false
    @State private var style = ToolPreset(ink: .pen, color: 0x1B22_30FF, width: 2.7)
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 6)
    private static let panelWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            actions
            if styling {
                Rectangle().fill(Color.hairline).frame(height: 1)
                stylePanel
            }
        }
        .board(in: RoundedRectangle.bar)
        .onAppear(perform: refresh)
        .onChange(of: selectionToken) { refresh() }
    }

    private func refresh() {
        if let current = initialStyle() { style = current }
    }

    // MARK: Buttons

    private var actions: some View {
        HStack(spacing: 0) {
            button("Style", "paintbrush.pointed", identifier: "style", isOn: styling) {
                withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { styling.toggle() }
                if !styling { onSettle() }
            }
            button("Copy", "doc.on.doc", identifier: "copy", action: onCopy)
            button("Cut", "scissors", identifier: "cut", action: onCut)
            button("Duplicate", "plus.square.on.square", identifier: "duplicate", action: onDuplicate)
            if canPaste {
                button("Paste", "doc.on.clipboard", identifier: "paste", action: onPaste)
            }
            rule
            button("Turn into Text", "text.viewfinder", identifier: "text", action: onTurnIntoText)
            if canMakeCard {
                button("Make Flashcard", "rectangle.on.rectangle.angled", identifier: "card", action: onMakeCard)
            }
            rule
            button("Delete", "trash", identifier: "delete", role: .destructive, action: onDelete)
        }
        .padding(.horizontal, Space.x1)
        .padding(.vertical, 2)
    }

    private var rule: some View {
        Rectangle().fill(Color.hairline).frame(width: 1, height: 24).padding(.horizontal, Space.x1)
    }

    private func button(_ title: LocalizedStringKey, _ symbol: String, identifier: String, isOn: Bool = false,
                        role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) { Label(title, systemImage: symbol) }
            .buttonStyle(TrayIconStyle(isOn: isOn))
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityIdentifier("editor.ink.\(identifier)")
    }

    // MARK: Style

    private var stylePanel: some View {
        let ink = style.inkType ?? .pen
        let solid = Color(uiColor: ToolPreset.uiColor(style.tint))
        let night = scheme == .dark
        let paper = night ? Color.well : Color.labelCream
        return VStack(alignment: .leading, spacing: Space.x2) {
            PenRoll(kind: Binding(get: { style.inkType ?? .pen }, set: { kind in
                var next = style
                next.ink = kind.rawValue
                next.width = ToolPreset.clamped(next.width, to: ToolPreset.widthRange(of: kind))
                change(next)
                onSettle()
            }), ink: solid, paper: paper, night: night)
            LazyVGrid(columns: Self.columns, spacing: 0) {
                ForEach(ToolPreset.palette(for: ink), id: \.self) { color in colourButton(color) }
            }
            VStack(alignment: .leading, spacing: Space.x2) {
                HStack {
                    Text("Width").font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                    Spacer()
                    Text(style.width.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(Color.textSecondary)
                }
                HStack(spacing: Space.x1) {
                    ForEach(Array(ToolPreset.widthSteps(of: ink).enumerated()), id: \.offset) { index, step in
                        let chosen = abs(style.width - step) < 0.02
                        Button {
                            var next = style
                            next.width = step
                            change(next)
                            onSettle()
                        } label: {
                            Circle().fill(solid)
                                .frame(width: CGFloat(3 + 7 * Double(index) / 7),
                                       height: CGFloat(3 + 7 * Double(index) / 7))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .contentShape(Rectangle())
                                .overlay { if chosen { Circle().strokeBorder(Color.accentColor, lineWidth: 2).frame(width: 34, height: 34) } }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Width \(step.formatted(.number.precision(.fractionLength(0...1))))"))
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                        .accessibilityIdentifier("editor.ink.menu.width.\(index + 1)")
                    }
                }
            }
            WidthBar(measure: .opacity,
                     travel: Binding(get: { (style.opacity - ToolPreset.leastOpacity) / (1 - ToolPreset.leastOpacity) }, set: { travel in
                         var next = style
                         next.opacity = ((ToolPreset.leastOpacity + (1 - ToolPreset.leastOpacity) * travel) * 20).rounded() / 20
                         change(next)
                     }),
                     ink: solid, paper: paper, night: night,
                     value: style.opacityName,
                     identifier: "editor.ink.menu.opacity", onSettle: onSettle)
        }
        .padding(Space.x3)
        .frame(width: Self.panelWidth)
    }

    private func colourButton(_ color: UInt32) -> some View {
        let chosen = style.tint == color
        return Button {
            var next = style
            next.setTint(color)
            change(next)
            onSettle()
        } label: {
            Circle()
                .fill(Color(uiColor: ToolPreset.uiColor(color)))
                .frame(width: 24, height: 24)
                .padding(4)
                .overlay { if chosen { Circle().strokeBorder(Color.accentColor, lineWidth: 2) } }
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(ToolPreset.colorName(color)))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func change(_ next: ToolPreset) {
        style = next
        onRestyle(next)
    }
}
