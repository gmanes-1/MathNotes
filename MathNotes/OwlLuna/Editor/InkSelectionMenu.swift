import SwiftUI
import PencilKit

/// The menu that stands beside the ink the lasso has selected, and nowhere else on screen: Style, Copy, Cut,
/// Duplicate, Paste, Turn into Text, Make Flashcard and Delete. Style opens inline, below the buttons, with a colour,
/// a width and an opacity for the selected strokes. The width is on a fixed scale, as Notability's is: the knob stands
/// at how thick the ink is, and moving it makes every selected stroke that thick. The ink changes as the knob moves and
/// is kept when it is let go.
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
    /// What is asked for, against the ink as it is: the ink follows it.
    let onRestyle: (InkRestyleChange) -> Void
    /// What is asked for is to be kept.
    let onSettle: () -> Void

    @State private var styling = false
    /// The colour, opacity and width the ink has, as the menu last read or set them.
    @State private var style = ToolPreset(ink: .pen, color: 0x1B22_30FF, width: 2.7)
    /// What has been asked for since the ink was last kept.
    @State private var pickedWidth: CGFloat?
    @State private var pickedTint: UInt32?
    @State private var pickedOpacity: Double?
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
        forgetAsked()
    }

    private func forgetAsked() {
        pickedWidth = nil
        pickedTint = nil
        pickedOpacity = nil
    }

    /// Keeps what was asked for.
    private func settle() {
        onSettle()
        forgetAsked()
    }

    private func ask() {
        onRestyle(InkRestyleChange(width: pickedWidth, tint: pickedTint, opacity: pickedOpacity))
    }

    // MARK: Buttons

    private var actions: some View {
        HStack(spacing: 0) {
            button("Style", "paintbrush.pointed", identifier: "style", isOn: styling) {
                withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { styling.toggle() }
                if !styling { settle() }
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
            LazyVGrid(columns: Self.columns, spacing: 0) {
                ForEach(ToolPreset.palette(for: ink), id: \.self) { color in colourButton(color) }
            }
            // The width the selected ink has, on the graded scale: the grade nearest it is marked.
            InkGradeRow(width: style.width, identifier: "editor.ink.menu.width") { step in
                style.width = step
                pickedWidth = CGFloat(step)
                ask()
                settle()
            }
            WidthBar(measure: .opacity,
                     travel: Binding(get: { (style.opacity - ToolPreset.leastOpacity) / (1 - ToolPreset.leastOpacity) }, set: { travel in
                         let opacity = ((ToolPreset.leastOpacity + (1 - ToolPreset.leastOpacity) * travel) * 20).rounded() / 20
                         style.opacity = opacity
                         pickedOpacity = opacity
                         ask()
                     }),
                     ink: solid, paper: paper, night: night,
                     value: style.opacityName,
                     identifier: "editor.ink.menu.opacity", onSettle: settle)
        }
        .padding(Space.x3)
        .frame(width: Self.panelWidth)
    }

    private func colourButton(_ color: UInt32) -> some View {
        let chosen = style.tint == color
        return Button {
            style.setTint(color)
            pickedTint = color
            ask()
            settle()
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
}

/// The graded scale of ink thicknesses as a row of dots, each as thick as its grade. The grade nearest `width` is marked
/// and the figure beside the title is the thickness itself, which may lie between two grades.
struct InkGradeRow: View {
    /// How thick the ink is, in points of the page.
    let width: Double
    let identifier: String
    let onPick: (Double) -> Void

    var body: some View {
        let nearest = InkGrade.nearest(to: width)
        VStack(alignment: .leading, spacing: Space.x1) {
            HStack {
                Text("Width")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 0)
                Text(InkGrade.label(width) + " pt")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            HStack(spacing: 0) {
                ForEach(InkGrade.steps, id: \.self) { step in
                    Button { onPick(step) } label: {
                        Circle()
                            .fill(Color.ink)
                            .frame(width: dot(step), height: dot(step))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background {
                                if step == nearest { RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.18)) }
                            }
                            .overlay {
                                if step == nearest { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2) }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Width \(InkGrade.label(step)) points"))
                    .accessibilityAddTraits(step == nearest ? .isSelected : [])
                    .accessibilityIdentifier("\(identifier).\(InkGrade.label(step))")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// The dot grows with the square root of the grade, so the fine grades are told apart.
    private func dot(_ step: Double) -> CGFloat {
        let lo = InkGrade.steps.first ?? 0, hi = InkGrade.steps.last ?? 1
        return 3 + 14 * CGFloat(((step - lo) / (hi - lo)).squareRoot())
    }
}
