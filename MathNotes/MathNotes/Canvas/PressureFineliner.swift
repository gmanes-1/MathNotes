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
    private var pressureAmount: CGFloat = 0.08
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
        pressureAmount = min(max(CGFloat(preset.pressureAmount ?? 0.08), 0), 1)
        maliangCanvas.isPencilMode = !allowsFingerDrawing

        // These are the same brush settings used by MaLiangFinelinerPrototypeView.
        // Pressure OFF makes the minimum ratio 1, so the width is constant.
        // Pressure ON uses MaLiang's native force curve and the tray slider.
        let brush = maliangCanvas.defaultBrush!
        brush.pointSize = referenceWidth * 0.3
        brush.pointStep = 0.6
        brush.opacity = 0.72
        brush.minimumForceRatio = usesPressure ? 0.43 : 1
        brush.forceSensitive = usesPressure ? pressureAmount : 0
        brush.color = inkColor
        brush.use()
        maliangCanvas.isUserInteractionEnabled = true
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isEnabled, bounds.contains(point) else { return nil }
        return super.hitTest(point, with: event) ?? self
    }

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
        for line in strip.lines {
            let start = notebookLocation(for: line.begin)
            let end = notebookLocation(for: line.end)
            let width = max(line.pointSize, 0.2)
            if controlPoints.isEmpty || hypot(controlPoints.last!.location.x - start.x,
                                               controlPoints.last!.location.y - start.y) > 0.01 {
                controlPoints.append(makePoint(start, width: width, time: time))
                time += 0.001
            }
            controlPoints.append(makePoint(end, width: width, time: time))
            time += 0.001
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
        // UIView.convert already returns coordinates in the notebook canvas'
        // content coordinate space. Its bounds origin is contentOffset, so adding
        // contentOffset again shifts every committed stroke twice as far while
        // scrolling/zooming (and can place it outside the visible page).
        return notebookCanvas.convert(point, from: maliangCanvas)
    }

    private func makePoint(_ location: CGPoint, width: CGFloat, time: TimeInterval) -> PKStrokePoint {
        PKStrokePoint(location: location, timeOffset: time,
                      size: CGSize(width: width, height: width), opacity: 1,
                      force: 0.5, azimuth: 0, altitude: .pi / 2)
    }
}
