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

    /// The reference width is 3% of the selected preset width. This is a first
    /// visual correction after the 12% prototype rendered roughly four times too thick.
    public func configure(
        width: CGFloat,
        color: UIColor,
        pressureSensitivity: CGFloat
    ) {
        let brush = canvas.defaultBrush!
        // Reduce the MaLiang reference width by 4x; keep pressure behaviour unchanged.
        brush.pointSize = max(0, width) * 0.03
        // Preserve the previous minimum-width proportion, now relative to this preset.
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
