import UIKit

/// Serializable, renderer-independent ink data. Coordinates and widths are stored in page points,
/// never in screen/zoom coordinates, so the same strokes survive viewport changes.
struct NativeInkDocument: Codable, Sendable {
    var version: Int = 1
    var strokes: [NativeInkStroke] = []
}

struct NativeInkStroke: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var colorRGBA: UInt32
    var baseWidth: CGFloat
    var pressureSensitive: Bool
    var points: [NativeInkPoint]
    var createdAt: Date = .now

    var bounds: CGRect {
        guard let first = points.first else { return .null }
        return points.dropFirst().reduce(CGRect(origin: first.location, size: .zero)) {
            $0.union(CGRect(origin: $1.location, size: .zero))
        }.insetBy(dx: -baseWidth, dy: -baseWidth)
    }
}

struct NativeInkPoint: Codable, Sendable {
    var x: CGFloat
    var y: CGFloat
    var force: CGFloat
    var time: TimeInterval
    var location: CGPoint { CGPoint(x: x, y: y) }

    init(location: CGPoint, force: CGFloat, time: TimeInterval) {
        x = location.x
        y = location.y
        self.force = min(max(force, 0), 1)
        self.time = time
    }
}

/// The common geometry and pressure profile used by both Pen and Fineliner.
/// Pressure never exceeds the selected width: that width is the maximum for either tool.
enum NativeInkGeometry {
    static func width(base: CGFloat, force: CGFloat, pressureSensitive: Bool) -> CGFloat {
        let maximum = max(base, 0.1)
        guard pressureSensitive else { return maximum }
        let normalized = min(max(force, 0), 1)
        return maximum * (0.68 + 0.32 * pow(normalized, 0.8))
    }

    static func path(for points: [NativeInkPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first.location)
        guard points.count > 1 else {
            path.addLine(to: first.location.applying(CGAffineTransform(translationX: 0.01, y: 0.01)))
            return path
        }
        for index in 1..<points.count {
            let previous = points[index - 1].location
            let current = points[index].location
            let midpoint = CGPoint(x: (previous.x + current.x) * 0.5,
                                   y: (previous.y + current.y) * 0.5)
            path.addQuadCurve(to: midpoint, controlPoint: previous)
            if index == points.count - 1 { path.addLine(to: current) }
        }
        return path
    }
}

/// Native touch capture and vector preview. The owning page/document supplies persistence and
/// undo transactions through onStrokeCommitted; this view deliberately has no PencilKit dependency.
@MainActor
final class NativeInkCanvasView: UIView {
    var selectedColor: UIColor = .label
    var selectedWidth: CGFloat = 2.5
    var pressureSensitive = false
    var pencilOnly = true
    var onStrokeCommitted: ((NativeInkStroke) -> Void)?

    private var activePoints: [NativeInkPoint] = []
    private let previewLayer = CAShapeLayer()
    private var committedLayers: [UUID: CAShapeLayer] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        isOpaque = false
        backgroundColor = .clear
        previewLayer.fillColor = UIColor.clear.cgColor
        previewLayer.lineCap = .round
        previewLayer.lineJoin = .round
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled else { return false }
        return super.point(inside: point, with: event)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, accepts(touch) else { return }
        activePoints.removeAll(keepingCapacity: true)
        append(touch)
        updatePreview()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, accepts(touch) else { return }
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        samples.forEach(append)
        updatePreview()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, accepts(touch) else { cancelStroke(); return }
        append(touch)
        finishStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelStroke()
    }

    private func accepts(_ touch: UITouch) -> Bool {
        !pencilOnly || touch.type == .pencil
    }

    private func append(_ touch: UITouch) {
        let force = touch.maximumPossibleForce > 0 ? touch.force / touch.maximumPossibleForce : 1
        let point = NativeInkPoint(location: touch.location(in: self),
                                   force: touch.type == .pencil ? force : 1,
                                   time: touch.timestamp)
        if let last = activePoints.last,
           hypot(last.x - point.x, last.y - point.y) < 0.15 { return }
        activePoints.append(point)
    }

    private func updatePreview() {
        previewLayer.path = NativeInkGeometry.path(for: activePoints).cgPath
        previewLayer.strokeColor = selectedColor.cgColor
        previewLayer.lineWidth = NativeInkGeometry.width(
            base: selectedWidth,
            force: activePoints.last?.force ?? 1,
            pressureSensitive: pressureSensitive
        )
    }

    private func finishStroke() {
        guard !activePoints.isEmpty else { cancelStroke(); return }
        let rgba = Self.rgba(selectedColor)
        let stroke = NativeInkStroke(colorRGBA: rgba, baseWidth: max(selectedWidth, 0.1),
                                     pressureSensitive: pressureSensitive, points: activePoints)
        let committed = CAShapeLayer()
        committed.path = NativeInkGeometry.path(for: activePoints).cgPath
        committed.fillColor = UIColor.clear.cgColor
        committed.strokeColor = selectedColor.cgColor
        committed.lineWidth = max(selectedWidth, 0.1)
        committed.lineCap = .round
        committed.lineJoin = .round
        layer.insertSublayer(committed, below: previewLayer)
        committedLayers[stroke.id] = committed
        onStrokeCommitted?(stroke)
        cancelStroke()
    }

    private func cancelStroke() {
        activePoints.removeAll(keepingCapacity: true)
        previewLayer.path = nil
    }

    private static func rgba(_ color: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(cgColor: color.cgColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return byte(r) << 24 | byte(g) << 16 | byte(b) << 8 | byte(a)
    }

    func display(_ document: NativeInkDocument) {
        committedLayers.values.forEach { $0.removeFromSuperlayer() }
        committedLayers.removeAll()
        for stroke in document.strokes {
            let shape = CAShapeLayer()
            shape.path = NativeInkGeometry.path(for: stroke.points).cgPath
            shape.fillColor = UIColor.clear.cgColor
            shape.strokeColor = UIColor(
                red: CGFloat((stroke.colorRGBA >> 24) & 255) / 255,
                green: CGFloat((stroke.colorRGBA >> 16) & 255) / 255,
                blue: CGFloat((stroke.colorRGBA >> 8) & 255) / 255,
                alpha: CGFloat(stroke.colorRGBA & 255) / 255
            ).cgColor
            shape.lineWidth = stroke.baseWidth
            shape.lineCap = .round
            shape.lineJoin = .round
            layer.insertSublayer(shape, below: previewLayer)
            committedLayers[stroke.id] = shape
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}
