import SwiftUI
import PencilKit

/// Restyling the ink under a lasso selection: its width and its opacity. The ink's colour is left as it is,
/// so restyling never silently recolours handwriting.
struct InkRestyleSheet: View {
    @Binding var preset: ToolPreset
    let apply: (ToolPreset) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    let ink = preset.inkType ?? .pen
                    let solid = Color(uiColor: ToolPreset.uiColor(preset.tint))
                    let paper = scheme == .dark ? Color.well : Color.labelCream
                    let night = scheme == .dark

                    WidthBar(
                        travel: Binding(get: { preset.widthTravel }, set: { travel in
                            var next = preset
                            next.width = ToolPreset.width(at: travel, of: ink)
                            preset = next
                            apply(next)
                        }),
                        ink: solid, paper: paper, night: night,
                        value: preset.width.formatted(.number.precision(.fractionLength(0...1))),
                        identifier: "editor.ink.style.width"
                    )

                    WidthBar(
                        measure: .opacity,
                        travel: Binding(get: {
                            (preset.opacity - ToolPreset.leastOpacity) / (1 - ToolPreset.leastOpacity)
                        }, set: { travel in
                            var next = preset
                            next.opacity = ((ToolPreset.leastOpacity + (1 - ToolPreset.leastOpacity) * travel) * 20).rounded() / 20
                            preset = next
                            apply(next)
                        }),
                        ink: solid, paper: paper, night: night,
                        value: preset.opacityName,
                        identifier: "editor.ink.style.opacity"
                    )
                }
                .padding(Space.x4)
            }
            .navigationTitle("Style of Selected Ink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
