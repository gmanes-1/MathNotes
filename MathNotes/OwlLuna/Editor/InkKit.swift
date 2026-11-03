import UIKit
import PencilKit
import Observation

/// What a restyle changes in the selected ink. The width is a multiple of what it is now, never a width worked out
/// from a guess, so the ink grows and shrinks from what it is; colour and opacity are the ones asked for, and are
/// left as they were when they are nil.
struct InkRestyleChange: Equatable {
    var widthScale: CGFloat = 1
    var tint: UInt32?
    var opacity: Double?

    var isIdentity: Bool { abs(widthScale - 1) < 0.001 && tint == nil && opacity == nil }
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
    /// The strokes at `indices`, made thicker or thinner by `widthScale`, and given a new colour and opacity if those
    /// are asked for. Each stroke keeps its own kind of ink and the way its width swells along it; whatever is not
    /// asked for stays as it was.
    @MainActor
    func restyled(_ indices: Set<Int>, widthScale: CGFloat, tint: UInt32?, opacity: Double?) -> PKDrawing {
        guard !indices.isEmpty else { return self }
        var strokes = self.strokes
        for i in indices where strokes.indices.contains(i) {
            strokes[i] = Self.restyledStroke(strokes[i], widthScale: widthScale, tint: tint, opacity: opacity)
        }
        return PKDrawing(strokes: strokes)
    }

    @MainActor
    private static func restyledStroke(_ stroke: PKStroke, widthScale: CGFloat, tint: UInt32?, opacity: Double?) -> PKStroke {
        var path = stroke.path
        if abs(widthScale - 1) > 0.001, stroke.path.count > 0 {
            let kind = PKInkingTool.InkType(rawValue: stroke.ink.inkType.rawValue) ?? .pen
            let least = InkCalibration.leastPoint(for: kind)
            let points = stroke.path.map { p -> PKStrokePoint in
                // Never thinner than is still seen, and never thicker than it was if it was already finer than that.
                let width = max(p.size.width * widthScale, min(p.size.width, least))
                let height = max(p.size.height * widthScale, min(p.size.height, least))
                return PKStrokePoint(location: p.location, timeOffset: p.timeOffset, size: CGSize(width: width, height: height),
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
