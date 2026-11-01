import SwiftUI
import PencilKit

/// The pen-style popover over an ink selection: Style, Cut, Copy, Paste, Duplicate, Delete, a Colour grid,
/// and the width and opacity of the selected strokes.
struct InkSelectionMenu: View {
    let preset: ToolPreset
    let forSelection: Bool
    let canPaste: Bool
    let canDelete: Bool
    let onStyle: () -> Void
    let onCut: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onWidth: (Double) -> Void
    let onOpacity: (Double) -> Void
    let onColor: (UInt32) -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            // Top Action Buttons
            HStack(spacing: Space.x2) {
                if forSelection {
                    Button(action: onStyle) { Label("Style", systemImage: "paintbrush.pointed") }
                    Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
                    Button(action: onCut) { Label("Cut", systemImage: "scissors") }
                    Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
                }
                if canPaste {
                    Button(action: onPaste) { Label("Paste", systemImage: "doc.on.clipboard") }
                }
                Spacer(minLength: 0)
                if canDelete {
                    Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                }
            }
            .labelStyle(.iconOnly)
            .font(.body.weight(.medium))
            .frame(minHeight: 44)

            if forSelection {
                Divider()
                
                let ink = preset.inkType ?? .pen
                let solid = Color(uiColor: ToolPreset.uiColor(preset.tint))
                let paper = scheme == .dark ? Color.well : Color.labelCream
                let night = scheme == .dark

                // Color Palette
                LazyVGrid(columns: Self.columns, spacing: 0) {
                    ForEach(ToolPreset.palette(for: ink), id: \.self) { color in
                        Button {
                            onColor(color)
                        } label: {
                            Circle()
                                .fill(Color(uiColor: ToolPreset.uiColor(color)))
                                .frame(width: 24, height: 24)
                                .padding(4)
                                .overlay {
                                    if preset.tint == color {
                                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(ToolPreset.colorName(color)))
                    }
                }
                .padding(.bottom, Space.x1)

                // Width and Opacity Sliders
                WidthBar(travel: Binding(get: { preset.widthTravel }, set: { onWidth($0) }),
                         ink: solid, paper: paper, night: night,
                         value: preset.width.formatted(.number.precision(.fractionLength(0...1))),
                         identifier: "editor.ink.menu.width")
                
                WidthBar(measure: .opacity,
                         travel: Binding(get: { (preset.opacity - ToolPreset.leastOpacity) / (1 - ToolPreset.leastOpacity) },
                                         set: { onOpacity(((ToolPreset.leastOpacity + (1 - ToolPreset.leastOpacity) * $0) * 20).rounded() / 20) }),
                         ink: solid, paper: paper, night: night,
                         value: preset.opacityName,
                         identifier: "editor.ink.menu.opacity")
            }
        }
        .padding(Space.x4)
        .frame(minWidth: 320, idealWidth: 340)
    }
}
