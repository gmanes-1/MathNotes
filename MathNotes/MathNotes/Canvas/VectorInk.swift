import UIKit
import PencilKit

/// A page-local vector sample. Coordinates and widths are stored in paper points, never screen pixels.
struct VectorInkPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var force: Double
    var time: Double

    var location: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
}

/// The unified Pen and Highlighter use this format instead of PKStroke/PKDrawing.
struct VectorInkStroke: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable { case pen, highlighter }

    var id: UUID
    var kind: Kind
    var color: UInt32
    var width: Double
    var pressureSensitive: Bool
    var points: [VectorInkPoint]

    init(id: UUID = UUID(), kind: Kind, color: UInt32, width: Double,
         pressureSensitive: Bool, points: [VectorInkPoint]) {
        self.id = id
        self.kind = kind
        self.color = color
        self.width = width
        self.pressureSensitive = pressureSensitive
        self.points = points
    }

    /// A compact, forward-compatible manifest field. Older builds preserve it as an unknown page field.
    static func decode(_ raw: String?) -> [VectorInkStroke] {
        guard let raw, let data = Data(base64Encoded: raw) else { return [] }
        return (try? JSONDecoder().decode([VectorInkStroke].self, from: data)) ?? []
    }

    static func encode(_ strokes: [VectorInkStroke]) -> String? {
        guard !strokes.isEmpty, let data = try? JSONEncoder().encode(strokes) else { return nil }
        return data.base64EncodedString()
    }
}


/// Vector geometry is shared by the live canvas, thumbnails, image export and PDF export.
struct VectorInkTool: Sendable {
    var color: UInt32
    var width: Double
    var pressureSensitive: Bool
    var isHighlighter: Bool
}

