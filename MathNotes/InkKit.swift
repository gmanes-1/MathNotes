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
