import SwiftUI
import UIKit
import PencilKit

/// Isolated visual comparison using generated sample ink only.
@MainActor
struct InkDisplayComparisonView: View {
    private let pageRect = CGRect(x: 0, y: 0, width: 340, height: 210)
    private let original = Self.makeSampleDrawing()
    private var thinner: PKDrawing { Self.thinCopy(of: original, factor: 0.8) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Both samples use the same PencilKit strokes. The second is a separate copy with stroke point sizes reduced to 80%.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                sample(title: "Original", drawing: original)
                sample(title: "Thinner display · 80%", drawing: thinner)

                Text("This preview uses generated ink only. It does not change your notebooks or Apple Pencil pressure capture.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Stroke Display")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sample(title: String, drawing: PKDrawing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Image(uiImage: drawing.image(from: pageRect, scale: 2))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                }
        }
    }

    /// Rebuilds only path point sizes; positions, pressure, tilt, timing, ink and masks remain intact.
    private static func thinCopy(of drawing: PKDrawing, factor: CGFloat) -> PKDrawing {
        let scale = min(max(factor, 0.1), 1)
        let strokes = drawing.strokes.map { stroke -> PKStroke in
            let points = stroke.path.map { point in
                PKStrokePoint(location: point.location,
                              timeOffset: point.timeOffset,
                              size: CGSize(width: max(point.size.width * scale, 0.2),
                                           height: max(point.size.height * scale, 0.2)),
                              opacity: point.opacity,
                              force: point.force,
                              azimuth: point.azimuth,
                              altitude: point.altitude,
                              secondaryScale: point.secondaryScale)
            }
            let path = PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate)
            return PKStroke(ink: stroke.ink, path: path, transform: stroke.transform,
                            mask: stroke.mask, randomSeed: stroke.randomSeed)
        }
        return PKDrawing(strokes: strokes)
    }

    private static func makeSampleDrawing() -> PKDrawing {
        let now = Date()
        let strokes: [PKStroke] = [
            makeStroke(points: (0..<48).map { index in
                let t = CGFloat(index) / 47
                return point(x: 28 + t * 280, y: 54 + sin(t * .pi * 2) * 17,
                             time: t, width: 3.8 + sin(t * .pi) * 2.8,
                             force: 0.45 + 0.45 * sin(t * .pi))
            }, color: .black, date: now),
            makeStroke(points: (0..<48).map { index in
                let t = CGFloat(index) / 47
                return point(x: 28 + t * 280, y: 112 + cos(t * .pi * 2) * 13,
                             time: t, width: 2.6 + sin(t * .pi) * 2,
                             force: 0.35 + 0.5 * sin(t * .pi))
            }, color: UIColor(red: 0.12, green: 0.34, blue: 0.72, alpha: 1), date: now),
            makeStroke(points: (0..<34).map { index in
                let t = CGFloat(index) / 33
                return point(x: 38 + t * 255, y: 166 + sin(t * .pi * 3) * 5,
                             time: t, width: 1.7, force: 0.5)
            }, color: UIColor(red: 0.78, green: 0.18, blue: 0.16, alpha: 1), date: now)
        ]
        return PKDrawing(strokes: strokes)
    }

    private static func point(x: CGFloat, y: CGFloat, time: CGFloat, width: CGFloat, force: CGFloat) -> PKStrokePoint {
        PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: TimeInterval(time),
                      size: CGSize(width: width, height: width), opacity: 1,
                      force: force, azimuth: 0, altitude: .pi / 2, secondaryScale: 1)
    }

    private static func makeStroke(points: [PKStrokePoint], color: UIColor, date: Date) -> PKStroke {
        let path = PKStrokePath(controlPoints: points, creationDate: date)
        return PKStroke(ink: PKInk(.pen, color: color), path: path,
                        transform: .identity, mask: nil, randomSeed: 1)
    }
}
