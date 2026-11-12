import UIKit
import PencilKit
import Observation

/// How broad PencilKit lays a kind of ink down for each point of a pen's width.
enum FinelinerPressure {
    static let minimumForceRatio: CGFloat = 0.68
    static let forceSensitivity: CGFloat = 0.08

    /// MaLiang smooths force from one sample to the next, then maps half-scale
    /// Pencil force to the selected maximum width.
    static func widthRatio(for force: CGFloat, previousForce: CGFloat? = nil) -> CGFloat {
        let current = min(max(force, 0), 1)
        let filtered = previousForce.map { $0 * 0.95 + current * 0.05 } ?? current
        let pressure = min(max(filtered, 0), 1)
        return minimumForceRatio + (1 - minimumForceRatio) * pow(pressure, 0.8)
    }

    /// Rebuilds only the stroke's width profile. Location, timing, force, colour,
    /// opacity, transform, mask and PencilKit's smooth vector rendering are kept.
    static func adjusted(_ stroke: PKStroke, maximumWidth: CGFloat) -> PKStroke {
        guard maximumWidth > 0, stroke.path.count > 0 else { return stroke }
        var previousForce: CGFloat?
        let points = stroke.path.map { point -> PKStrokePoint in
            let ratio = widthRatio(for: point.force, previousForce: previousForce)
            let force = min(max(point.force, 0), 1)
            previousForce = previousForce.map { $0 * 0.95 + force * 0.05 } ?? force
            let visibleFloor = min(maximumWidth, 0.2)
            let width = max(maximumWidth * ratio, visibleFloor)
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
