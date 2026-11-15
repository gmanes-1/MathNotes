import SwiftUI
import UIKit
import PencilKit

/// An isolated visual check of the display-only stroke-width experiment.
/// This screen uses generated sample ink and never reads or changes a notebook.
@MainActor
struct InkDisplayComparisonView: View {
    private let pageRect = CGRect(x: 0, y: 0, width: 340, height: 210)
    private let original = Self.makeSampleDrawing()
    private var thinner: PKDrawing { original.displayThinner(by: 0.8) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x5) {
                Text("The two samples use the same PencilKit strokes. The right side is a separate display copy with point sizes reduced to 80%.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                sample(title: "Original", drawing: original)
                sample(title: "Thinner display · 80%", drawing: thinner)

                Text("This is only a rendering comparison. It does not change the ink in your notebooks or the way Apple Pencil captures pressure.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(Space.x4)
        }
        .background(Color.paper)
        .navigationTitle("Stroke Display")
        .navigationBarTitleDisplayMode(.inline)
        .barGround(.paper)
    }

    private func sample(title: String, drawing: PKDrawing) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(title).font(.headline).foregroundStyle(Color.ink)
            Image(uiImage: drawing.image(from: pageRect, scale: 2))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.plate))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.plate)
                        .stroke(Color.hairline, lineWidth: 1)
                }
        }
    }

    private static func makeSampleDrawing() -> PKDrawing {
        let now = Date()
        let strokes: [PKStroke] = [
            makeStroke(points: (0..<48).map { index in
                let t = CGFloat(index) / 47
                let x = 28 + t * 280
                let y = 54 + sin(t * .pi * 2) * 17
                let width = 3.8 + (sin(t * .pi) * 2.8)
                return point(x: x, y: y, time: t, width: width, force: 0.45 + 0.45 * sin(t * .pi))
            }, color: .black, date: now),
            makeStroke(points: (0..<48).map { index in
                let t = CGFloat(index) / 47
                let x = 28 + t * 280
                let y = 112 + cos(t * .pi * 2) * 13
                let width = 2.6 + sin(t * .pi) * 2.0
                return point(x: x, y: y, time: t, width: width, force: 0.35 + 0.5 * sin(t * .pi))
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
