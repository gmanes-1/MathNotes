import UIKit
import PencilKit
import Observation

/// What a restyle changes in the selected ink. The width is on a fixed scale, as Notability's is: it is how thick the
/// strokes are to be, in points of the page, the same for every stroke selected. Colour and opacity are the ones asked
/// for. Whatever is nil is left as it was.
struct InkRestyleChange: Equatable {
    var width: CGFloat?
    var tint: UInt32?
    var opacity: Double?

    var isIdentity: Bool { width == nil && tint == nil && opacity == nil }
}

/// Ink thickness on a fixed, graded scale, as the line widths of Preview are, in points of the page. A pen is set to a
/// grade, the lasso reads the thickness of the ink it holds and shows the grade nearest it, and Style sets one.
enum InkGrade {
    /// From the finest line PencilKit's own tools write to a broad stroke: close together where a little matters, wider
    /// apart where it does not. A pen is set to a grade and PencilKit writes it, held to the range it allows that pen.
    static let steps: [Double] = [0.5, 0.7, 1, 1.4, 2, 2.8, 4, 6, 9, 14, 20, 30]
    /// The grade a new pen starts at.
    static let standard = 1.0

    /// The inks that write a line of this thickness. A marker, crayon or watercolour is as broad as its tool is.
    static func applies(to ink: PKInkingTool.InkType) -> Bool {
        switch ink {
        case .pen, .monoline, .fountainPen, .pencil: true
        default: false
        }
    }

    static func nearest(to width: Double) -> Double {
        steps.min { abs($0 - width) < abs($1 - width) } ?? standard
    }

    /// "1.2": the thickness as it is shown, with no figure that is not worth the room.
    static func label(_ width: Double) -> String {
        width.formatted(.number.precision(.fractionLength(0...2)))
    }
}

enum InkCalibration {
    /// The width in the middle of a stroke's points, which is how thick the stroke is without its swells.
    nonisolated static func middleSize(of stroke: PKStroke) -> CGFloat? {
        let sizes = stroke.path.map(\.size.width).sorted()
        return sizes.isEmpty ? nil : sizes[sizes.count / 2]
    }

    /// The least a point of a stroke may be thinned to, so restyled ink is never made too fine to see.
    static func leastPoint(for ink: PKInkingTool.InkType) -> CGFloat {
        switch ink {
        case .pen, .fountainPen: 2.0
        case .marker: 3.0
        case .crayon, .watercolor: 2.0
        case .pencil: 1.0
        case .monoline: 0.5
        default: 2.0
        }
    }

    /// A colour as the pen stores it: a byte each for red, green, blue and alpha, as it is on light paper. A colour
    /// that can't be read as red, green and blue is left black rather than clear, so ink is never made invisible.
    static func bytes(of color: UIColor) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        guard light.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return ToolPreset.bytes(of: .black) }
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return byte(red) << 24 | byte(green) << 16 | byte(blue) << 8 | byte(alpha)
    }
}

@MainActor
@Observable
final class InkClipboard {
    static let shared = InkClipboard()

    private(set) var strokes: [PKStroke] = []
    @ObservationIgnored private(set) var bounds: CGRect?
    @ObservationIgnored var pastes = 0

    var isEmpty: Bool { strokes.isEmpty }

    func set(_ new: [PKStroke]) {
        strokes = new
        bounds = new.reduce(CGRect?.none) { result, stroke in result?.union(stroke.renderBounds) ?? stroke.renderBounds }
        pastes = 0
    }
}

final class PageScrollView: UIScrollView {
    var panMayBegin: ((CGPoint) -> Bool)?

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer, let panMayBegin {
            let translation = panGestureRecognizer.translation(in: self), now = panGestureRecognizer.location(in: self)
            if !panMayBegin(CGPoint(x: now.x - translation.x, y: now.y - translation.y)) { return false }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

extension PKDrawing {
    /// The strokes at `indices`, made `width` thick, and given a new colour and opacity if those are asked for. A
    /// stroke keeps its own kind of ink and the way its width swells along it: it is made as thick, in the middle of
    /// it, as `width` says. Whatever is not asked for stays as it was.
    @MainActor
    func restyled(_ indices: Set<Int>, width: CGFloat?, tint: UInt32?, opacity: Double?) -> PKDrawing {
        guard !indices.isEmpty else { return self }
        var strokes = self.strokes
        for i in indices where strokes.indices.contains(i) {
            strokes[i] = Self.restyledStroke(strokes[i], width: width, tint: tint, opacity: opacity)
        }
        return PKDrawing(strokes: strokes)
    }

    @MainActor
    private static func restyledStroke(_ stroke: PKStroke, width: CGFloat?, tint: UInt32?, opacity: Double?) -> PKStroke {
        var path = stroke.path
        if let width, width > 0, stroke.path.count > 0, let middle = InkCalibration.middleSize(of: stroke), middle > 0,
           abs(width / middle - 1) > 0.001 {
            let ratio = width / middle
            let finest: CGFloat = 0.5
            let points = stroke.path.map { p in
                // No point is made finer than PencilKit's own finest line, unless it was finer already.
                PKStrokePoint(location: p.location, timeOffset: p.timeOffset,
                              size: CGSize(width: max(p.size.width * ratio, min(p.size.width, finest)),
                                           height: max(p.size.height * ratio, min(p.size.height, finest))),
                              opacity: p.opacity, force: p.force, azimuth: p.azimuth, altitude: p.altitude,
                              secondaryScale: p.secondaryScale)
            }
            path = PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate)
        }
        var ink = stroke.ink
        if tint != nil || opacity != nil {
            let current = InkCalibration.bytes(of: stroke.ink.color)
            let rgb = (tint ?? current) & 0xFFFF_FF00
            let alpha = opacity.map { UInt32((min(max($0, ToolPreset.leastOpacity), 1) * 255).rounded()) } ?? (current & 0xFF)
            ink = PKInk(stroke.ink.inkType, color: ToolPreset.uiColor(rgb | alpha))
        }
        return PKStroke(ink: ink, path: path, transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
    }
}
