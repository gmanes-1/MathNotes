import UIKit
import PencilKit
import Observation

@MainActor
enum InkCalibration {
    private static let key = "inkPointsPerWidth"
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
        case .pen, .fountainPen: 2.0
        case .marker: 3.0
        case .crayon, .watercolor: 2.0
        case .pencil: 1.0
        case .monoline: 0.5
        default: 2.0
        }
    }

    static func pointSize(forWidth width: Double, of ink: PKInkingTool.InkType) -> CGFloat {
        max(CGFloat(width) * factor(for: ink), leastPoint(for: ink))
    }

    static func width(forPointSize size: CGFloat, of ink: PKInkingTool.InkType) -> Double {
        let raw = Double(size / max(factor(for: ink), 0.01))
        return ToolPreset.clamped((raw * 10).rounded() / 10, to: ToolPreset.widthRange(of: ink))
    }

    nonisolated static func middleSize(of stroke: PKStroke) -> CGFloat? {
        let sizes = stroke.path.map(\.size.width).sorted()
        return sizes.isEmpty ? nil : sizes[sizes.count / 2]
    }

    static func learn(from stroke: PKStroke, writtenWith tool: PKInkingTool) {
        guard stroke.path.count >= 4, tool.width > 0,
              stroke.ink.inkType.rawValue == tool.inkType.rawValue,
              let middle = middleSize(of: stroke) else { return }
        let sample = Double(middle / tool.width)
        guard (0.2...6).contains(sample) else { return }
        let name = tool.inkType.rawValue
        let next = factors[name].map { $0 * 0.7 + sample * 0.3 } ?? sample
        factors[name] = next
        if let last = saved[name], abs(last - next) / last < 0.03 { return }
        saved = factors
        UserDefaults.standard.set(factors, forKey: key)
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
    @MainActor
    func restyled(_ indices: Set<Int>, to preset: ToolPreset) -> PKDrawing {
        guard !indices.isEmpty, let kind = preset.inkType else { return self }
        let width = ToolPreset.clamped(preset.width, to: ToolPreset.widthRange(of: kind))
        let target = InkCalibration.pointSize(forWidth: width, of: kind)
        let least = InkCalibration.leastPoint(for: kind)
        let newInk = PKInk(kind, color: preset.uiColor)
        var strokes = self.strokes
        for i in indices where strokes.indices.contains(i) {
            strokes[i] = Self.restyledStroke(strokes[i], to: newInk, kind: kind, target: target, least: least)
        }
        return PKDrawing(strokes: strokes)
    }

    @MainActor
    private static func restyledStroke(_ stroke: PKStroke, to ink: PKInk, kind: PKInkingTool.InkType,
                                       target: CGFloat, least: CGFloat) -> PKStroke {
        let old = Array(stroke.path)
        guard !old.isEmpty, let middle = InkCalibration.middleSize(of: stroke) else { return stroke }
        let sameKind = stroke.ink.inkType.rawValue == kind.rawValue
        let swells = kind == .pen || kind == .fountainPen || kind == .pencil || kind == .crayon || kind == .watercolor
        let points = old.map { p -> PKStrokePoint in
            let ratio: CGFloat = middle > 0.01 ? p.size.width / middle : 1
            let kept: CGFloat = sameKind ? ratio : (swells ? min(max(ratio, 0.6), 1.4) : 1)
            let side = max(target * kept, least)
            let height = sameKind && p.size.width > 0.01 ? side * p.size.height / p.size.width : side
            if sameKind {
                return PKStrokePoint(location: p.location, timeOffset: p.timeOffset, size: CGSize(width: side, height: height),
                                     opacity: p.opacity, force: p.force, azimuth: p.azimuth, altitude: p.altitude,
                                     secondaryScale: p.secondaryScale)
            }
            return PKStrokePoint(location: p.location, timeOffset: p.timeOffset, size: CGSize(width: side, height: side),
                                 opacity: 1, force: max(p.force, 0.5), azimuth: p.azimuth, altitude: p.altitude)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate)
        let finalInk = PKInk(kind, color: ink.color)
        return PKStroke(ink: finalInk, path: path, transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
    }
}