enum VectorInkRenderer {
    private static func makeColor(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat(value >> 24 & 0xFF) / 255,
                green: CGFloat(value >> 16 & 0xFF) / 255,
                blue: CGFloat(value >> 8 & 0xFF) / 255,
                alpha: CGFloat(value & 0xFF) / 255)
    }

    static func draw(_ strokes: [VectorInkStroke], in context: CGContext, scale: CGFloat = 1,
                     offset: CGPoint = .zero) {
        guard !strokes.isEmpty else { return }
        context.saveGState()
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high
        for stroke in strokes where !stroke.points.isEmpty {
            let color = makeColor(stroke.color)
            let isHighlighter = stroke.kind == .highlighter
            context.setBlendMode(isHighlighter ? .multiply : .normal)
            context.setFillColor(color.withAlphaComponent(color.cgColor.alpha * (isHighlighter ? 0.36 : 1)).cgColor)
            let points = stroke.points
            if points.count == 1 {
                let p = viewPoint(points[0], scale: scale, offset: offset)
                let radius = diameter(stroke, at: points[0]) * scale / 2
                context.fillEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
                continue
            }
            var outline = CGMutablePath()
            var left: [CGPoint] = []
            var right: [CGPoint] = []
            // Catmull-Rom interpolation smooths the sampled centreline without changing
            // the saved page-space points or making the stroke dependent on display scale.
            for index in 0..<(points.count - 1) {
                let p0 = points[max(0, index - 1)]
                let p1 = points[index]
                let p2 = points[index + 1]
                let p3 = points[min(points.count - 1, index + 2)]
                for step in 0..<12 {
                    let t = CGFloat(step) / 12
                    let t2 = t * t, t3 = t2 * t
                    func curve(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> CGFloat {
                        CGFloat(0.5 * ((2 * b) + (-a + c) * Double(t) +
                            (2 * a - 5 * b + 4 * c - d) * Double(t2) +
                            (-a + 3 * b - 3 * c + d) * Double(t3)))
                    }
                    func derivative(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> CGFloat {
                        CGFloat(0.5 * ((-a + c) +
                            2 * (2 * a - 5 * b + 4 * c - d) * Double(t) +
                            3 * (-a + 3 * b - 3 * c + d) * Double(t2)))
                    }
                    let x = curve(p0.x, p1.x, p2.x, p3.x)
                    let y = curve(p0.y, p1.y, p2.y, p3.y)
                    let force = Double(t) * (p2.force - p1.force) + p1.force
                    let center = CGPoint(x: x * scale - offset.x, y: y * scale - offset.y)
                    let tangentX = derivative(p0.x, p1.x, p2.x, p3.x) * scale
                    let tangentY = derivative(p0.y, p1.y, p2.y, p3.y) * scale
                    let length = max(hypot(tangentX, tangentY), 0.001)
                    let normal = CGPoint(x: -tangentY / length, y: tangentX / length)
                    let radius = CGFloat(stroke.width * pressureScale(force, enabled: stroke.pressureSensitive)) * scale / 2
                    left.append(CGPoint(x: center.x + normal.x * radius, y: center.y + normal.y * radius))
                    right.append(CGPoint(x: center.x - normal.x * radius, y: center.y - normal.y * radius))
                }
            }
            if let last = points.last {
                let center = viewPoint(last, scale: scale, offset: offset)
                let radius = diameter(stroke, at: last) * scale / 2
                let p0 = points[max(0, points.count - 2)]
                let dx = CGFloat(last.x - p0.x) * scale, dy = CGFloat(last.y - p0.y) * scale
                let length = max(hypot(dx, dy), 0.001)
                let normal = CGPoint(x: -dy / length, y: dx / length)
                left.append(CGPoint(x: center.x + normal.x * radius, y: center.y + normal.y * radius))
                right.append(CGPoint(x: center.x - normal.x * radius, y: center.y - normal.y * radius))
            }
            if let first = left.first, !right.isEmpty {
                outline.move(to: first)
                for point in left.dropFirst() { outline.addLine(to: point) }
                for point in right.reversed() { outline.addLine(to: point) }
                outline.closeSubpath()
                context.addPath(outline)
                context.fillPath()
                let firstCenter = viewPoint(points[0], scale: scale, offset: offset)
                let firstRadius = diameter(stroke, at: points[0]) * scale / 2
                let lastCenter = viewPoint(points[points.count - 1], scale: scale, offset: offset)
                let lastRadius = diameter(stroke, at: points[points.count - 1]) * scale / 2
                context.fillEllipse(in: CGRect(x: firstCenter.x - firstRadius, y: firstCenter.y - firstRadius,
                                               width: firstRadius * 2, height: firstRadius * 2))
                context.fillEllipse(in: CGRect(x: lastCenter.x - lastRadius, y: lastCenter.y - lastRadius,
                                               width: lastRadius * 2, height: lastRadius * 2))
            }
        }
        context.restoreGState()
    }

    private static func viewPoint(_ point: VectorInkPoint, scale: CGFloat, offset: CGPoint) -> CGPoint {
        CGPoint(x: CGFloat(point.x) * scale - offset.x, y: CGFloat(point.y) * scale - offset.y)
    }

    /// A smooth, visible pressure response with a stable minimum width.
    /// The previous ±12% range was too small to perceive in normal handwriting.
    private static func pressureScale(_ force: Double, enabled: Bool) -> Double {
        guard enabled else { return 1 }
        let normalized = min(max(force, 0), 1)
        return 0.65 + 0.70 * normalized
    }

    private static func diameter(_ stroke: VectorInkStroke, at point: VectorInkPoint) -> CGFloat {
        CGFloat(stroke.width * pressureScale(point.force, enabled: stroke.pressureSensitive))
    }
}

/// Captures coalesced UIKit Pencil samples and paints the same page-space vector path that is saved.
@MainActor
final class VectorInkInputView: UIView {
    weak var canvas: UIScrollView?
    var onCommit: ((VectorInkStroke) -> Void)?
    private(set) var strokes: [VectorInkStroke] = []
    private var preset: VectorInkTool?
    private var pageID: UUID?
    private var pageSize = CGSize.zero
    private var inProgress: [VectorInkPoint] = []
    private var activePreset: VectorInkTool?
    private var activeCommit: ((VectorInkStroke) -> Void)?
    private var pendingStroke: VectorInkStroke?
    private var startedAt: TimeInterval = 0
    private var acceptsFinger = false
    private var estimatedForceIndices: [NSNumber: Int] = [:]
    var canDraw: (() -> Bool)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isMultipleTouchEnabled = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The overlay is a raster-backed UIView inside the zooming page hierarchy.
    /// Increase its backing resolution as its ancestors magnify it so ink edges
    /// don't become enlarged screen-resolution pixels while zooming.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let window else { return }
        let boundsInWindow = convert(bounds, to: window)
        let viewScale = max(boundsInWindow.width / max(bounds.width, 1),
                            boundsInWindow.height / max(bounds.height, 1))
        let targetScale = window.screen.scale * min(max(viewScale, 1), 2)
        if abs(contentScaleFactor - targetScale) > 0.05 {
            contentScaleFactor = targetScale
            layer.contentsScale = targetScale
            setNeedsDisplay()
        }
    }

    func configure(canvas: UIScrollView, canvasIsLoaded: Bool, pageID: UUID, pageSize: CGSize,
                   strokes: [VectorInkStroke], preset: VectorInkTool?, acceptsFinger: Bool) {
        self.canvas = canvas
        self.pageID = pageID
        self.pageSize = pageSize
        self.strokes = strokes
        pendingStroke = nil
        self.preset = preset
        self.acceptsFinger = acceptsFinger
        isUserInteractionEnabled = preset != nil && canvasIsLoaded
        setNeedsDisplay()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard canDraw?() ?? true else { return nil }
        if let touches = event?.allTouches, !touches.isEmpty,
           !touches.contains(where: accepts) { return nil }
        return super.hitTest(point, with: event)
    }

    func showPending(_ stroke: VectorInkStroke?) {
        pendingStroke = stroke
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let canvas else { return }
        VectorInkRenderer.draw(strokes + (pendingStroke.map { [$0] } ?? []), in: context, scale: canvas.zoomScale, offset: canvas.contentOffset)
        if let preset, !inProgress.isEmpty {
            let kind: VectorInkStroke.Kind = preset.isHighlighter ? .highlighter : .pen
            let live = VectorInkStroke(kind: kind, color: preset.color, width: preset.width,
                                       pressureSensitive: preset.pressureSensitive, points: inProgress)
            VectorInkRenderer.draw([live], in: context, scale: canvas.zoomScale, offset: canvas.contentOffset)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard inProgress.isEmpty, canDraw?() ?? true, let touch = touches.first, accepts(touch) else { return }
        startedAt = touch.timestamp
        estimatedForceIndices.removeAll(keepingCapacity: true)
        activePreset = preset
        activeCommit = onCommit
        inProgress.removeAll(keepingCapacity: true)
        append(touch, event: event)
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, !inProgress.isEmpty else { return }
        append(touch, event: event)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, !inProgress.isEmpty else { return }
        append(touch, event: event)
        defer {
            inProgress.removeAll(keepingCapacity: true)
            estimatedForceIndices.removeAll(keepingCapacity: true)
            activePreset = nil
            activeCommit = nil
            setNeedsDisplay()
        }
        guard let preset = activePreset, pageID != nil else { return }
        let kind: VectorInkStroke.Kind = preset.isHighlighter ? .highlighter : .pen
        let stroke = VectorInkStroke(kind: kind, color: preset.color, width: preset.width,
                                     pressureSensitive: preset.pressureSensitive, points: inProgress)
        if !stroke.points.isEmpty {
            strokes.append(stroke)
            activeCommit?(stroke)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            inProgress.removeAll(keepingCapacity: true)
            activePreset = nil
            activeCommit = nil
            setNeedsDisplay()
        }
        guard let touch = touches.first, !inProgress.isEmpty,
              let preset = activePreset, pageID != nil else { return }
        append(touch, event: event)
        guard !inProgress.isEmpty else { return }
        let kind: VectorInkStroke.Kind = preset.isHighlighter ? .highlighter : .pen
        let stroke = VectorInkStroke(kind: kind, color: preset.color, width: preset.width,
                                     pressureSensitive: preset.pressureSensitive, points: inProgress)
        strokes.append(stroke)
        activeCommit?(stroke)
    }

    private func accepts(_ touch: UITouch) -> Bool {
        touch.type == .pencil || (acceptsFinger && touch.type == .direct)
    }

    private func append(_ touch: UITouch, event: UIEvent?) {
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            let local = sample.location(in: self)
            let scale = max(canvas?.zoomScale ?? 1, 0.001)
            let offset = canvas?.contentOffset ?? .zero
            let point = CGPoint(x: (local.x + offset.x) / scale, y: (local.y + offset.y) / scale)
            guard CGRect(origin: .zero, size: pageSize).insetBy(dx: -1, dy: -1).contains(point) else { continue }
            let rawForce = sample.maximumPossibleForce > 0 ? sample.force / sample.maximumPossibleForce : 0.5
            let force = min(max(Double(rawForce), 0.08), 1)
            let elapsed = max(0, sample.timestamp - startedAt)
            let next = VectorInkPoint(x: Double(point.x), y: Double(point.y), force: force, time: elapsed)
            if let last = inProgress.last, hypot(last.x - next.x, last.y - next.y) < 0.08 { continue }
            let sampleIndex = inProgress.count
            inProgress.append(next)
            if sample.estimatedPropertiesExpectingUpdates.contains(.force),
               let updateIndex = sample.estimationUpdateIndex {
                estimatedForceIndices[updateIndex] = sampleIndex
            }
        }
    }

    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        var changed = false
        for touch in touches {
            guard let updateIndex = touch.estimationUpdateIndex,
                  let sampleIndex = estimatedForceIndices[updateIndex],
                  inProgress.indices.contains(sampleIndex),
                  !touch.estimatedPropertiesExpectingUpdates.contains(.force) else { continue }
            let normalized = touch.maximumPossibleForce > 0
                ? touch.force / touch.maximumPossibleForce : 0.5
            inProgress[sampleIndex].force = min(max(Double(normalized), 0.08), 1)
            estimatedForceIndices.removeValue(forKey: updateIndex)
            changed = true
        }
        if changed { setNeedsDisplay() }
    }
}

extension NotebookPage {
    var vectorInkStrokes: [VectorInkStroke] {
        get { VectorInkStroke.decode(extra["vectorInk"]?.stringValue) }
        set { extra["vectorInk"] = VectorInkStroke.encode(newValue).map(JSONValue.string) }
    }
}
