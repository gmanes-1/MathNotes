import SwiftUI
import UIKit

/// A throwaway comparison room for calibrating MaLiang before it is considered for notebook ink.
/// Nothing drawn here is written into a notebook or the app's PKDrawing documents.
@MainActor
private final class MaLiangSurfaceHandle: ObservableObject {
    weak var surface: MaLiangFinelinerPrototypeView?

    func clear() { surface?.clear() }
    func undo() { surface?.undo() }
    func redo() { surface?.redo() }
}

private struct MaLiangSurface: UIViewRepresentable {
    @ObservedObject var handle: MaLiangSurfaceHandle
    let width: CGFloat
    let color: UIColor
    let pressureSensitivity: CGFloat

    func makeUIView(context: Context) -> MaLiangZoomableNotebookPage {
        let page = MaLiangZoomableNotebookPage(
            width: width,
            color: color,
            pressureSensitivity: pressureSensitivity
        )
        handle.surface = page.surface
        return page
    }

    func updateUIView(_ page: MaLiangZoomableNotebookPage, context: Context) {
        page.surface.configure(width: width, color: color, pressureSensitivity: pressureSensitivity)
        handle.surface = page.surface
    }
}

/// A real, high-resolution notebook sheet hosted by a native zooming scroll view.
/// Pencil input is left to MaLiang; finger gestures pan and pinch-zoom the sheet.
@MainActor
private final class MaLiangZoomableNotebookPage: UIView, UIScrollViewDelegate {
    private let pageSize = CGSize(width: 900, height: 1200)
    let surface: MaLiangFinelinerPrototypeView
    private let scrollView = UIScrollView()
    private var didSetInitialZoom = false

    init(width: CGFloat, color: UIColor, pressureSensitivity: CGFloat) {
        surface = MaLiangFinelinerPrototypeView(
            frame: CGRect(origin: .zero, size: CGSize(width: 900, height: 1200)),
            width: width,
            color: color,
            pressureSensitivity: pressureSensitivity
        )
        super.init(frame: .zero)
        backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.minimumZoomScale = 0.25
        scrollView.maximumZoomScale = 2.5
        scrollView.bouncesZoom = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = false
        // Keep Pencil strokes out of the scroll view's one-finger pan recognizer.
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        surface.frame = CGRect(origin: .zero, size: pageSize)
        scrollView.addSubview(surface)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !didSetInitialZoom, bounds.width > 0, bounds.height > 0 {
            scrollView.contentSize = pageSize
            let fit = min(bounds.width / pageSize.width, bounds.height / pageSize.height)
            scrollView.minimumZoomScale = fit
            scrollView.maximumZoomScale = fit * 5
            scrollView.zoomScale = fit
            didSetInitialZoom = true
            centerPageIfNeeded()
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { surface }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPageIfNeeded() }

    private func centerPageIfNeeded() {
        let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
        let vertical = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(
            top: vertical, left: horizontal, bottom: vertical, right: horizontal
        )
    }
}

#if DEBUG
struct MaLiangLabHost: View {
    @State private var showingLab = true

    var body: some View {
        if showingLab {
            MaLiangLabView { showingLab = false }
        } else {
            MathNotesRoot()
        }
    }
}
#endif

private struct MaLiangLabView: View {
    let onClose: () -> Void
    @StateObject private var fineliner = MaLiangSurfaceHandle()
    @StateObject private var pressurePen = MaLiangSurfaceHandle()
    @State private var width: Double = 2.7
    @State private var pressureSensitivity: Double = 0.08
    @State private var inkColor = Color.black

    private var uiColor: UIColor { UIColor(inkColor) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MaLiang pen test")
                            .font(.title2.bold())
                        Text("Draw with Apple Pencil. These are isolated test surfaces: strokes do not enter or change any notebook.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Reference width")
                            Spacer()
                            Text(width.formatted(.number.precision(.fractionLength(1))))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $width, in: 0.1...8, step: 0.1)
                        HStack {
                            Text("Pressure response")
                            Spacer()
                            Text(pressureSensitivity.formatted(.number.precision(.fractionLength(2))))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $pressureSensitivity, in: 0...1, step: 0.01)
                        ColorPicker("Ink colour", selection: $inkColor, supportsOpacity: false)
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                    surfaceCard(
                        title: "Fineliner",
                        subtitle: "Constant-width MaLiang brush",
                        handle: fineliner,
                        sensitivity: 0
                    )

                    surfaceCard(
                        title: "Pressure Pen",
                        subtitle: "MaLiang pressure response: \(pressureSensitivity.formatted(.number.precision(.fractionLength(2))))",
                        handle: pressurePen,
                        sensitivity: CGFloat(pressureSensitivity)
                    )

                    Text("Both surfaces use the same reference width and colour. Change the sliders, then draw new strokes to compare. Undo and clear are independent for each surface.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                    .padding(10)
                }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("MaLiang Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: onClose)
                }
            }
        }
        .tint(.accentColor)
    }

    private func surfaceCard(
        title: String,
        subtitle: String,
        handle: MaLiangSurfaceHandle,
        sensitivity: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            MaLiangSurface(
                handle: handle,
                width: CGFloat(width),
                color: uiColor,
                pressureSensitivity: sensitivity
            )
            .frame(height: 420)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }

            HStack(spacing: 18) {
                Button { handle.undo() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                Button { handle.redo() } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                Spacer()
                Button(role: .destructive) { handle.clear() } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
