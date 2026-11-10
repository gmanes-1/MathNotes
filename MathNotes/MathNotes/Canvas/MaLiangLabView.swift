import SwiftUI
import UIKit

/// An isolated MaLiang notebook workspace. Strokes here never enter notebook documents.
@MainActor
private final class MaLiangSurfaceHandle: ObservableObject {
    weak var page: MaLiangZoomableNotebookPage?

    func clear() { page?.surface.clear() }
    func undo() { page?.surface.undo() }
    func redo() { page?.surface.redo() }
    func zoomIn() { page?.changeZoom(by: 1.2) }
    func zoomOut() { page?.changeZoom(by: 1 / 1.2) }
    func fitPage() { page?.fitPage() }
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
        handle.page = page
        return page
    }

    func updateUIView(_ page: MaLiangZoomableNotebookPage, context: Context) {
        page.surface.configure(width: width, color: color, pressureSensitivity: pressureSensitivity)
        handle.page = page
    }
}

/// A single notebook sheet. Apple Pencil draws; finger gestures pan and pinch-zoom.
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
        scrollView.bouncesZoom = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = false
        // A finger can pan the page, while Pencil touches remain available to MaLiang.
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
        guard !didSetInitialZoom, bounds.width > 0, bounds.height > 0 else { return }
        scrollView.contentSize = pageSize
        let fit = min(bounds.width / pageSize.width, bounds.height / pageSize.height)
        scrollView.minimumZoomScale = fit
        scrollView.maximumZoomScale = fit * 5
        scrollView.zoomScale = fit
        didSetInitialZoom = true
        centerPageIfNeeded()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { surface }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPageIfNeeded() }

    func changeZoom(by factor: CGFloat) {
        guard didSetInitialZoom else { return }
        let target = min(max(scrollView.zoomScale * factor, scrollView.minimumZoomScale),
                         scrollView.maximumZoomScale)
        scrollView.setZoomScale(target, animated: true)
    }

    func fitPage() {
        guard didSetInitialZoom else { return }
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
    }

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
    @StateObject private var pageHandle = MaLiangSurfaceHandle()
    @State private var width: Double = 2.7
    @State private var pressureSensitivity: Double = 0.08
    @State private var inkColor = Color.black
    @State private var usesPressure = true
    @State private var showingPenOptions = false

    private var uiColor: UIColor { UIColor(inkColor) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                MaLiangSurface(
                    handle: pageHandle,
                    width: CGFloat(width),
                    color: uiColor,
                    pressureSensitivity: usesPressure ? CGFloat(pressureSensitivity) : 0
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                VStack {
                    Spacer()
                    HStack(spacing: 22) {
                        toolButton("Undo", systemImage: "arrow.uturn.backward") { pageHandle.undo() }
                        toolButton("Redo", systemImage: "arrow.uturn.forward") { pageHandle.redo() }
                        Spacer()
                        toolButton("Clear", systemImage: "trash") { pageHandle.clear() }
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 18)
            }
            .navigationTitle("MaLiang Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: onClose)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { pageHandle.zoomOut() } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .accessibilityLabel("Zoom out")

                    Button { pageHandle.fitPage() } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel("Fit page")

                    Button { pageHandle.zoomIn() } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .accessibilityLabel("Zoom in")

                    Button {
                        showingPenOptions = true
                    } label: {
                        Image(systemName: "pencil.tip.crop.circle")
                    }
                    .accessibilityLabel("Pen options")
                    .popover(isPresented: $showingPenOptions, arrowEdge: .top) {
                        penOptions
                            .frame(width: 310)
                            .padding(16)
                    }
                }
            }
        }
        .tint(.accentColor)
    }

    private var penOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pen options").font(.headline)

            Picker("Pen", selection: $usesPressure) {
                Text("Pressure pen").tag(true)
                Text("Fineliner").tag(false)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Pen width")
                    Spacer()
                    Text(width.formatted(.number.precision(.fractionLength(1))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $width, in: 0.1...8, step: 0.1)
            }

            if usesPressure {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Pressure response")
                        Spacer()
                        Text(pressureSensitivity.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $pressureSensitivity, in: 0...1, step: 0.01)
                }
            }

            ColorPicker("Ink colour", selection: $inkColor, supportsOpacity: false)
        }
    }

    private func toolButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}
