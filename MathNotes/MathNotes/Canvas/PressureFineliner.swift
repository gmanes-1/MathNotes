import UIKit
import PencilKit

/// Captures Apple Pencil force for Fineliner and commits the resulting points as a normal PencilKit stroke.
/// The live preview is a vector shape layer; it is never used as the saved drawing.
@MainActor
final class PressureFinelinerCaptureView: UIView {
    private struct Sample {
        var location: CGPoint
        var time: TimeInterval
        var force: CGFloat
        var azimuth: CGFloat
        var altitude: CGFloat
        var viewLocation: CGPoint
    }

    weak var canvas: PageCanvasView?
    var onStrokeBegan: (() -> Void)?
    var onStrokeCommitted: ((PKDrawing, PKStroke) -> Void)?
    private let preview = CAShapeLayer()
    private var samples: [Sample] = []
    private var estimates: [NSNumber: Int] = [:]
    private var startDate = Date()
    private var startTimestamp: TimeInterval = 0
    private var baseWidth: CGFloat = 1
    private var inkColor = UIColor.label
    private var activeTouch: UITouch?
    private(set) var isEnabled = false
    private var allowsFingerDrawing = false

    init(canvas: PageCanvasView) {
        self.canvas = canvas
        super.init(frame: canvas.frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false
        preview.fillColor = inkColor.cgColor
        preview.fillRule = .nonZero
        layer.addSublayer(preview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(preset: ToolPreset?, enabled: Bool, allowsFingerDrawing: Bool = false) {
        let shouldEnable = enabled && preset?.pressureSensitive == true
        isEnabled = shouldEnable
        isUserInteractionEnabled = shouldEnable
        self.allowsFingerDrawing = shouldEnable && allowsFingerDrawing
        if let preset {
            // Match the selected app width and the same learned monoline calibration
            // used by ordinary notebook strokes. Do not read canvas.tool.width here:
            // the capture view, not PencilKit, owns the pressure-sensitive stroke.
            baseWidth = CGFloat((canvas?.tool as? PKInkingTool)?.width ?? CGFloat(preset.width))
                * InkCalibration.factor(for: .monoline)
            inkColor = preset.uiColor
            preview.fillColor = inkColor.cgColor
        }
        if !shouldEnable { cancelStroke() }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isEnabled, bounds.contains(point),
              event?.allTouches?.contains(where: { $0.type == .pencil || (allowsFingerDrawing && $0.type == .direct) }) == true else { return nil }
        return self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        preview.frame = bounds
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isEnabled, let touch = touches.first(where: { $0.type == .pencil || (allowsFingerDrawing && $0.type == .direct) }), canvas != nil else {
            super.touchesBegan(touches, with: event)
            return
        }
        cancelStroke()
        activeTouch = touch
        startDate = Date()
        startTimestamp = touch.timestamp
        onStrokeBegan?()
        append(touch)
        refreshPreview()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, let event, touches.contains(activeTouch) else { return }
        let coalesced = event.coalescedTouches(for: activeTouch) ?? [activeTouch]
        for touch in coalesced { append(touch) }
        refreshPreview()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        if let event {
            for touch in event.coalescedTouches(for: activeTouch) ?? [activeTouch] { append(touch) }
        }
        finishStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        cancelStroke()
    }

    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        for touch in touches {
            guard touch.type == .pencil,
                  let index = touch.estimationUpdateIndex,
                  !touch.estimatedPropertiesExpectingUpdates.contains(.force),
                  let sampleIndex = estimates.removeValue(forKey: index),
                  samples.indices.contains(sampleIndex) else { continue }
            samples[sampleIndex].force = max(touch.force, 0)
            refreshPreview()
        }
    }

    private func append(_ touch: UITouch) {
        guard let canvas else { return }
        let visiblePoint = touch.location(in: self)
        let canvasPoint = canvas.convert(visiblePoint, from: self)
        let contentPoint = CGPoint(x: canvasPoint.x + canvas.contentOffset.x,
                                   y: canvasPoint.y + canvas.contentOffset.y)
        let rawForce = touch.type == .pencil ? max(touch.force, 0) : 1
        let force = samples.last.map { $0.force * 0.62 + rawForce * 0.38 } ?? rawForce
        if let last = samples.last, hypot(last.location.x - contentPoint.x, last.location.y - contentPoint.y) < 0.12,
           abs(last.force - force) < 0.015 { return }
        let sample = Sample(location: contentPoint, time: max(0, touch.timestamp - startTimestamp),
                            force: force, azimuth: touch.azimuthAngle(in: self),
                            altitude: touch.altitudeAngle, viewLocation: visiblePoint)
        samples.append(sample)
        if touch.estimatedPropertiesExpectingUpdates.contains(.force), let index = touch.estimationUpdateIndex {
            estimates[index] = samples.count - 1
        }
    }

    private func widthFactor(_ force: CGFloat) -> CGFloat {
        // Keep the selected width as the reference at average force (1.0).
        // Lighter pressure tapers gently; maximum pressure is only 5% wider.
        let response = 0.95 + 0.05 * pow(min(max(force, 0), 2.0), 0.65)
        return min(max(response, 0.95), 1.05)
    }

    private func refreshPreview() {
        guard !samples.isEmpty, canvas != nil else { preview.path = nil; return }
        let points = samples.map { ($0.viewLocation, max(baseWidth * 0.55 * widthFactor($0.force) / 2, 0.12)) }
        let path = CGMutablePath()
        if points.count == 1 {
            let p = points[0].0, r = points[0].1
            path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        } else {
            var left: [CGPoint] = []
            var right: [CGPoint] = []
            let centers = smoothSamples(points, steps: 6)
            for i in centers.indices {
                let previous = centers[max(i - 1, 0)].0
                let next = centers[min(i + 1, centers.count - 1)].0
                let dx = next.x - previous.x, dy = next.y - previous.y
                let length = max(hypot(dx, dy), 0.001)
                let normal = CGPoint(x: -dy / length, y: dx / length)
                let center = centers[i].0, radius = centers[i].1
                left.append(CGPoint(x: center.x + normal.x * radius, y: center.y + normal.y * radius))
                right.append(CGPoint(x: center.x - normal.x * radius, y: center.y - normal.y * radius))
            }
            if let first = left.first { path.move(to: first) }
            for point in left.dropFirst() { path.addLine(to: point) }
            for point in right.reversed() { path.addLine(to: point) }
            path.closeSubpath()
            for (center, radius) in [centers.first, centers.last].compactMap({ $0 }) {
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2))
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.path = path
        CATransaction.commit()
    }

    private func smoothSamples(_ points: [(CGPoint, CGFloat)], steps: Int) -> [(CGPoint, CGFloat)] {
        guard points.count > 1 else { return points }
        var result: [(CGPoint, CGFloat)] = []
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                let t2 = t * t, t3 = t2 * t
                func interpolate(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * ((2 * b) + (-a + c) * t + (2*a - 5*b + 4*c - d) * t2 + (-a + 3*b - 3*c + d) * t3)
                }
                let point = CGPoint(x: interpolate(p0.0.x, p1.0.x, p2.0.x, p3.0.x),
                                    y: interpolate(p0.0.y, p1.0.y, p2.0.y, p3.0.y))
                let radius = max(interpolate(p0.1, p1.1, p2.1, p3.1), 0.12)
                result.append((point, radius))
            }
        }
        if let last = points.last { result.append(last) }
        return result
    }

    private func finishStroke() {
        defer { cancelStroke() }
        guard let canvas, !samples.isEmpty else { return }
        var controlPoints = samples.map { sample in
            let width = max(baseWidth * 0.55 * widthFactor(sample.force), 0.12)
            return PKStrokePoint(location: sample.location, timeOffset: sample.time,
                                 size: CGSize(width: width, height: width), opacity: 1,
                                 force: sample.force, azimuth: sample.azimuth, altitude: sample.altitude)
        }
        if controlPoints.count == 1, let point = controlPoints.first {
            controlPoints.append(PKStrokePoint(location: point.location, timeOffset: point.timeOffset + 0.001,
                                               size: point.size, opacity: point.opacity, force: point.force,
                                               azimuth: point.azimuth, altitude: point.altitude))
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: startDate)
        let stroke = PKStroke(ink: PKInk(.monoline, color: inkColor), path: path, transform: .identity, mask: nil)
        let before = canvas.drawing
        onStrokeCommitted?(before, stroke)
    }

    private func cancelStroke() {
        samples.removeAll(keepingCapacity: true)
        estimates.removeAll(keepingCapacity: true)
        activeTouch = nil
        preview.path = nil
    }
}
