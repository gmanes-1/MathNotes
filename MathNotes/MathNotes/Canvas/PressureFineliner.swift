import UIKit
import PencilKit
import MaLiang

/// Uses the actual MaLiang Canvas/Brush for live ink, then converts MaLiang's
/// finished line strip into a regular PKStroke for the notebook's existing
/// persistence, undo, replay and export pipeline.
@MainActor
final class MaLiangFinelinerCaptureView: UIView, @preconcurrency ActionObserver {
    weak var notebookCanvas: PageCanvasView?
    let maliangCanvas: Canvas
    var onStrokeCommitted: ((PKDrawing, PKStroke) -> Void)?
    private var inkColor = UIColor.label
    private var referenceWidth: CGFloat = 2.7
    private var usesPressure = false
    private(set) var isEnabled = false

    init(canvas: PageCanvasView) {
        notebookCanvas = canvas
        maliangCanvas = Canvas(frame: .zero)
        super.init(frame: canvas.bounds)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true

        maliangCanvas.translatesAutoresizingMaskIntoConstraints = false
        maliangCanvas.backgroundColor = .clear
        maliangCanvas.isPencilMode = true
        addSubview(maliangCanvas)
        NSLayoutConstraint.activate([
            maliangCanvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            maliangCanvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            maliangCanvas.topAnchor.constraint(equalTo: topAnchor),
            maliangCanvas.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        maliangCanvas.addObserver(self)
        configure(preset: nil, enabled: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(preset: ToolPreset?, enabled: Bool, allowsFingerDrawing: Bool = false) {
        let active = enabled && preset?.inkType == .monoline
        isEnabled = active
        isUserInteractionEnabled = active
        guard active, let preset else {
            maliangCanvas.isUserInteractionEnabled = false
            maliangCanvas.resetData()
            return
        }

        referenceWidth = max(CGFloat(preset.width), 0.1)
        inkColor = preset.uiColor
        usesPressure = preset.pressureSensitive ?? false
        maliangCanvas.isPencilMode = !allowsFingerDrawing

        // These are the same brush settings used by MaLiangFinelinerPrototypeView.
        // Pressure OFF makes the minimum ratio 1, so the width is constant.
        // Pressure ON uses MaLiang's native force response at a fixed strength.
        let brush = maliangCanvas.defaultBrush!
        brush.pointSize = referenceWidth
        brush.pointStep = 0.6
        brush.opacity = 1
        brush.minimumForceRatio = usesPressure ? 0.43 : 1
        brush.forceSensitive = usesPressure ? 0.08 : 0
        brush.color = inkColor
        brush.use()
        maliangCanvas.isUserInteractionEnabled = true
    }

    // Keep normal UIKit hit-testing. MaLiang is in Pencil mode, so it accepts
    // Apple Pencil input while the ancestor scroll view's gesture recognizers
    // continue to observe finger contacts for pinch-to-zoom.
    override func layoutSubviews() {
        super.layoutSubviews()
        maliangCanvas.frame = bounds
    }

    func canvas(_ canvas: Canvas, didFinishLineAt point: CGPoint, force: CGFloat) {
        guard canvas === maliangCanvas, let notebookCanvas, isEnabled,
              let strip = canvas.data.elements.last as? LineStrip,
              !strip.lines.isEmpty else {
            maliangCanvas.resetData()
            return
        }

        var controlPoints: [PKStrokePoint] = []
        var time: TimeInterval = 0
        // MaLiang stores line coordinates and point sizes divided by its render
        // target scale. Convert them back to UIKit points before handing them to
        // PencilKit; otherwise strokes are misplaced and their widths drift.
        let renderScale = max(canvas.scale, 0.001)
        let renderOffset = canvas.contentOffset
        for line in strip.lines {
            let startInCanvas = CGPoint(x: line.begin.x * renderScale - renderOffset.x,
                                        y: line.begin.y * renderScale - renderOffset.y)
            let endInCanvas = CGPoint(x: line.end.x * renderScale - renderOffset.x,
                                      y: line.end.y * renderScale - renderOffset.y)
            let start = notebookLocation(for: startInCanvas)
            let end = notebookLocation(for: endInCanvas)
            let width = min(max(line.pointSize * renderScale, 0.2), referenceWidth)
            // MaLiang's Metal renderer stamps many dots along each short line.
            // Keeping only the segment endpoints in PencilKit made the saved
            // stroke visibly faceted. Resample each segment into sub-point steps
            // so the committed vector path follows the same smooth curve.
            let distance = hypot(end.x - start.x, end.y - start.y)
            let subdivisions = max(1, Int(ceil(distance / 0.75)))
            for sample in 0...subdivisions {
                let fraction = CGFloat(sample) / CGFloat(subdivisions)
                let location = CGPoint(x: start.x + (end.x - start.x) * fraction,
                                       y: start.y + (end.y - start.y) * fraction)
                if let last = controlPoints.last,
                   hypot(last.location.x - location.x, last.location.y - location.y) <= 0.01 {
                    continue
                }
                controlPoints.append(makePoint(location, width: width, time: time))
                time += 1.0 / 120.0
            }
        }

        if controlPoints.count == 1, let only = controlPoints.first {
            controlPoints.append(makePoint(only.location, width: only.size.width, time: time))
        }
        guard controlPoints.count >= 2 else {
            maliangCanvas.resetData()
            return
        }

        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        let stroke = PKStroke(ink: PKInk(.monoline, color: inkColor),
                              path: path, transform: .identity, mask: nil)
        let before = notebookCanvas.drawing
        onStrokeCommitted?(before, stroke)
        // The notebook now owns the finished stroke. Clear the temporary Metal
        // surface so it cannot be drawn twice or leak into the next stroke.
        maliangCanvas.resetData()
    }

    private func notebookLocation(for point: CGPoint) -> CGPoint {
        guard let notebookCanvas else { return point }
        // The point passed here has already been converted out of MaLiang's
        // render-target scale and offset. UIView.convert supplies the page's
        // content-coordinate transform, including its current scroll offset.
        return notebookCanvas.convert(point, from: maliangCanvas)
    }

    private func makePoint(_ location: CGPoint, width: CGFloat, time: TimeInterval) -> PKStrokePoint {
        PKStrokePoint(location: location, timeOffset: time,
                      size: CGSize(width: width, height: width), opacity: 1,
                      force: 0.5, azimuth: 0, altitude: .pi / 2)
    }
}
