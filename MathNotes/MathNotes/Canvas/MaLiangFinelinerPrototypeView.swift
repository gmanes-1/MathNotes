import UIKit
import MaLiang

/// Isolated Apple Pencil Fineliner test surface. It is deliberately not wired into
/// PageStack: MathNotes continues to use PencilKit for all production notebook ink.
@MainActor
public final class MaLiangFinelinerPrototypeView: UIView {
    public let canvas: Canvas
    private var fineliner: Brush?

    public init(
        frame: CGRect = .zero,
        width: CGFloat = 0.65,
        color: UIColor = .label,
        pressureSensitivity: CGFloat = 0.12
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
        configure(width: 0.65, color: .label, pressureSensitivity: 0.12)
    }

    private func installCanvas() {
        backgroundColor = .clear
        clipsToBounds = true
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

    /// MaLiang computes width as pointSize * pow(force, forceSensitive).
    /// A low exponent keeps pressure changes deliberately restrained.
    public func configure(
        width: CGFloat,
        color: UIColor,
        pressureSensitivity: CGFloat
    ) {
        let brush = canvas.defaultBrush!
        brush.pointSize = max(0.2, width)
        brush.pointStep = 0.6
        brush.opacity = 0.65
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
