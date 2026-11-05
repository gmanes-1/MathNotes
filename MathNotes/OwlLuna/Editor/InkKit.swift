import UIKit
import PencilKit
import Observation

@MainActor
enum InkCalibration {
    private static let key = "inkPointsPerWidth.v2"
    private static var factors: [String: Double] = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    private static var saved: [String: Double] = factors

    static func factor(for ink: PKInkingTool.InkType) -> CGFloat {
        CGFloat(factors[ink.rawValue] ?? guess(ink))
    }

    private static func guess(_ ink: PKInkingTool.InkType) -> Double {
        switch ink {
        case .pen: 1.25
        case .fountainPen: 1.3
        default: 1.0
        }
    }

    static func leastPoint(for ink: PKInkingTool.InkType) -> CGFloat {
        switch ink {
        case .pen, .fountainPen: 0.35
        case .marker: 0.75
        case .crayon, .watercolor: 0.5
        case .pencil: 0.35
        case .monoline: 0.2
        default: 0.35
        }
    }

    static func pointSize(forWidth width: Double, of ink: PKInkingTool.InkType) -> CGFloat {
        max(CGFloat(width) * factor(for: ink), leastPoint(for: ink))
    }

    static func width(forPointSize size: CGFloat, of ink: PKInkingTool.InkType) -> Double {
        let raw = Double(size / max(factor(for: ink), 0.01))
        return ToolPreset.clamped(raw, to: ToolPreset.widthRange(of: ink))
    }

    nonisolated static func middleSize(of stroke: PKStroke) -> CGFloat? {
        let sizes = stroke.path.map(\.size.width).sorted()
        return sizes.isEmpty ? nil : sizes[sizes.count / 2]
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

    static func learn(from stroke: PKStroke, writtenWith tool: PKInkingTool) {
        guard stroke.path.count >= 4, tool.width > 0,
              stroke.ink.inkType.rawValue == tool.inkType.rawValue,
              let middle = middleSize(of: stroke) else { return }
        let sample = Double(middle) / (Double(tool.width) / Double(ToolPreset.writingScale(of: tool.inkType)))
        guard (0.2...6).contains(sample) else { return }
        let name = tool.inkType.rawValue
        let next = factors[name].map { $0 * 0.7 + sample * 0.3 } ?? sample
        factors[name] = next
        if let last = saved[name], abs(last - next) / last < 0.03 { return }
        saved = factors
        UserDefaults.standard.set(factors, forKey: key)
    }

    /// PencilKit can render sub-0.9 pt pen presets at nearly the same apparent width.
    /// Correct the completed stroke's point sizes against the 0.9 pt reference while
    /// preserving each point's pressure-driven variation and all other stroke attributes.
    static func correctedFinePenStroke(_ stroke: PKStroke, preset: ToolPreset) -> PKStroke {
        let referenceWidth = 0.9
        guard preset.inkType == .pen, preset.width < referenceWidth, !stroke.path.isEmpty else { return stroke }
        let scale = CGFloat(preset.width / referenceWidth)
        let points = stroke.path.map { point -> PKStrokePoint in
            let size = CGSize(width: max(point.size.width * scale, 0.2),
                              height: max(point.size.height * scale, 0.2))
            return PKStrokePoint(location: point.location, timeOffset: point.timeOffset, size: size,
                                 opacity: point.opacity, force: point.force, azimuth: point.azimuth,
                                 altitude: point.altitude, secondaryScale: point.secondaryScale)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate)
        return PKStroke(ink: stroke.ink, path: path, transform: stroke.transform,
                        mask: stroke.mask, randomSeed: stroke.randomSeed)
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
    func restyled(_ indices: Set<Int>, widthScale: CGFloat, inkType: PKInkingTool.InkType? = nil, tint: UInt32?, opacity: Double?) -> PKDrawing {
        guard !indices.isEmpty else { return self }
        var strokes = self.strokes
        for i in indices where strokes.indices.contains(i) {
            strokes[i] = Self.restyledStroke(strokes[i], widthScale: widthScale, inkType: inkType, tint: tint, opacity: opacity)
        }
        return PKDrawing(strokes: strokes)
    }

    @MainActor
    private static func restyledStroke(_ stroke: PKStroke, widthScale: CGFloat, inkType: PKInkingTool.InkType?, tint: UInt32?, opacity: Double?) -> PKStroke {
        var path = stroke.path
        if abs(widthScale - 1) > 0.001, stroke.path.count > 0 {
            let points = stroke.path.map { p -> PKStrokePoint in
                // Keep sub-point handwriting visible. A fixed 1–3 pt floor made fine strokes jump back to a
                // thicker width during restyling, especially after zooming into the page.
                let width = max(p.size.width * widthScale, 0.2)
                let height = max(p.size.height * widthScale, 0.2)
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
            ink = PKInk(inkType ?? stroke.ink.inkType, color: ToolPreset.uiColor(rgb | alpha))
        } else if let inkType {
            ink = PKInk(inkType, color: stroke.ink.color)
        }
        return PKStroke(ink: ink, path: path, transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
    }
}
