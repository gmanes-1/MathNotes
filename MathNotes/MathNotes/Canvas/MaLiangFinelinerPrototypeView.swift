import UIKit
import MaLiang

/// MaLiang Fineliner surface. The current notebook still persists its production ink as PKDrawing.
@MainActor
public final class MaLiangFinelinerPrototypeView: UIView {
    public let canvas: Canvas
    private var fineliner: Brush?

    public init(
        frame: CGRect = .zero,
        width: CGFloat,
        color: UIColor = .label,
        pressureSensitivity: CGFloat = 0.08
    ) {
        canvas = Canvas(frame: .zero)
        super.init(frame: frame)
        installCanvas()
        configure(width: width, color: color, pressureSensitivity: pressureSensitivity)
    }

    public required init?(coder: NSCoder) {
        canvas = Canvas(frame: .zero)
        super.init(coder: coder)
        installCanvas()
        configure(width: 0.65, color: .label, pressureSensitivity: 0.08)
    }

    private func installCanvas() {
        backgroundColor = .white
        isOpaque = true
        clipsToBounds = true
        layer.cornerRadius = 3
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.16
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.backgroundColor = .clear
        canvas.isPencilMode = true
        addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Draw a subtle ruled-paper background beneath the transparent Metal canvas.
    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        UIColor.white.setFill()
        UIRectFill(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor(red: 0.78, green: 0.86, blue: 0.94, alpha: 1).cgColor)
        context.setLineWidth(1)
        stride(from: CGFloat(72), through: bounds.height, by: 42).forEach { y in
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        context.strokePath()
        context.setStrokeColor(UIColor(red: 0.92, green: 0.68, blue: 0.68, alpha: 0.9).cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: 96, y: 0))
        context.addLine(to: CGPoint(x: 96, y: bounds.height))
        context.strokePath()
    }

    /// Convert the lab's selected reference width into a clearly visible MaLiang point size.
    /// The previous 3% factor made a 2.7-point selection only 0.081 points wide.
    public func configure(
        width: CGFloat,
        color: UIColor,
        pressureSensitivity: CGFloat
    ) {
        let brush = canvas.defaultBrush!
        brush.pointSize = max(0, width) * 0.3
        brush.minimumForceRatio = 0.43
        brush.pointStep = 0.6
        brush.opacity = 0.72
        brush.forceSensitive = min(max(pressureSensitivity, 0), 1)
        brush.color = color
        brush.use()
        fineliner = brush
    }

    public func clear() { canvas.clear() }
    public func undo() { canvas.undo() }
    public func redo() { canvas.redo() }
    public func snapshot() -> UIImage? { canvas.snapshot() }

    /// Saves MaLiang's own vector document format to an empty directory.
    /// This is intentionally separate from MathNotes' PKDrawing storage.
    public func saveVectorDocument(
        to emptyDirectory: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DataExporter(canvas: canvas).save(to: emptyDirectory, result: completion)
    }
}
