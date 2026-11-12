import UIKit
import PencilKit
import Observation

/// How broad PencilKit lays a kind of ink down for each point of a pen's width.
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

/// The Fineliner keeps PencilKit's smooth path and renderer, but uses MaLiang's
/// calibrated force response for the width profile of each completed stroke.
enum FinelinerPressure {
    static let minimumForceRatio: CGFloat = 0.43
    static let forceSensitivity: CGFloat = 0.08

    /// MaLiang smooths force from one sample to the next, then maps half-scale
    /// Pencil force to the selected maximum width.
    static func widthRatio(for force: CGFloat, previousForce: CGFloat? = nil) -> CGFloat {
        let current = min(max(force, 0), 1)
        let filtered = previousForce.map { $0 * 0.95 + current * 0.05 } ?? current
        let pressure = min(filtered * 2, 1)
        let curve = 1 + forceSensitivity * 3
        return minimumForceRatio + (1 - minimumForceRatio) * pow(pressure, curve)
    }

    /// Rebuilds only the stroke's width profile. Location, timing, force, colour,
    /// opacity, transform, mask and PencilKit's smooth vector rendering are kept.
    static func adjusted(_ stroke: PKStroke, maximumWidth: CGFloat) -> PKStroke {
        guard maximumWidth > 0, !stroke.path.isEmpty else { return stroke }
        var previousForce: CGFloat?
        let points = stroke.path.map { point -> PKStrokePoint in
            let ratio = widthRatio(for: point.force, previousForce: previousForce)
            let force = min(max(point.force, 0), 1)
            previousForce = previousForce.map { $0 * 0.95 + force * 0.05 } ?? force
            let width = max(maximumWidth * ratio, 0.2)
            return PKStrokePoint(location: point.location, timeOffset: point.timeOffset,
                                 size: CGSize(width: width, height: width), opacity: point.opacity,
                                 force: point.force, azimuth: point.azimuth, altitude: point.altitude,
                                 secondaryScale: point.secondaryScale)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate)
        return PKStroke(ink: stroke.ink, path: path, transform: stroke.transform,
                        mask: stroke.mask, randomSeed: stroke.randomSeed)
    }
}
