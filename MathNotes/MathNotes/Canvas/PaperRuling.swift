import SwiftUI

/// How a page's lines, grid or dots are spaced and drawn. Kept in the page's (and the notebook defaults') `extra["ruling"]`,
/// so older builds keep it as an unknown key. A page without one is drawn exactly as before.
struct PaperRuling: Sendable, Hashable {
    /// Gap between lines, grid cells or dots, in the template's 800-unit page width.
    var spacing: CGFloat
    /// Multiplies the template's line width and dot size.
    var weight: CGFloat

    init(spacing: CGFloat, weight: CGFloat) {
        self.spacing = spacing
        self.weight = weight
    }

    init?(_ json: JSONValue?) {
        guard let object = json?.objectValue, let spacing = object["spacing"]?.doubleValue, let weight = object["weight"]?.doubleValue,
              spacing > 0, weight > 0 else { return nil }
        self.init(spacing: CGFloat(spacing), weight: CGFloat(weight))
    }

    var json: JSONValue { .object(["spacing": .number(Double(spacing)), "weight": .number(Double(weight))]) }

    static let spacingRange: ClosedRange<CGFloat> = 14...60
    static let weightRange: ClosedRange<CGFloat> = 0.5...3

    /// The templates whose spacing and line weight can be adjusted.
    static let adjustable: [PaperTemplate] = [.narrowRuled, .wideRuled, .grid, .dotted]

    static func standard(for template: PaperTemplate) -> PaperRuling {
        let spacing: CGFloat = switch template {
        case .wideRuled: 38
        case .grid, .dotted: 26
        default: 28
        }
        return PaperRuling(spacing: spacing, weight: 1)
    }

    /// The gap in millimetres on a page `pageWidth` points wide.
    func millimetres(onPageWidth pageWidth: CGFloat) -> Double {
        Double(spacing * pageWidth / 800 * 25.4 / 72)
    }
}

extension NotebookPage {
    var ruling: PaperRuling? {
        get { PaperRuling(extra["ruling"]) }
        set { extra["ruling"] = newValue?.json }
    }
}

extension PageDefaults {
    var ruling: PaperRuling? {
        get { PaperRuling(extra["ruling"]) }
        set { extra["ruling"] = newValue?.json }
    }
}

/// A live preview of a template drawn with a ruling, redrawn as the sliders move.
struct RulingPreview: View {
    let template: PaperTemplate
    let color: PaperColor
    let pageSize: CGSize
    let ruling: PaperRuling?

    var body: some View {
        Canvas { context, size in
            context.withCGContext { ctx in
                ctx.setFillColor(PageRenderer.paperColor(color).cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                PageRenderer.drawTemplate(template, color: color, in: ctx, size: size, ruling: ruling)
            }
        }
        .aspectRatio(pageSize.width / max(pageSize.height, 1), contentMode: .fit)
        .overlay { Rectangle().strokeBorder(Color.hairline, lineWidth: 1) }
        .accessibilityHidden(true)
    }
}
