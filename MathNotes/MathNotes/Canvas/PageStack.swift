import SwiftUI
import UIKit
import PencilKit
import os

private struct SharedSlide: @unchecked Sendable {
    let image: UIImage
}

struct PageStack: UIViewControllerRepresentable {
    let session: EditorSession

    func makeUIViewController(context: Context) -> PageStackController {
        let controller = PageStackController(session: session)
        session.canvas = controller
        return controller
    }

    func updateUIViewController(_ controller: PageStackController, context: Context) {}
}

/// Page frames in page points, stacked vertically and centred on the widest page. A whiteboard has no size to
/// stack: among the pages it is a card, and once opened it is laid out alone, with every other page put away.
struct PageStackLayout {
    static let margin: CGFloat = 16

    private(set) var frames: [CGRect] = []
    private(set) var size = CGSize(width: 1, height: 1)
    let solo: Int?

    init(pages: [NotebookPage] = [], solo: Int? = nil) {
        self.solo = solo.flatMap { pages.indices.contains($0) && pages[$0].isBoard ? $0 : nil }
        if let solo = self.solo {
            frames = pages.indices.map { $0 == solo ? CGRect(origin: .zero, size: Whiteboard.size) : .zero }
            size = Whiteboard.size
            return
        }
        let sheet = Self.sheetWidth(pages)
        let width = sheet + Self.margin * 2
        var y = Self.margin
        frames = pages.map { page in
            let size = page.isBoard ? CGSize(width: sheet, height: (sheet * Whiteboard.shownSize.height / Whiteboard.shownSize.width).rounded()) : page.size
            defer { y += size.height + Self.margin }
            return CGRect(x: ((width - size.width) / 2).rounded(), y: y, width: size.width, height: size.height)
        }
        size = CGSize(width: width, height: max(y, 1))
    }

    static func sheetWidth(_ pages: [NotebookPage]) -> CGFloat {
        pages.lazy.filter { !$0.isBoard }.map(\.size.width).max() ?? Whiteboard.sheet.width
    }

    func isLaidOut(_ index: Int, in pages: [NotebookPage]) -> Bool {
        guard pages.indices.contains(index), frames.indices.contains(index) else { return false }
        return solo.map { $0 == index } ?? !pages[index].isBoard
    }

    func pageIndex(atY y: CGFloat) -> Int {
        if let solo { return solo }
        guard !frames.isEmpty else { return 0 }
        var low = 0, high = frames.count - 1
        while low < high {
            let mid = (low + high) / 2
            if frames[mid].maxY + Self.margin / 2 < y { low = mid + 1 } else { high = mid }
        }
        return low
    }

    func range(from top: CGFloat, to bottom: CGFloat) -> ClosedRange<Int>? {
        if let solo { return solo...solo }
        guard !frames.isEmpty else { return nil }
        let first = pageIndex(atY: top)
        var last = first
        while last + 1 < frames.count, frames[last + 1].minY <= bottom { last += 1 }
        return first...last
    }
}

final class PageCanvasView: PKCanvasView {
    var pageID: UUID?
    var isLoaded = false
    weak var undoProxy: UndoManager?
    var strokeCount: Int?
    override var undoManager: UndoManager? { undoProxy ?? super.undoManager }

    override var accessibilityValue: String? {
        get {
            let count = strokeCount ?? drawing.strokes.count
            strokeCount = count
            return count == 0 ? String(localized: "canvas.empty", defaultValue: "Empty") : String(localized: "\(count) strokes")
        }
        set {}
    }
}

final class ResponderAnchor: UIView {
    weak var undoProxy: UndoManager?
    var onResign: (() -> Void)?
    override var canBecomeFirstResponder: Bool { true }
    override var undoManager: UndoManager? { undoProxy ?? super.undoManager }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onResign?() }
        return resigned
    }
}

private extension UIView {
    var firstResponderInside: UIView? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let found = subview.firstResponderInside { return found }
        }
        return nil
    }
}

final class FindHighlightView: UIView {
    private var marks: [CAShapeLayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ rects: [CGRect], current: CGRect?, scale: CGFloat, onDark: Bool) {
        while marks.count > rects.count { marks.removeLast().removeFromSuperlayer() }
        while marks.count < rects.count {
            let mark = CAShapeLayer()
            layer.addSublayer(mark)
            marks.append(mark)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (mark, rect) in zip(marks, rects) {
            let box = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).insetBy(dx: -3, dy: -2)
            let shown = rect == current
            mark.path = CGPath(roundedRect: box, cornerWidth: 3, cornerHeight: 3, transform: nil)
            mark.fillColor = UIColor(hex: 0xE8B023, alpha: shown ? 0.5 : 0.3).cgColor
            mark.strokeColor = shown ? UIColor(hex: onDark ? 0xF7F1E3 : 0x1B2230).cgColor : UIColor(hex: 0xB07F0E).cgColor
            mark.lineWidth = shown ? 2 : 1
        }
        CATransaction.commit()
    }
}

final class BoardCardView: UIView {
    private let picture = UIImageView()
    private let chip = UIView()
    private let label = UILabel()
    private let symbol = UIImageView(image: UIImage(systemName: "arrow.up.left.and.arrow.down.right",
                                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
    var onOpen: (() -> Void)?
    var shownKey: String?

    var image: UIImage? {
        get { picture.image }
        set { picture.image = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        picture.contentMode = .scaleAspectFill
        picture.clipsToBounds = true
        picture.frame = bounds
        picture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(picture)

        chip.backgroundColor = .board
        chip.layer.borderColor = UIColor.hairline.resolvedColor(with: traitCollection).cgColor
        chip.layer.borderWidth = 1
        chip.layer.shadowColor = UIColor(hex: 0x3A2A12).cgColor
        chip.layer.shadowOpacity = 0.16
        chip.layer.shadowRadius = 3
        chip.layer.shadowOffset = CGSize(width: 0, height: 1)
        chip.isUserInteractionEnabled = false
        label.text = String(localized: "Open Whiteboard")
        let style = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        label.font = UIFont(descriptor: style.withSymbolicTraits(.traitBold) ?? style, size: 0)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .ink
        symbol.tintColor = .ink
        let row = UIStackView(arrangedSubviews: [symbol, label])
        row.spacing = Space.x2
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(row)
        addSubview(chip)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: Space.x4),
            row.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -Space.x4),
            row.topAnchor.constraint(equalTo: chip.topAnchor, constant: Space.x2),
            row.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -Space.x2),
            chip.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            chip.centerXAnchor.constraint(equalTo: centerXAnchor),
            chip.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Space.x5),
            chip.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -Space.x4),
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open)))
        addInteraction(UIPointerInteraction())
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = String(localized: "Opens the whiteboard")
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (self: Self, _) in
            self.chip.layer.borderColor = UIColor.hairline.resolvedColor(with: self.traitCollection).cgColor
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        chip.layer.cornerRadius = Radius.plate
    }

    @objc private func open() { onOpen?() }

    override func accessibilityActivate() -> Bool {
        onOpen?()
        return true
    }
}

final class PageSlotView: UIView {
    var page: NotebookPage
    let night: Bool
    var paper: PagePaperView?
    var card: BoardCardView?
    weak var canvas: PageCanvasView?
    var findView: FindHighlightView?
    private(set) var itemViews: [UUID: PageItemView] = [:]

    func syncItems(assets: URL, scale: CGFloat, links: LinkTitles, lifted: Set<UUID>, onActivate: @escaping (UUID) -> Void) {
        let items = page.items.filter { $0.content != .unknown }
        let keep = Set(items.map(\.id))
        for (id, view) in itemViews where !keep.contains(id) {
            view.removeFromSuperview()
            itemViews[id] = nil
        }
        for item in items {
            let view = itemViews[item.id] ?? PageItemView(item: item, assets: assets)
            view.update(item, onDark: page.isDark(night: night), links: links, lifted: lifted.contains(item.id))
            view.onActivate = onActivate
            view.layout(scale: scale)
            itemViews[item.id] = view
            if item.isOverInk {
                continue
            } else if let canvas, canvas.superview === self {
                insertSubview(view, belowSubview: canvas)
            } else {
                addSubview(view)
            }
        }
        raiseTape()
    }

    func raiseTape() {
        for item in page.items.reversed() where item.isOverInk {
            guard let view = itemViews[item.id] else { continue }
            if let canvas, canvas.superview === self { insertSubview(view, aboveSubview: canvas) } else { addSubview(view) }
        }
    }

    func showLifted(_ lifted: Set<UUID>, links: LinkTitles) {
        for item in page.items where item.isOverInk {
            itemViews[item.id]?.update(item, onDark: page.isDark(night: night), links: links, lifted: lifted.contains(item.id))
        }
    }

    func layoutItems(scale: CGFloat) {
        for view in itemViews.values { view.layout(scale: scale) }
    }

    init(page: NotebookPage, night: Bool = false) {
        self.page = page
        self.night = night
        super.init(frame: .zero)
        backgroundColor = PageRenderer.paperColor(page.effectivePaperColor, night: page.turnsDark(night))
        clipsToBounds = true
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError() }
}

@MainActor
final class PageStackController: UIViewController, UIScrollViewDelegate, PKCanvasViewDelegate,
                                 InkObserver, EditorCanvasControlling, UIGestureRecognizerDelegate, UIDropInteractionDelegate, UITextViewDelegate,
                                 UIPencilInteractionDelegate, PKToolPickerObserver {
    private let session: EditorSession
    private var document: NotebookDocument { session.document }
    private let scrollView = PageScrollView()
    private let contentView = UIView()
    private let anchor = ResponderAnchor()
    private var toolPicker: PKToolPicker?
    private let toolbox: Toolbox
    private let undoProxy: CanvasUndoProxy
    private let signposter = OSSignposter(subsystem: "com.owais.MathNotes", category: "editor")

    private var layout = PageStackLayout()
    private var pages: [NotebookPage] = []
    private var fitScale: CGFloat = 1
    private var bakedScale: CGFloat = 1
    private(set) var zoom: CGFloat = 1
    private(set) var minimumZoom: CGFloat = 1
    private(set) var maximumZoom: CGFloat = 4

    private var slots: [UUID: PageSlotView] = [:]
    private var canvases: [UUID: PageCanvasView] = [:]
    private var pool: [PageCanvasView] = []
    private var canvasWindow: ClosedRange<Int>?
    private var night = false
    private var isApplyingDrawing = false
    private var isBaking = false
    private var paperLevel = 0
    private var lastBounds: CGRect = .zero
    private var isModalShowing = false
    private var keepsAnchor = false
    private var unreadWriting: [UUID: Set<Date>] = [:]
    private var typingTimer: Task<Void, Never>?
    private var lastTyped: InkTyping.Last?
    private let laser = LaserTrailView()
    private lazy var laserGesture = UILongPressGestureRecognizer(target: self, action: #selector(pointLaser))
    private(set) var isPresenting = false
    private var replay: (timeline: ReplayTimeline, time: TimeInterval)?
    private var replayPages: [UUID: ReplayInk.Page] = [:]
    private var inkLasso: InkLassoOverlay?
    private var inkSelection: InkSelection = [:]
    private var lassoMoveOrigin: CGPoint?
    private var isMovingInk = false
    private var restyleTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var pendingRestyle: InkRestyleChange?
    private var pendingRestyleStyle: ToolPreset?
    private var restyleBaseline: ToolPreset?
    private var inkMenuSuspended = false
    private var inkPasteStackPoint: CGPoint?
    private lazy var lassoPan = UIPanGestureRecognizer(target: self, action: #selector(lassoPanned))
    private lazy var pasteHold = UILongPressGestureRecognizer(target: self, action: #selector(heldForPaste))
    private var isFinding = false
    private var findRects: [UUID: [CGRect]] = [:]
    private var findCurrent: FindMatch?
    private var textOverlay: TextSelectOverlay?
    private var textAnchor: (index: Int, point: CGPoint)?
    private var textSelection: (pageID: UUID, selection: TextSelection)?
    private var textRequest = 0
    private let pdfText = PDFTextReader()
    private lazy var textPan = UIPanGestureRecognizer(target: self, action: #selector(textPanned))
    private lazy var textTap = UITapGestureRecognizer(target: self, action: #selector(textTapped))
    private var isLocked: Bool { isPresenting || replay != nil || inkLasso != nil || isFinding || textOverlay != nil }
    private var zoomWindow: ZoomWindow?
    private var zoomPanel: ZoomWindowPanel?
    private var zoomCanvas: PageCanvasView?
    private var zoomPaper: PagePaperView?
    private var zoomTarget: ZoomTargetView?
    private var zoomLevel = 1
    private var zoomDragOrigin: CGPoint?
    private var zoomAdvance: DispatchWorkItem?
    private var zoomReachedBand = false
    private var selectionView: ItemSelectionView?
    private var cropView: ItemCropView?
    private var linkTitles = LinkTitles()
    private var textView: UITextView?
    private var typing: ItemSelection?
    private var typed: TextBox?
    private var typingMarkers: TextMarkersView?
    private var keyboardOverlap: CGFloat = 0
    private var mirrored: String?
    private var fingersDraw = false
    private let strokeHold = StrokeHoldRecognizer()
    private lazy var itemTap = UITapGestureRecognizer(target: self, action: #selector(tappedPage))
    private lazy var itemHold = UILongPressGestureRecognizer(target: self, action: #selector(heldPage))
    private lazy var tapeTap = UITapGestureRecognizer(target: self, action: #selector(tappedTape))
    private var soloID: UUID? {
        didSet { if session.openBoard != soloID { session.openBoard = soloID } }
    }
    private var stackZoom: CGFloat = 1
    private var boardViews: [UUID: (center: CGPoint, zoom: CGFloat)] = [:]
    private var isSolo: Bool { layout.solo != nil }
    private var lastSafeTop: CGFloat = 0
    private var firstInkPage: UUID?
    private var firstInkReported = false
    private let openedAt = CACurrentMediaTime()
    private var openInterval: OSSignpostIntervalState?

    var onFirstInk: ((TimeInterval) -> Void)?

    private static let scrollTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                                           NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]

    init(session: EditorSession, toolbox: Toolbox = .shared) {
        self.session = session
        self.toolbox = toolbox
        undoProxy = CanvasUndoProxy(document: session.document.undoManager)
        super.init(nibName: nil, bundle: nil)
        openInterval = signposter.beginInterval("Open to first ink")
        document.inkObserver = self
        document.onStructureChange = { [weak self] in self?.pagesDidChange() }
        pages = document.pages
        linkTitles = LinkTitles(pages: pages, notebooks: session.notebookTitles)
        layout = PageStackLayout(pages: pages)
    }

    required init?(coder: NSCoder) { fatalError() }

    var liveCanvasCount: Int { canvases.count }
    var openBoardID: UUID? { soloID }
    var paperPixelCount: Int { slots.values.reduce(0) { $0 + ($1.paper?.pixelCount ?? 0) } }
    var zoomWindowRect: CGRect? { zoomWindow?.rect }
    var isPaperDrawn: Bool { slots.values.allSatisfy { $0.paper?.isDrawn ?? false } }

    func canvas(forPage index: Int) -> PageCanvasView? {
        pages.indices.contains(index) ? canvases[pages[index].id] : nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .desk
        night = PaperNight.isOn(traitCollection)
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.bouncesZoom = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.panGestureRecognizer.allowedTouchTypes = Self.scrollTouchTypes
        scrollView.scrollsToTop = true
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        anchor.undoProxy = undoProxy
        anchor.onResign = { [weak self] in DispatchQueue.main.async { self?.reclaimAnchor() } }
        anchor.frame = .zero
        view.addSubview(anchor)
        laser.frame = view.bounds
        laser.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(laser)
        laserGesture.minimumPressDuration = 0
        laserGesture.allowableMovement = .greatestFiniteMagnitude
        laserGesture.cancelsTouchesInView = false
        laserGesture.delegate = self
        laserGesture.isEnabled = false
        view.addGestureRecognizer(laserGesture)
        view.addInteraction(UIDropInteraction(delegate: self))
        view.addInteraction(UIPencilInteraction(delegate: self))
        if PencilGestures.squeezeIsScripted {
            let squeeze = UITapGestureRecognizer(target: self, action: #selector(scriptedSqueeze))
            squeeze.numberOfTouchesRequired = 2
            view.addGestureRecognizer(squeeze)
        }
        itemTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        itemHold.minimumPressDuration = 0.45
        for recognizer in [itemTap, itemHold, strokeHold, tapeTap] {
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
        }
        strokeHold.onTouchDown = { [weak self] in self?.session.onTouchDown?() }
        strokeHold.fingersDraw = { [weak self] in self?.effectivePolicy == .anyInput }
        for pan in [lassoPan, textPan] {
            pan.maximumNumberOfTouches = 1
            pan.allowedTouchTypes = Self.scrollTouchTypes + [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        }
        lassoPan.delegate = self
        scrollView.panMayBegin = { [weak self] start in
            guard let self, inkLasso != nil else { return true }
            return !isOnInkSelection(scrollView.convert(start, to: contentView))
        }
        scrollView.panGestureRecognizer.require(toFail: lassoPan)
        pasteHold.minimumPressDuration = 0.45
        pasteHold.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pasteHold.cancelsTouchesInView = false
        pasteHold.delegate = self
        scrollView.addGestureRecognizer(pasteHold)
        NotificationCenter.default.addObserver(self, selector: #selector(toolChanged), name: Toolbox.didChange, object: toolbox)
        applyDrawingPolicy(session.drawingInput.policy)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (self: Self, _) in
            self.updatePageEdges()
            self.updateNight()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: UserDefaults.didChangeNotification, object: nil)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.layoutZoomPanel()
            self.updateInsets()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(sceneDidActivate), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(secondScreenChanged), name: .mathNotesExternalDisplayChanged, object: nil)
        for name in [UIScene.willDeactivateNotification, Notification.Name.mathNotesCloseEditor] {
            NotificationCenter.default.addObserver(self, selector: #selector(finishTyping), name: name, object: nil)
        }
    }

    @objc private func sceneDidActivate() { applyDrawingPolicy(drawingPolicy) }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        keepsAnchor = true
        configureNativeToolPicker()
        nativeToolPickerDidChange()
    }

    /// PencilKit owns the drawing tools, colours, widths, eraser and ruler UI.
    private func configureNativeToolPicker() {
        guard view.window != nil else { return }
        if toolPicker == nil {
            let additionalInks: [PKToolPickerItem] = [
                PKToolPickerInkingItem(type: .fountainPen, color: nil, width: nil, identifier: "com.mathnotes.fountainPen"),
                PKToolPickerInkingItem(type: .monoline, color: nil, width: nil, identifier: "com.mathnotes.monoline"),
                PKToolPickerInkingItem(type: .crayon, color: nil, width: nil, identifier: "com.mathnotes.crayon"),
                PKToolPickerInkingItem(type: .watercolor, color: nil, width: nil, identifier: "com.mathnotes.watercolor")
            ]
            if #available(iOS 26.0, *) {
                additionalInks.append(PKToolPickerInkingItem(type: .reed, color: nil, width: nil, identifier: "com.mathnotes.reed"))
            }
            let additionalTypes: [PKInkingTool.InkType] = [.fountainPen, .monoline, .crayon, .watercolor]
            let standardItems = PKToolPicker.defaultToolItems.filter { item in
                guard let ink = item.tool as? PKInkingTool else { return true }
                return !additionalTypes.contains(ink.inkType)
            }
            let picker = PKToolPicker(toolItems: standardItems + additionalInks)
            picker.stateAutosaveName = "com.mathnotes.nativeToolPicker"
            picker.selectedTool = toolbox.tool
            picker.isRulerActive = toolbox.isRulerActive
            picker.addObserver(self)
            toolPicker = picker
        }
        guard let picker = toolPicker else { return }
        if !sameTool(picker.selectedTool, toolbox.tool) { picker.selectedTool = toolbox.tool }
        if picker.isRulerActive != toolbox.isRulerActive { picker.isRulerActive = toolbox.isRulerActive }
        if !anchor.isFirstResponder { anchor.becomeFirstResponder() }
        picker.setVisible(session.showsNativeTools || session.mode == .selecting, forFirstResponder: anchor)
    }

    func toolPickerSelectedToolDidChange(_ toolPicker: PKToolPicker) {
        guard self.toolPicker === toolPicker else { return }
        toolbox.adoptNativeTool(toolPicker.selectedTool)
    }

    func toolPickerIsRulerActiveDidChange(_ toolPicker: PKToolPicker) {
        guard self.toolPicker === toolPicker else { return }
        toolbox.isRulerActive = toolPicker.isRulerActive
    }

    private func reclaimAnchor() {
        guard keepsAnchor, textView == nil, !isModalShowing, !anchor.isFirstResponder, let window = view.window else { return }
        var presenter = window.rootViewController
        while let presented = presenter?.presentedViewController {
            if presented.isFirstResponder { return }
            presenter = presented
        }
        if window.firstResponderInside != nil { return }
        anchor.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keepsAnchor = false
        endTextEditing()
        typingTimer?.cancel()
        session.dish = nil
        ExternalDisplay.shared.end(for: self)
        if let toolPicker {
            toolPicker.setVisible(false, forFirstResponder: anchor)
            toolPicker.removeObserver(self)
            self.toolPicker = nil
        }
        anchor.resignFirstResponder()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let top = view.safeAreaInsets.top
        guard lastBounds != .zero, top != lastSafeTop else { return }
        lastSafeTop = top
        if isPresenting {
            present(page: pendingPage ?? currentPage)
            return
        }
        let wasAtTop = scrollView.contentOffset.y <= -scrollView.contentInset.top + 1
        updateInsets()
        let y = wasAtTop ? -scrollView.contentInset.top : scrollView.contentOffset.y
        scrollView.contentOffset = clamped(CGPoint(x: scrollView.contentOffset.x, y: y))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        defer { if inkLasso != nil { publishInkSelection() } }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0, bounds.size != lastBounds.size else { return }
        let isFirst = lastBounds == .zero
        let page = isFirst ? session.currentPage : isPresenting || replay != nil ? pendingPage ?? session.currentPage : currentPage
        let middle = isFirst || !isSolo ? nil : boardMiddle(of: lastBounds.size)
        let keep: CGPoint? = isFirst || isSolo || isPresenting || replay != nil || effectiveScale <= 0 ? nil
            : CGPoint(x: scrollView.contentOffset.x / effectiveScale, y: scrollView.contentOffset.y / effectiveScale)
        let wasAtTop = scrollView.contentOffset.y <= -scrollView.contentInset.top + 1
        lastBounds = bounds
        if isFirst {
            firstInkPage = pages.indices.contains(page) ? pages[page].id : nil
            lastSafeTop = view.safeAreaInsets.top
            if pages.indices.contains(page), pages[page].isBoard {
                soloID = pages[page].id
                layout = PageStackLayout(pages: pages, solo: page)
            }
        }
        measure()
        layoutZoomPanel()
        bake(zoom: zoom)
        if let middle {
            center(on: middle)
        } else if isSolo {
            placeBoard()
        } else if let keep {
            let inset = scrollView.contentInset
            scrollView.contentOffset = clamped(CGPoint(x: inset.left > 0 ? -inset.left : keep.x * bakedScale,
                                                       y: wasAtTop ? -inset.top : keep.y * bakedScale))
        } else {
            scrollToPage(page, animated: false)
        }
        updateWindow(force: true)
        if isPresenting { present(page: page) }
        resizeZoomWindow()
    }

    override var keyCommands: [UIKeyCommand]? {
        guard !isModalShowing else { return [] }
        guard textView == nil else { return [UIKeyCommand(title: String(localized: "Done"), action: #selector(finishTyping), input: UIKeyCommand.inputEscape)] }
        let commands = [
            UIKeyCommand(title: String(localized: "Next Page"), action: #selector(nextPage), input: UIKeyCommand.inputPageDown),
            UIKeyCommand(title: String(localized: "Previous Page"), action: #selector(previousPage), input: UIKeyCommand.inputPageUp),
            UIKeyCommand(title: String(localized: "Scroll Down"), action: #selector(lineDown), input: UIKeyCommand.inputDownArrow),
            UIKeyCommand(title: String(localized: "Scroll Up"), action: #selector(lineUp), input: UIKeyCommand.inputUpArrow),
            UIKeyCommand(title: String(localized: "Scroll Down a Screen"), action: #selector(screenDown), input: " "),
            UIKeyCommand(title: String(localized: "Scroll Up a Screen"), action: #selector(screenUp), input: " ", modifierFlags: .shift),
            UIKeyCommand(title: String(localized: "First Page"), action: #selector(firstPage), input: UIKeyCommand.inputUpArrow, modifierFlags: .command),
            UIKeyCommand(title: String(localized: "Last Page"), action: #selector(lastPage), input: UIKeyCommand.inputDownArrow, modifierFlags: .command),
            UIKeyCommand(title: String(localized: "First Page"), action: #selector(firstPage), input: UIKeyCommand.inputHome),
            UIKeyCommand(title: String(localized: "Last Page"), action: #selector(lastPage), input: UIKeyCommand.inputEnd),
            UIKeyCommand(title: isSolo ? String(localized: "Actual Size") : String(localized: "Fit Width"), action: #selector(fitWidth), input: "0", modifierFlags: .command),
            UIKeyCommand(title: isSolo ? String(localized: "Show Everything") : String(localized: "Fit Page"), action: #selector(fitWholePage), input: "9", modifierFlags: .command),
        ]
        let presenting = !isPresenting ? [] : [
            UIKeyCommand(title: String(localized: "Next Page"), action: #selector(nextPage), input: UIKeyCommand.inputRightArrow),
            UIKeyCommand(title: String(localized: "Previous Page"), action: #selector(previousPage), input: UIKeyCommand.inputLeftArrow),
        ]
        let selected = session.selection == nil ? [] : cropView != nil ? [
            UIKeyCommand(title: String(localized: "Cancel"), action: #selector(cancelCrop), input: UIKeyCommand.inputEscape),
            UIKeyCommand(title: String(localized: "Done"), action: #selector(keepCrop), input: "\r"),
        ] : [
            UIKeyCommand(title: String(localized: "Delete"), action: #selector(deleteSelectedItem), input: UIKeyCommand.inputDelete),
            UIKeyCommand(action: #selector(deleteSelectedItem), input: "\u{8}"),
            UIKeyCommand(title: String(localized: "Done"), action: #selector(clearSelection), input: UIKeyCommand.inputEscape),
        ]
        for command in commands + presenting + selected { command.wantsPriorityOverSystemBehavior = true }
        return commands + presenting + selected
    }

    @objc private func nextPage() { session.step(1) }
    @objc private func previousPage() { session.step(-1) }
    @objc private func lineDown() { scrollBy(viewportFraction: 0.12, animated: true) }
    @objc private func lineUp() { scrollBy(viewportFraction: -0.12, animated: true) }
    @objc private func screenDown() { scrollBy(viewportFraction: 0.9, animated: true) }
    @objc private func screenUp() { scrollBy(viewportFraction: -0.9, animated: true) }
    @objc private func firstPage() { session.go(to: 0) }
    @objc private func lastPage() { session.go(to: pages.count - 1) }
    @objc private func fitWidth() { fit(.width) }
    @objc private func fitWholePage() { fit(.page) }

    private var effectiveScale: CGFloat { bakedScale * scrollView.zoomScale }

    private struct SlotKey {
        let id: UUID
        let background: PageBackground
        let paperColorRaw: String
        let size: CGSize
        let day: String?

        init(_ page: NotebookPage) {
            id = page.id
            background = page.background
            paperColorRaw = page.paperColorRaw
            size = page.size
            day = page.day
        }
    }

    private func bake(zoom newZoom: CGFloat, restoringOffset restore: ((_ scale: CGFloat) -> CGPoint)? = nil) {
        zoom = min(max(newZoom, minimumZoom), maximumZoom)
        bakedScale = zoom * fitScale
        paperLevel = 0
        isBaking = true
        scrollView.zoomScale = 1
        contentView.transform = .identity
        contentView.frame = CGRect(x: 0, y: 0, width: layout.size.width * bakedScale, height: layout.size.height * bakedScale)
        scrollView.contentSize = contentView.frame.size
        scrollView.minimumZoomScale = min(1, minimumZoom / zoom)
        scrollView.maximumZoomScale = max(1, maximumZoom / zoom)
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = Self.scrollTouchTypes
        if let restore {
            updateInsets()
            var offset = restore(bakedScale)
            if scrollView.contentInset.left > 0 { offset.x = -scrollView.contentInset.left }
            scrollView.contentOffset = clamped(offset)
        }
        for (id, slot) in slots {
            guard let index = index(of: id) else { continue }
            position(slot, at: index)
            slot.paper?.fit(unit: fitScale, zoom: zoom)
            if let canvas = slot.canvas { place(canvas, in: slot, force: true) }
            slot.layoutItems(scale: bakedScale)
            showFind(in: slot)
        }
        showSelection()
        inkLasso?.scale = bakedScale
        if inkLasso != nil { publishInkSelection() }
        textOverlay?.scale = bakedScale
        layoutZoomTarget()
        updateInsets()
        isBaking = false
        if zoomWindow != nil { showZoomWindow() }
    }

    private func position(_ slot: PageSlotView, at index: Int) {
        let frame = layout.frames[index]
        slot.frame = CGRect(x: frame.minX * bakedScale, y: frame.minY * bakedScale, width: frame.width * bakedScale, height: frame.height * bakedScale)
    }

    private func updateInsets() {
        let was = scrollView.contentInset
        let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
        let vertical = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
        let slack = isPresenting ? scrollView.bounds.height / 2 : 0
        let panel = zoomPanel.map { view.bounds.maxY - $0.frame.minY } ?? 0
        let next = UIEdgeInsets(
            top: max(vertical + view.safeAreaInsets.top, slack),
            left: horizontal,
            bottom: max(vertical, toolsObscured, slack, panel, textView == nil && !isFinding ? 0 : keyboardOverlap),
            right: horizontal
        )

        guard next != was else { return }
        scrollView.contentInset = next
        let offset = scrollView.contentOffset
        let target = clamped(offset)
        if abs(target.x - offset.x) > 0.5 || abs(target.y - offset.y) > 0.5 {
            scrollView.contentOffset = target
        }
    }

    private func clamped(_ offset: CGPoint) -> CGPoint {
        let inset = scrollView.contentInset
        let minX = -inset.left, minY = -inset.top
        let maxX = max(minX, scrollView.contentSize.width + inset.right - scrollView.bounds.width)
        let maxY = max(minY, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        return CGPoint(x: min(max(offset.x, minX), maxX), y: min(max(offset.y, minY), maxY))
    }

    private func index(of id: UUID) -> Int? { pages.firstIndex { $0.id == id } }

    var currentPage: Int {
        if let solo = layout.solo { return solo }
        guard effectiveScale > 0, !pages.isEmpty else { return 0 }
        let inset = scrollView.adjustedContentInset
        let maxY = scrollView.contentSize.height + inset.bottom - scrollView.bounds.height
        if maxY > -inset.top + 1, scrollView.contentOffset.y >= maxY - 1 { return pages.count - 1 }
        return layout.pageIndex(atY: (scrollView.contentOffset.y + scrollView.adjustedContentInset.top + scrollView.bounds.height * 0.3) / effectiveScale)
    }

    func setZoom(_ newZoom: CGFloat) {
        guard !pages.isEmpty else { return }
        let page = currentPage
        if isSolo {
            let middle = boardMiddle()
            bake(zoom: newZoom)
            center(on: middle)
            return updateWindow(force: true)
        }
        bake(zoom: newZoom)
        let frame = layout.frames[page]
        scrollView.contentOffset = clamped(CGPoint(x: (frame.minX + 40) * bakedScale - scrollView.contentInset.left,
                                                   y: (frame.minY + 40) * bakedScale - scrollView.contentInset.top))
        updateWindow(force: true)
    }

    private var pageArea: CGRect {
        var area = view.bounds.inset(by: UIEdgeInsets(top: view.safeAreaInsets.top, left: 0, bottom: 0, right: 0))
        if let zoomPanel { area.size.height = max(min(area.height, zoomPanel.frame.minY - area.minY), 80) }
        return area
    }

    private var readableArea: CGRect {
        var area = pageArea
        area.size.height = max(min(area.height, view.bounds.maxY - toolsObscured - area.minY), 80)
        return area
    }

    private var toolsObscured: CGFloat {
        guard session.showsNativeTools else { return 0 }
        return max(view.safeAreaInsets.bottom, zoomPanel.map { view.bounds.maxY - $0.frame.minY } ?? 0)
    }

    func fitZoom(_ fit: PageFit, page index: Int) -> CGFloat {
        guard layout.frames.indices.contains(index), fitScale > 0 else { return 1 }
        if layout.solo == index {
            guard fit == .page else { return 1 }
            let frame = boardFrame(index), area = readableArea
            return max(min(area.width / (frame.width * fitScale), area.height / (frame.height * fitScale)), minimumZoom)
        }
        let frame = layout.frames[index], area = readableArea, margin = PageStackLayout.margin
        let width = area.width / ((frame.width + margin * 2) * fitScale)
        return fit == .width ? width : min(width, area.height / ((frame.height + margin * 2) * fitScale))
    }

    func fit(_ fit: PageFit) {
        guard !pages.isEmpty, fitScale > 0 else { return }
        let index = pendingPage.flatMap { layout.frames.indices.contains($0) ? $0 : nil } ?? currentPage, frame = layout.frames[index], area = readableArea
        if layout.solo == index {
            let shown = boardFrame(index), middle = fit == .page ? CGPoint(x: shown.midX, y: shown.midY) : boardMiddle()
            pendingPage = nil
            bake(zoom: min(fitZoom(fit, page: index), maximumZoom))
            center(on: middle, in: fit == .page ? area : nil)
            updateWindow(force: true)
            return session.pageDidChange(index)
        }
        let line = scrollView.bounds.height * 0.3
        let anchor = (scrollView.contentOffset.y + scrollView.adjustedContentInset.top + line) / effectiveScale
        let target = min(fitZoom(fit, page: index), maximumZoom)
        minimumZoom = min(minimumZoom, target)
        pendingPage = nil
        bake(zoom: target)
        let y: CGFloat = if fit == .page {
            frame.midY * bakedScale - area.midY
        } else if (frame.minY...frame.maxY).contains(anchor) {
            anchor * bakedScale - scrollView.adjustedContentInset.top - line
        } else {
            (frame.minY - PageStackLayout.margin / 2) * bakedScale - area.minY
        }
        scrollView.contentOffset = clamped(CGPoint(x: frame.midX * bakedScale - area.midX, y: y))
        if currentPage != index { pendingPage = index }
        updateWindow(force: true)
        session.pageDidChange(index)
    }

    private var pendingPage: Int?

    func scrollToPage(_ index: Int, animated: Bool = false) {
        guard layout.frames.indices.contains(index), pages.indices.contains(index) else { return }
        if pages[index].isBoard { return openBoard(index) }
        let animated = animated && !isSolo
        closeBoard()
        let y = (layout.frames[index].minY - PageStackLayout.margin / 2) * effectiveScale - scrollView.contentInset.top
        let target = clamped(CGPoint(x: scrollView.contentOffset.x, y: y))
        let moves = animated && abs(target.y - scrollView.contentOffset.y) > 0.5
        pendingPage = moves ? index : nil
        scrollView.setContentOffset(target, animated: moves)
        if !moves { updateWindow() }
    }

    func scrollBy(viewportFraction: CGFloat, animated: Bool = false) {
        let offset = scrollView.contentOffset
        let visible = scrollView.bounds.inset(by: scrollView.adjustedContentInset).height
        let target = clamped(CGPoint(x: offset.x, y: offset.y + viewportFraction * visible))
        scrollView.setContentOffset(target, animated: animated)
        if !animated { updateWindow() }
    }

    private func visibleRange() -> ClosedRange<Int>? {
        guard effectiveScale > 0 else { return nil }
        return layout.range(from: scrollView.bounds.minY / effectiveScale, to: scrollView.bounds.maxY / effectiveScale)
    }

    private func updateWindow(force: Bool = false) {
        guard isViewLoaded, !isBaking, let visible = visibleRange() else { return }
        let count = pages.count
        let window = layout.solo.map { $0...$0 } ?? max(0, visible.lowerBound - 1)...min(count - 1, visible.upperBound + 1)
        if force || window != canvasWindow {
            canvasWindow = window
            let keep = Set(pages[window].map(\.id))
            for id in Array(slots.keys) where !keep.contains(id) { removeSlot(id) }
            for index in window {
                let page = pages[index]
                let slot = slots[page.id] ?? makeSlot(page, at: index)
                if slot.canvas == nil, slot.card == nil { attachCanvas(page, to: slot) }
            }
            document.pinInk(keep.union(zoomWindow.map { [$0.pageID] } ?? []))
            let prefetch = isSolo ? window : max(0, visible.lowerBound - 3)...min(count - 1, visible.upperBound + 3)
            document.prefetchInk(pages[prefetch].map(\.id))
        }
        let density = paperDensity()
        for index in canvasWindow ?? window {
            guard let slot = slots[pages[index].id] else { continue }
            if let canvas = slot.canvas { place(canvas, in: slot, force: force) }
            if slot.card == nil { updatePaper(in: slot, density: density) }
        }
        let page = currentPage
        if pendingPage == nil, page != session.currentPage { session.pageDidChange(page) }
        updateInkAppearance()
        dimOtherPages()
        mirrorPresentation()
    }

    private func dimOtherPages() {
        let shown = pendingPage ?? session.currentPage
        let shownID = isPresenting && pages.indices.contains(shown) ? pages[shown].id : nil
        for (id, slot) in slots {
            let alpha: CGFloat = shownID == nil || id == shownID ? 1 : 0.25
            if slot.alpha != alpha { slot.alpha = alpha }
        }
    }

    private func updateInkAppearance() {
        let index = pendingPage ?? session.currentPage
        guard pages.indices.contains(index) else { return }
        let dark = pages[index].effectivePaperColor.inkAppearance == .dark, turned = pages[index].turnsDark(night)
        if session.inkIsLight != dark { session.inkIsLight = dark }
        if session.paperIsNight != turned { session.paperIsNight = turned }
    }

    @objc private nonisolated func settingsChanged() {
        Task { @MainActor [weak self] in
            self?.updateNight()
            self?.zoomPanel?.isLeftHanded = UserDefaults.standard.bool(forKey: SettingsKey.leftHanded)
        }
    }

    private func updateNight() {
        let now = PaperNight.isOn(traitCollection)
        guard now != night else { return }
        night = now
        guard isViewLoaded else { return }
        if session.isEditingText { finishTyping() }
        if inkLasso != nil { setInkSelection([:]) }
        for (id, slot) in slots where slot.page.turnsDark(true) { removeSlot(id) }
        updateWindow(force: true)
        refreshZoomWindow()
        updateInkAppearance()
    }

    private func makeSlot(_ page: NotebookPage, at index: Int) -> PageSlotView {
        let slot = PageSlotView(page: page, night: night)
        slot.layer.borderWidth = isSolo ? 0 : 1 / max(traitCollection.displayScale, 1)
        slot.layer.borderColor = UIColor.hairline.resolvedColor(with: traitCollection).cgColor
        position(slot, at: index)
        contentView.addSubview(slot)
        if let inkLasso { contentView.bringSubviewToFront(inkLasso) }
        if let textOverlay { contentView.bringSubviewToFront(textOverlay) }
        if let zoomTarget { contentView.bringSubviewToFront(zoomTarget) }
        slots[page.id] = slot
        if page.isBoard, !isSolo {
            let card = BoardCardView(frame: slot.bounds)
            card.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            card.onOpen = { [weak self] in
                guard let self, let index = self.index(of: page.id) else { return }
                self.session.go(to: index)
            }
            slot.addSubview(card)
            slot.card = card
            nameCard(in: slot, at: index)
            drawCard(in: slot)
        } else if page.hasItems {
            syncItems(in: slot)
        }
        showFind(in: slot)
        return slot
    }

    private func removeSlot(_ id: UUID) {
        if session.selection?.pageID == id { select(nil) }
        recycleCanvas(id)
        guard let slot = slots.removeValue(forKey: id) else { return }
        slot.paper?.clear()
        slot.removeFromSuperview()
    }

    private func updatePageEdges() {
        for slot in slots.values { slot.layer.borderColor = UIColor.hairline.resolvedColor(with: traitCollection).cgColor }
    }

    private func paperDensity() -> CGFloat {
        let pinch = log2(max(scrollView.zoomScale, 0.01))
        if abs(pinch - CGFloat(paperLevel)) > 0.6 { paperLevel = Int(pinch.rounded()) }
        return zoom * max(traitCollection.displayScale, 1) * pow(2, CGFloat(paperLevel))
    }

    private func updatePaper(in slot: PageSlotView, density: CGFloat) {
        let paper = slot.paper ?? PagePaperView(page: slot.page, assets: document.package.assetsDirectory, night: night)
        if slot.paper == nil {
            slot.insertSubview(paper, at: 0)
            slot.paper = paper
        }
        paper.fit(unit: fitScale, zoom: zoom)
        let viewport = slot.convert(scrollView.bounds, from: scrollView)
        let keep = viewport.insetBy(dx: -viewport.width / 4, dy: -viewport.height / 4).intersection(slot.bounds)
        paper.show(near: keep.isNull ? .null : paper.convert(keep, from: slot), density: density)
    }

    private func makeCanvas() -> PageCanvasView {
        let canvas = PageCanvasView()
        canvas.undoProxy = undoProxy
        canvas.delegate = self
        canvas.isScrollEnabled = false
        canvas.bounces = false
        canvas.bouncesZoom = false
        canvas.pinchGestureRecognizer?.isEnabled = false
        canvas.panGestureRecognizer.isEnabled = false
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.clipsToBounds = true
        canvas.scrollsToTop = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawingPolicy = effectivePolicy
        canvas.maximumSupportedContentVersion = .latest
        canvas.isAccessibilityElement = true
        canvas.accessibilityTraits = .allowsDirectInteraction
        return canvas
    }

    private func sameTool(_ lhs: PKTool, _ rhs: PKTool) -> Bool {
        if let a = lhs as? PKInkingTool, let b = rhs as? PKInkingTool {
            return a.inkType == b.inkType && ToolPreset.bytes(of: a.color) == ToolPreset.bytes(of: b.color)
                && abs(a.width - b.width) < 0.01
        }
        if let a = lhs as? PKEraserTool, let b = rhs as? PKEraserTool {
            return a.eraserType == b.eraserType && abs(a.width - b.width) < 0.01
        }
        return lhs is PKLassoTool && rhs is PKLassoTool
    }

    private func syncTool(_ canvas: PageCanvasView) {
        let selected = toolbox.tool
        if canvas === zoomCanvas, let ink = selected as? PKInkingTool {
            // PKCanvasView records widths in its own content coordinates. The zoom window has a
            // different points-per-page-point scale from the main canvas, so compensate the tool
            // width to keep the resulting stroke the same size in the notebook.
            let scale = canvas.zoomScale / max(bakedScale, 0.001)
            // Preserve the app's explicit fine widths; do not re-clamp them to the picker range.
            canvas.tool = PKInkingTool(ink.inkType, color: ink.color, width: ink.width * scale)
        } else {
            canvas.tool = selected
        }
        canvas.isRulerActive = toolbox.isRulerActive
    }

    private func attachCanvas(_ page: NotebookPage, to slot: PageSlotView) {
        let canvas = pool.popLast() ?? makeCanvas()
        syncTool(canvas)
        canvas.pageID = page.id
        canvas.overrideUserInterfaceStyle = page.inkAppearance(night: night)
        let number = (index(of: page.id) ?? 0) + 1
        canvas.accessibilityLabel = canvasLabel(page, number: number)
        canvas.accessibilityIdentifier = "page.canvas.\(number)"
        place(canvas, in: slot, force: true)
        slot.addSubview(canvas)
        slot.canvas = canvas
        canvases[page.id] = canvas
        slot.raiseTape()
        if let selectionView, selectionView.superview === slot { slot.bringSubviewToFront(selectionView) }
        if let cropView, cropView.superview === slot { slot.bringSubviewToFront(cropView) }
        if let textView, textView.superview === slot { slot.bringSubviewToFront(textView) }
        if let findView = slot.findView { slot.bringSubviewToFront(findView) }
        if let ink = document.loadedInk(page.id) {
            show(ink, in: canvas)
        } else {
            setDrawingEnabled(false, canvas)
            let id = page.id
            Task { [weak self] in
                guard let self else { return }
                let ink = await document.ink(id)
                if canvas.pageID == id { show(ink, in: canvas) }
            }
        }
    }

    private func show(_ ink: PKDrawing, in canvas: PageCanvasView) {
        isApplyingDrawing = true
        canvas.drawing = replayed(ink, on: canvas.pageID)
        canvas.strokeCount = nil
        isApplyingDrawing = false
        canvas.isLoaded = true
        setDrawingEnabled(!document.isReadOnly && !isLocked, canvas)
        if !firstInkReported, canvas.pageID == firstInkPage, ink.strokes.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.reportFirstInk() }
        }
    }

    private func setDrawingEnabled(_ enabled: Bool, _ canvas: PageCanvasView) {
        // PencilKit owns the complete touch lifecycle so pressure, undo, persistence and zoom
        // all use the same native stroke pipeline.
        canvas.drawingGestureRecognizer.isEnabled = enabled
    }


    private func recycleCanvas(_ id: UUID) {
        guard let canvas = canvases.removeValue(forKey: id) else { return }
        if canvas.isFirstResponder { anchor.becomeFirstResponder() }
        canvas.removeFromSuperview()
        canvas.pageID = nil
        replayPages[id] = nil
        canvas.isLoaded = false
        canvas.overrideUserInterfaceStyle = .light
        slots[id]?.canvas = nil
        isApplyingDrawing = true
        canvas.drawing = PKDrawing()
        isApplyingDrawing = false
        if pool.count < 3 { pool.append(canvas) }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        pool.removeAll()
        document.releaseCleanInk()
    }

    private static let canvasOverscan: CGFloat = 0.25

    private func place(_ canvas: PageCanvasView, in slot: PageSlotView, force: Bool = false) {
        let s = bakedScale
        let rescaled = abs(canvas.zoomScale - s) > 0.0001
        if rescaled {
            canvas.minimumZoomScale = min(canvas.minimumZoomScale, s)
            canvas.maximumZoomScale = max(canvas.maximumZoomScale, s)
            canvas.zoomScale = s
            canvas.minimumZoomScale = s
            canvas.maximumZoomScale = s
        }
        let full = slot.bounds
        let viewport = slot.convert(scrollView.bounds, from: scrollView)
        let size = CGSize(width: slot.page.size.width * s, height: slot.page.size.height * s)
        let needed = viewport.intersection(full)
        if !force, !rescaled, canvas.contentSize == size, canvas.frame.width > 0,
           needed.isNull || canvas.frame.insetBy(dx: -0.5, dy: -0.5).contains(needed) {
            return
        }
        let pixel = 1 / max(traitCollection.displayScale, 1)
        let grown = viewport.insetBy(dx: -viewport.width * Self.canvasOverscan, dy: -viewport.height * Self.canvasOverscan)
        let width = min(full.width, (grown.width / pixel).rounded(.up) * pixel)
        let height = min(full.height, (grown.height / pixel).rounded(.up) * pixel)
        let x = min(max((grown.minX / pixel).rounded(.down) * pixel, 0), full.width - width)
        let y = min(max((grown.minY / pixel).rounded(.down) * pixel, 0), full.height - height)
        let target = CGRect(x: x, y: y, width: width, height: height)
        if canvas.frame != target { canvas.frame = target }
        if canvas.contentSize != size { canvas.contentSize = size }
        if canvas.contentOffset != target.origin { canvas.contentOffset = target.origin }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingDrawing, let canvas = canvasView as? PageCanvasView, canvas.isLoaded, let id = canvas.pageID else { return }
        canvas.strokeCount = nil
        let before = document.loadedInk(id)
        let rest = canvas === zoomCanvas ? nil : strokeHold.takeHold()
        if pencilGesture(on: canvas, pageID: id, before: before, rest: rest) {
            if !unreadWriting.isEmpty { readWritingAfterARest() }
            return
        }
        if let before, canvas.drawing.strokes.count == before.strokes.count + 1,
           let drawn = canvas.drawing.strokes.last,
           let tool = canvas.tool as? PKInkingTool, canvas !== zoomCanvas {
            // Learn from the exact tool PencilKit received. Never scale the stroke transform:
            // that changes the path's length as well as its thickness.
            InkCalibration.learn(from: drawn, writtenWith: tool)
        }

        document.canvasDidChangeInk(id, to: canvas.drawing)
        mirrorInk(from: canvas, pageID: id)
        let typing = noteWriting(on: canvas, pageID: id, before: before)
        let straighten = { [weak self, weak canvas] in
            guard let self, let canvas, canvas !== zoomCanvas, !typing else { return }
            straightenLastStroke(on: canvas, pageID: id, before: before, rest: rest)
        }
        let readingText = snapHighlighter(on: canvas, pageID: id, before: before, otherwise: straighten)
        if canvas === zoomCanvas { return zoomStrokeEnded(canvas, before: before) }
        if !readingText { straighten() }
    }

    private func noteWriting(on canvas: PageCanvasView, pageID: UUID, before: PKDrawing?) -> Bool {
        guard toolbox.typesHandwriting, PencilGestures.writes(canvas.tool), !canvas.isRulerActive, !document.isReadOnly,
              let before, canvas.drawing.strokes.count == before.strokes.count + 1, let drawn = canvas.drawing.strokes.last else { return false }
        unreadWriting[pageID, default: []].insert(drawn.path.creationDate)
        readWritingAfterARest()
        return true
    }

    private func readWritingAfterARest() {
        typingTimer?.cancel()
        typingTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(InkTyping.lookAhead))
            guard !Task.isCancelled else { return }
            self?.typeUnreadWriting(after: InkTyping.pause - InkTyping.lookAhead)
        }
    }

    private func typeUnreadWriting(after rest: TimeInterval = 0) {
        typingTimer?.cancel()
        typingTimer = nil
        var pieces: [(pageID: UUID, stamps: Set<Date>, ink: PKDrawing)] = []
        for (pageID, stamps) in unreadWriting {
            let written = document.loadedInk(pageID)?.strokes.filter { stamps.contains($0.path.creationDate) } ?? []
            if written.isEmpty { unreadWriting[pageID] = nil } else { pieces.append((pageID, stamps, PKDrawing(strokes: written))) }
        }
        guard !pieces.isEmpty else { return }
        typingTimer = Task { [weak self] in
            let texts = await InkTyping.read(pieces.map(\.ink), handingBackAfter: rest) { InkText.recognize([$0]) }
            guard !Task.isCancelled, let self else { return }
            for (piece, text) in zip(pieces, texts) { setType(text, inPlaceOf: piece.stamps, onPage: piece.pageID) }
        }
    }

    private func setType(_ text: String?, inPlaceOf stamps: Set<Date>, onPage pageID: UUID) {
        unreadWriting[pageID]?.subtract(stamps)
        if unreadWriting[pageID]?.isEmpty == true { unreadWriting[pageID] = nil }
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !document.isReadOnly, let ink = document.loadedInk(pageID), let page = pages.first(where: { $0.id == pageID }) else { return }
        let written = ink.strokes.filter { stamps.contains($0.path.creationDate) }
        guard !written.isEmpty else { return }
        let bounds = PKDrawing(strokes: written).bounds, action = String(localized: "Handwriting to Text")
        guard document.updateInk([pageID: PKDrawing(strokes: ink.strokes.filter { !stamps.contains($0.path.creationDate) })], actionName: action) else { return }
        let lineHeight = bounds.height / CGFloat(max(trimmed.split(separator: "\n").count, 1))
        var typed = InkTyping.Last(pageID: pageID, itemID: UUID(), written: bounds, lineHeight: lineHeight)
        document.updateItems(onPage: pageID, actionName: action) { items in
            if let last = lastTyped, last.pageID == pageID, let index = items.firstIndex(where: { $0.id == last.itemID }),
               let join = InkTyping.join(bounds, after: last.written, lineHeight: last.lineHeight),
               let grown = InkTyping.extended(items[index], with: trimmed, join, pageSize: page.size) {
                items[index] = grown
                typed = InkTyping.Last(pageID: pageID, itemID: grown.id, written: last.written.union(bounds), lineHeight: last.lineHeight)
            } else {
                var item = InkText.box(for: trimmed, replacing: bounds, pageSize: page.size)
                if case .text(var box) = item.content, let colour = written.first?.ink.color {
                    box.tint = InkTyping.tint(for: colour)
                    item.content = .text(box)
                }
                items.append(item)
                typed.itemID = item.id
            }
        }
        lastTyped = typed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AccessibilityNotification.Announcement(String(localized: "Set as text: \(trimmed)")).post()
    }

    private func pencilGesture(on canvas: PageCanvasView, pageID: UUID, before: PKDrawing?, rest: TimeInterval?) -> Bool {
        guard let before, !before.strokes.isEmpty, canvas.drawing.strokes.count == before.strokes.count + 1, let drawn = canvas.drawing.strokes.last,
              PencilGestures.writes(canvas.tool), !canvas.isRulerActive, !document.isReadOnly else { return false }
        if let rest, rest >= ShapeSnap.holdDuration, PencilGestures.circleSelects, let frame = stackFrames[pageID],
           let outline = PencilGestures.outline(of: drawn, roundInkIn: before) {
            document.replaceInk(pageID, with: before)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let stack = outline.map { CGPoint(x: $0.x + frame.minX, y: $0.y + frame.minY) }
            DispatchQueue.main.async { [weak self] in self?.session.selectInk(inside: stack) }
            return true
        }
        guard PencilGestures.scribbleErases, let erased = PencilGestures.erasing(drawn, from: before) else { return false }
        document.canvasDidChangeInk(pageID, to: erased.drawing)
        document.undoManager.setActionName(String(localized: "Scribble Erase"))
        isApplyingDrawing = true
        canvas.drawing = erased.drawing
        isApplyingDrawing = false
        mirrorInk(from: canvas, pageID: pageID)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AccessibilityNotification.Announcement(String(localized: "\(erased.count) strokes erased")).post()
        return true
    }

    private func mirrorInk(from canvas: PageCanvasView, pageID: UUID) {
        let other = canvas === zoomCanvas ? canvases[pageID] : zoomWindow?.pageID == pageID ? zoomCanvas : nil
        guard let other, other.isLoaded else { return }
        isApplyingDrawing = true
        other.drawing = canvas.drawing
        other.strokeCount = nil
        isApplyingDrawing = false
    }

    private func straightenLastStroke(on canvas: PageCanvasView, pageID: UUID, before: PKDrawing?, rest: TimeInterval?) {
        guard let rest, rest >= ShapeSnap.holdDuration, ShapeSnap.isEnabled, canvas.tool is PKInkingTool, !canvas.isRulerActive,
              let before, canvas.drawing.strokes.count == before.strokes.count + 1, let drawn = canvas.drawing.strokes.last,
              let snapped = ShapeSnap.snapped(drawn) else { return }
        replaceLastStroke(drawn, with: snapped.stroke, on: canvas, pageID: pageID, actionName: String(localized: "Straighten Shape"),
                          announcement: String(localized: "Straightened into a \(snapped.shape.displayName)"))
    }

    private func snapHighlighter(on canvas: PageCanvasView, pageID: UUID, before: PKDrawing?, otherwise: @escaping () -> Void) -> Bool {
        guard PDFText.snapsHighlighter, (canvas.tool as? PKInkingTool)?.inkType == .marker, !canvas.isRulerActive,
              let index = index(of: pageID), case .pdf(let file, let pdfIndex) = pages[index].background,
              let before, canvas.drawing.strokes.count == before.strokes.count + 1, let drawn = canvas.drawing.strokes.last else { return false }
        let points = PencilGestures.points(of: drawn)
        guard PDFText.runsAlongALine(points) else { return false }
        let url = document.package.assetURL(file), size = pages[index].size
        Task { [weak self, weak canvas] in
            guard let self else { return }
            let line = await pdfText.line(under: points, file: url, index: pdfIndex, pageSize: size)
            guard let canvas, let line else { return otherwise() }
            replaceLastStroke(drawn, with: TextHighlight.stroke(over: line, ink: drawn.ink, replacing: drawn), on: canvas, pageID: pageID,
                              actionName: String(localized: "Snap Highlighter"), announcement: String(localized: "Highlight laid over the text"))
        }
        return true
    }

    private func replaceLastStroke(_ drawn: PKStroke, with tidied: PKStroke, on canvas: PageCanvasView, pageID: UUID, actionName: String, announcement: String) {
        let count = canvas.drawing.strokes.count, stamp = drawn.path.creationDate
        func apply(tries: Int) {
            guard canvas.pageID == pageID, canvas.drawing.strokes.count == count, canvas.drawing.strokes.last?.path.creationDate == stamp else { return }
            guard document.undoManager.groupingLevel == 0 || tries == 0 else {
                return DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { apply(tries: tries - 1) }
            }
            var strokes = canvas.drawing.strokes
            strokes[count - 1] = tidied
            let drawing = PKDrawing(strokes: strokes)
            isApplyingDrawing = true
            canvas.drawing = drawing
            isApplyingDrawing = false
            document.canvasDidChangeInk(pageID, to: drawing)
            mirrorInk(from: canvas, pageID: pageID)
            document.undoManager.setActionName(actionName)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            AccessibilityNotification.Announcement(announcement).post()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { apply(tries: 5) }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        if session.selection != nil { select(nil) }
        if !unreadWriting.isEmpty { typingTimer?.cancel() }
        guard canvasView === zoomCanvas else { return }
        zoomAdvance?.cancel()
        session.onTouchDown?()
    }

    func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
        guard !firstInkReported, (canvasView as? PageCanvasView)?.pageID == firstInkPage,
              (canvasView as? PageCanvasView)?.isLoaded == true else { return }
        reportFirstInk()
    }

    private func reportFirstInk() {
        guard !firstInkReported else { return }
        firstInkReported = true
        if let openInterval { signposter.endInterval("Open to first ink", openInterval) }
        onFirstInk?(CACurrentMediaTime() - openedAt)
    }

    func document(_ document: NotebookDocument, didReplaceInkOf pageID: UUID) {
        if inkLasso != nil, !isMovingInk, !inkSelection.isEmpty { setInkSelection([:]) }
        guard let ink = document.loadedInk(pageID) else { return }
        replayPages[pageID] = nil
        if zoomWindow?.pageID == pageID, let zoomCanvas { showZoomInk(ink, in: zoomCanvas) }
        if let slot = slots[pageID], slot.card != nil { drawCard(in: slot) }
        guard let canvas = canvases[pageID] else { return }
        show(ink, in: canvas)
    }

    private func pagesDidChange() {
        let updated = document.pages
        let updatedKeys = updated.map(SlotKey.init), currentKeys = pages.map(SlotKey.init)
        let titles = LinkTitles(pages: updated, notebooks: session.notebookTitles)
        let renamed = titles != linkTitles
        linkTitles = titles
        guard updatedKeys.elementsEqual(currentKeys, by: Self.sameSlot) else {
            if textSelection != nil { setTextSelection(nil) }
            relayout(updated, changed: Self.changedIDs(updatedKeys, currentKeys))
            refreshItems(all: renamed)
            refreshZoomWindow()
            return
        }
        pages = updated
        refreshItems(all: renamed)
        refreshZoomWindow()
    }

    func linksDidChange() {
        let titles = LinkTitles(pages: pages, notebooks: session.notebookTitles)
        guard titles != linkTitles else { return }
        linkTitles = titles
        mirrored = nil
        refreshItems(all: true)
        mirrorPresentation()
    }

    private func syncItems(in slot: PageSlotView) {
        slot.syncItems(assets: document.package.assetsDirectory, scale: bakedScale, links: linkTitles, lifted: session.liftedTapes) { [weak self, weak slot] itemID in
            guard let self, let slot else { return }
            self.activate(ItemSelection(pageID: slot.page.id, itemID: itemID))
        }
        for view in slot.itemViews.values where view.item.text?.list == .check {
            view.onTick = { [weak self, weak slot] itemID, line in
                guard let self, let slot else { return }
                self.toggleCheck(ItemSelection(pageID: slot.page.id, itemID: itemID), line: line)
            }
        }
        if let typing, typing.pageID == slot.page.id { slot.itemViews[typing.itemID]?.isHidden = true }
    }

    private func refreshItems(all: Bool = false) {
        for (id, slot) in slots {
            guard let index = index(of: id) else { continue }
            let page = pages[index]
            let changed = slot.page.extra["items"] != page.extra["items"]
            slot.page = page
            if let card = slot.card {
                if all { card.shownKey = nil }
                drawCard(in: slot)
            } else if changed || (all && page.hasItems) {
                syncItems(in: slot)
            }
        }
        showSelection()
    }

    private func item(_ selection: ItemSelection) -> PageItem? {
        slots[selection.pageID]?.page.items.first { $0.id == selection.itemID }
    }

    private func activate(_ selection: ItemSelection) {
        if let link = item(selection)?.link {
            session.follow(link, from: selection.pageID)
        } else if item(selection)?.tape != nil {
            if replay == nil, inkLasso == nil { session.toggleTape(selection.itemID) }
        } else if !isLocked, !document.isReadOnly {
            select(selection)
        }
    }

    private func selectedItem() -> (slot: PageSlotView, item: PageItem)? {
        guard let selection = session.selection, let slot = slots[selection.pageID],
              let item = slot.page.items.first(where: { $0.id == selection.itemID }) else { return nil }
        return (slot, item)
    }

    func select(_ selection: ItemSelection?) {
        if textView != nil, selection != typing { endTextEditing() }
        if cropView != nil, selection != session.selection { endCrop(keeping: true) }
        if session.selection != selection { session.selection = selection }
        showSelection()
    }

    private func showSelection() {
        guard !isLocked, !document.isReadOnly, let (slot, item) = selectedItem() else {
            discardTextEditor()
            endCrop(keeping: true)
            selectionView?.removeFromSuperview()
            selectionView = nil
            if session.selection != nil { session.selection = nil }
            return
        }
        let view = selectionView ?? ItemSelectionView(item: item, pageSize: slot.page.size)
        if view.superview !== slot {
            view.removeFromSuperview()
            slot.addSubview(view)
        }
        slot.bringSubviewToFront(view)
        view.pageSize = slot.page.size
        view.scale = bakedScale
        if !view.isChanging { view.show(item) }
        view.onChange = { [weak self] item, final in self?.selectedItemChanged(item, final: final) }
        view.onTap = { [weak self] point in self?.tappedSelection(at: point) }
        selectionView = view
        if let cropView, cropView.item != item || cropView.superview !== slot { endCrop(keeping: false) }
        view.isHidden = cropView != nil
        if let cropView {
            cropView.scale = bakedScale
            slot.bringSubviewToFront(cropView)
        }
        layoutTextEditor()
    }

    func beginCrop() {
        guard cropView == nil, textView == nil, !isLocked, !document.isReadOnly, let (slot, item) = selectedItem(), item.assetFile != nil else { return }
        let view = ItemCropView(item: item, picture: slot.itemViews[item.id]?.shownPicture, assets: document.package.assetsDirectory, scale: bakedScale)
        view.onChange = { [weak self] crop in self?.session.crop = crop }
        slot.addSubview(view)
        slot.itemViews[item.id]?.isHidden = true
        selectionView?.isHidden = true
        cropView = view
        session.crop = view.crop
        UIAccessibility.post(notification: .layoutChanged, argument: view.accessibilityElements?.first)
    }

    func endCrop(keeping: Bool) {
        guard let cropView else { return }
        let slot = cropView.superview as? PageSlotView, item = cropView.item, crop = cropView.crop
        self.cropView = nil
        cropView.removeFromSuperview()
        if session.crop != nil { session.crop = nil }
        slot?.itemViews[item.id]?.isHidden = false
        selectionView?.isHidden = false
        guard keeping, !document.isReadOnly, let slot, slot.page.items.contains(item), crop != (item.crop ?? PageItem.wholePicture) else { return }
        document.updateItems(onPage: slot.page.id, actionName: String(localized: "Crop")) { items in
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = items[index].cropped(to: crop) }
        }
    }

    func resetCrop() { cropView?.reset() }

    @objc private func cancelCrop() { endCrop(keeping: false) }
    @objc private func keepCrop() { endCrop(keeping: true) }

    private func selectedItemChanged(_ item: PageItem, final: Bool) {
        guard let selection = session.selection, let slot = slots[selection.pageID] else { return }
        slot.itemViews[item.id]?.update(item, onDark: slot.page.isDark(night: night), links: linkTitles, lifted: session.liftedTapes.contains(item.id))
        slot.itemViews[item.id]?.layout(scale: bakedScale)
        selectionView?.show(item)
        guard final else { return }
        document.updateItems(onPage: selection.pageID, actionName: String(localized: "Arrange")) { items in
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        }
    }

    private func item(at point: CGPoint, tapeOnly: Bool = false) -> ItemSelection? {
        guard bakedScale > 0 else { return nil }
        for slot in slots.values where slot.page.hasItems && slot.card == nil {
            let local = contentView.convert(point, from: scrollView)
            guard slot.frame.contains(local) else { continue }
            let onPage = CGPoint(x: (local.x - slot.frame.minX) / bakedScale, y: (local.y - slot.frame.minY) / bakedScale)
            let items = slot.page.items
            let hit = items.last { $0.isOverInk && $0.contains(onPage, slop: tapeOnly ? 0 : 6) }
                ?? (tapeOnly ? nil : items.last { $0.content != .unknown && $0.contains(onPage, slop: 6) })
            if let hit { return ItemSelection(pageID: slot.page.id, itemID: hit.id) }
        }
        return nil
    }

    @objc private func tappedTape(_ gesture: UITapGestureRecognizer) {
        guard let hit = item(at: gesture.location(in: scrollView), tapeOnly: true) else { return }
        session.toggleTape(hit.itemID)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === tapeTap else { return true }
        return replay == nil && inkLasso == nil && textOverlay == nil && !isOnSelection(gestureRecognizer)
            && item(at: gestureRecognizer.location(in: scrollView), tapeOnly: true) != nil
    }

    func tapesDidChange() {
        for slot in slots.values where slot.page.hasItems { slot.showLifted(session.liftedTapes, links: linkTitles) }
        mirrored = nil
        mirrorPresentation()
    }

    private func isOnSelection(_ gesture: UIGestureRecognizer) -> Bool {
        guard let selectionView else { return false }
        return selectionView.point(inside: gesture.location(in: selectionView), with: nil)
    }

    @objc private func tappedPage(_ gesture: UITapGestureRecognizer) {
        guard !isOnSelection(gesture), !isFinding, cropView == nil else { return }
        if replay != nil { return seekReplay(to: gesture.location(in: scrollView)) }
        if inkLasso != nil { return lassoTapped(at: stackPoint(gesture)) }
        if textOverlay != nil { return }
        let hit = isPresenting || !fingersDraw ? item(at: gesture.location(in: scrollView)) : nil
        if let hit, item(hit)?.tape != nil { return }
        if let hit, let link = item(hit)?.link { return session.follow(link, from: hit.pageID) }
        if let hit, let line = checklistLine(hit, at: gesture.location(in: scrollView)) { return toggleCheck(hit, line: line) }
        guard !isPresenting, !document.isReadOnly else { return }
        if hit != nil || session.selection != nil { select(hit) }
    }

    private func checklistLine(_ selection: ItemSelection, at point: CGPoint) -> Int? {
        guard !isLocked, !document.isReadOnly, bakedScale > 0, let slot = slots[selection.pageID], let item = item(selection),
              let box = item.text, box.list == .check else { return nil }
        let local = contentView.convert(point, from: scrollView)
        let dx = (local.x - slot.frame.minX) / bakedScale - item.center.x, dy = (local.y - slot.frame.minY) / bakedScale - item.center.y
        let x = dx * cos(-item.rotation) - dy * sin(-item.rotation), y = dx * sin(-item.rotation) + dy * cos(-item.rotation)
        return box.checkbox(at: CGPoint(x: x + item.size.width / 2, y: y + item.size.height / 2), width: item.size.width)
    }

    private func toggleCheck(_ selection: ItemSelection, line: Int) {
        guard !isLocked, !document.isReadOnly, let box = item(selection)?.text else { return }
        let ticking = !box.checked.contains(line)
        document.updateItems(onPage: selection.pageID, actionName: ticking ? String(localized: "Tick") : String(localized: "Untick")) { items in
            guard let index = items.firstIndex(where: { $0.id == selection.itemID }), var box = items[index].text else { return }
            box.toggleCheck(line: line)
            items[index].content = .text(box)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func tappedSelection(at point: CGPoint) {
        if let selection = session.selection, let item = item(selection), item.text?.list == .check,
           let line = item.text?.checkbox(at: point, width: item.size.width) {
            return toggleCheck(selection, line: line)
        }
        editText()
    }

    @objc private func heldPage(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !isLocked, !document.isReadOnly, !isOnSelection(gesture), cropView == nil,
              let hit = item(at: gesture.location(in: scrollView)) else { return }
        if let canvas = canvases[hit.pageID], canvas.drawingGestureRecognizer.isEnabled {
            canvas.drawingGestureRecognizer.isEnabled = false
            canvas.drawingGestureRecognizer.isEnabled = true
        }
        select(hit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func editText() {
        guard textView == nil, !isLocked, !document.isReadOnly, let selection = session.selection,
              let (slot, item) = selectedItem(), let box = item.text else { return }
        let view = UITextView()
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.text = box.string
        view.delegate = self
        view.accessibilityIdentifier = "page.text.editor"
        view.accessibilityLabel = String(localized: "Text box")
        slot.addSubview(view)
        textView = view
        typing = selection
        typed = box
        let markers = TextMarkersView()
        slot.insertSubview(markers, belowSubview: view)
        typingMarkers = markers
        slot.itemViews[item.id]?.isHidden = true
        selectionView?.isEditing = true
        session.isEditingText = true
        layoutTextEditor()
        view.becomeFirstResponder()
        view.selectedRange = NSRange(location: (view.text as NSString).length, length: 0)
    }

    private func liveTextItem() -> (slot: PageSlotView, item: PageItem)? {
        guard let textView, let (slot, item) = selectedItem(), var box = item.text else { return nil }
        box.string = textView.text
        box.checked = typed?.checked ?? box.checked
        var live = item
        live.content = .text(box)
        return (slot, live.fittedToText())
    }

    private func layoutTextEditor() {
        guard let textView, let (slot, item) = liveTextItem(), let box = item.text else { return }
        let onDark = slot.page.isDark(night: night)
        styleTextEditor(textView, box: box, onDark: onDark)
        textView.transform = .identity
        textView.bounds = CGRect(x: 0, y: 0, width: item.size.width * bakedScale, height: item.size.height * bakedScale)
        textView.center = CGPoint(x: item.center.x * bakedScale, y: item.center.y * bakedScale)
        textView.transform = CGAffineTransform(rotationAngle: item.rotation)
        selectionView?.show(item)
        slot.bringSubviewToFront(textView)
        if let typingMarkers {
            typingMarkers.transform = .identity
            typingMarkers.bounds = textView.bounds
            typingMarkers.center = textView.center
            typingMarkers.transform = textView.transform
            typingMarkers.show(box.list == nil ? nil : box, onDark: onDark, scale: bakedScale)
            slot.insertSubview(typingMarkers, belowSubview: textView)
        }
    }

    private func styleTextEditor(_ textView: UITextView, box: TextBox, onDark: Bool) {
        guard textView.markedTextRange == nil else { return }
        let styled = box.editingText(scale: bakedScale, onDark: onDark), storage = textView.textStorage
        guard storage.string == styled.string, !storage.isEqual(to: styled) || storage.length == 0 else { return }
        storage.beginEditing()
        styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length)) { attributes, range, _ in
            storage.setAttributes(attributes, range: range)
        }
        storage.endEditing()
        let caret = textView.selectedRange.location, text = storage.string as NSString
        textView.typingAttributes = caret > 0 && caret <= text.length && text.character(at: caret - 1) != 10
            ? storage.attributes(at: caret - 1, effectiveRange: nil) : box.typingAttributes(scale: bakedScale, onDark: onDark)
    }

    func textViewDidChange(_ textView: UITextView) {
        typed?.carryChecks(to: textView.text)
        layoutTextEditor()
        revealTextEditor()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        endTextEditing()
    }

    @objc private func finishTyping() { endTextEditing() }

    private func endTextEditing() {
        guard let textView, let typing else { return }
        let string = textView.text ?? "", checked = typed?.checked
        discardTextEditor()
        if !isModalShowing { anchor.becomeFirstResponder() }
        if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if document.undoManager.canUndo, document.undoManager.undoActionName == EditorSession.addTextAction, item(typing)?.text?.string.isEmpty == true {
                document.undoManager.undo()
            } else {
                document.updateItems(onPage: typing.pageID, actionName: String(localized: "Delete")) { $0.removeAll { $0.id == typing.itemID } }
            }
        } else {
            document.updateItems(onPage: typing.pageID, actionName: String(localized: "Edit Text")) { items in
                guard let index = items.firstIndex(where: { $0.id == typing.itemID }), var box = items[index].text else { return }
                box.string = string
                box.checked = checked ?? box.checked
                items[index].content = .text(box)
                items[index] = items[index].fittedToText()
            }
        }
    }

    private func discardTextEditor() {
        guard let textView else { return }
        self.textView = nil
        textView.delegate = nil
        textView.removeFromSuperview()
        typingMarkers?.removeFromSuperview()
        typingMarkers = nil
        if let typing { slots[typing.pageID]?.itemViews[typing.itemID]?.isHidden = false }
        typing = nil
        typed = nil
        selectionView?.isEditing = false
        if session.isEditingText { session.isEditingText = false }
        updateInsets()
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue, let window = view.window else { return }
        let covered = view.convert(frame, from: window.screen.coordinateSpace).intersection(view.bounds)
        keyboardOverlap = covered.isNull ? 0 : max(0, view.bounds.maxY - covered.minY)
        if isFinding { updateInsets() }
        guard textView != nil else { return }
        updateInsets()
        revealTextEditor()
    }

    private func revealTextEditor() {
        guard let textView, let slot = textView.superview else { return }
        scrollView.scrollRectToVisible(scrollView.convert(textView.frame, from: slot).insetBy(dx: 0, dy: -24), animated: true)
    }

    private var acceptsPictures: Bool { !document.isReadOnly && !isLocked }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        acceptsPictures && session.canLoadObjects(ofClass: UIImage.self)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: acceptsPictures ? .copy : .forbidden)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        let local = contentView.convert(session.location(in: view), from: view)
        guard effectiveScale > 0, let index = layout.frames.indices.first(where: {
            !layout.frames[$0].isEmpty && layout.frames[$0].insetBy(dx: -PageStackLayout.margin, dy: -PageStackLayout.margin / 2).contains(CGPoint(x: local.x / bakedScale, y: local.y / bakedScale))
        }) else { return }
        let frame = layout.frames[index]
        let point = layout.isLaidOut(index, in: pages)
            ? CGPoint(x: min(max(local.x / bakedScale - frame.minX, 0), frame.width), y: min(max(local.y / bakedScale - frame.minY, 0), frame.height)) : nil
        session.loadObjects(ofClass: UIImage.self) { [weak self] objects in
            self?.place(objects.compactMap { $0 as? UIImage }, onPage: index, at: point)
        }
    }

    private func place(_ images: [UIImage], onPage index: Int?, at point: CGPoint?) {
        let editor = session
        document.perform {
            for image in images { try? await editor.addPicture(image, onPage: index, at: point) }
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) { return acceptsPictures && !isModalShowing && UIPasteboard.general.hasImages }
        if action == #selector(copy(_:)) { return textSelection != nil && !isModalShowing }
        return super.canPerformAction(action, withSender: sender)
    }

    override func copy(_ sender: Any?) {
        guard let text = textSelection?.selection.text else { return }
        UIPasteboard.general.string = text
        AccessibilityNotification.Announcement(String(localized: "Copied")).post()
    }

    override func paste(_ sender: Any?) {
        guard acceptsPictures, let images = UIPasteboard.general.images, !images.isEmpty else { return }
        place(images, onPage: nil, at: nil)
    }

    @objc private func deleteSelectedItem() { session.deleteSelection() }
    @objc private func clearSelection() { select(nil) }

    func visibleCenter(ofPage index: Int) -> CGPoint? {
        guard layout.isLaidOut(index, in: pages), effectiveScale > 0 else { return nil }
        let frame = layout.frames[index]
        let area = readableArea
        let visible = CGRect(x: (scrollView.contentOffset.x + area.minX) / effectiveScale, y: (scrollView.contentOffset.y + area.minY) / effectiveScale,
                             width: area.width / effectiveScale, height: area.height / effectiveScale).intersection(frame)
        guard !visible.isNull, !visible.isEmpty else { return CGPoint(x: frame.width / 2, y: frame.height / 2) }
        return CGPoint(x: visible.midX - frame.minX, y: visible.midY - frame.minY)
    }

    private static func sameSlot(_ a: SlotKey, _ b: SlotKey) -> Bool {
        a.id == b.id && a.background == b.background && a.paperColorRaw == b.paperColorRaw && a.size == b.size && a.day == b.day
    }

    private static func changedIDs(_ updated: [SlotKey], _ current: [SlotKey]) -> Set<UUID> {
        let before = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = Set(current.map(\.id)).subtracting(updated.map(\.id))
        for key in updated where before[key.id].map({ !sameSlot($0, key) }) ?? true { changed.insert(key.id) }
        return changed
    }

    private func relayout(_ updated: [NotebookPage], changed: Set<UUID>) {
        let anchorID = pages.indices.contains(currentPage) ? pages[currentPage].id : nil
        let anchorOffset = anchorID.flatMap { id in index(of: id).map { scrollView.contentOffset.y - layout.frames[$0].minY * effectiveScale } }
        let pendingID = pendingPage.flatMap { pages.indices.contains($0) ? pages[$0].id : nil }
        let wasSolo = layout.solo
        pages = updated
        pendingPage = pendingID.flatMap(index(of:))
        if let wasSolo, soloID.flatMap(index(of:)) == nil {
            arrange(solo: nil)
            bake(zoom: stackZoom)
            if pages.isEmpty { return updateWindow(force: true) }
            return session.go(to: min(wasSolo, pages.count - 1), animated: false)
        }
        layout = PageStackLayout(pages: pages, solo: soloID.flatMap(index(of:)))
        for id in changed where slots[id] != nil { removeSlot(id) }
        for (id, slot) in slots {
            guard let index = index(of: id) else { removeSlot(id); continue }
            position(slot, at: index)
            slot.canvas?.accessibilityLabel = canvasLabel(pages[index], number: index + 1)
            slot.canvas?.accessibilityIdentifier = "page.canvas.\(index + 1)"
            nameCard(in: slot, at: index)
        }
        contentView.frame = CGRect(x: 0, y: 0, width: layout.size.width * effectiveScale, height: layout.size.height * effectiveScale)
        scrollView.contentSize = contentView.frame.size
        if let anchorID, let index = index(of: anchorID), let anchorOffset {
            scrollView.contentOffset = clamped(CGPoint(x: scrollView.contentOffset.x, y: layout.frames[index].minY * effectiveScale + anchorOffset))
        } else {
            scrollView.contentOffset = clamped(scrollView.contentOffset)
        }
        updateInsets()
        updateWindow(force: true)
        if let pendingPage { session.pageDidChange(pendingPage) }
    }

    private func measure() {
        let bounds = view.bounds
        scrollView.scrollsToTop = !isSolo
        scrollView.showsVerticalScrollIndicator = !isSolo
        scrollView.showsHorizontalScrollIndicator = !isSolo
        if isSolo {
            fitScale = bounds.width / (PageStackLayout.sheetWidth(pages) + PageStackLayout.margin * 2)
            minimumZoom = Whiteboard.minimumZoom
        } else {
            fitScale = bounds.width / layout.size.width
            let tallest = layout.frames.map(\.height).max() ?? 1
            minimumZoom = min(1, bounds.height / (tallest + PageStackLayout.margin * 2) / fitScale)
        }
        maximumZoom = max(minimumZoom, min(5, 9.5 / max(fitScale, 0.01)))
    }

    private func boardMiddle(of size: CGSize? = nil) -> CGPoint {
        var area = pageArea
        if let size {
            area.size.width += size.width - view.bounds.width
            area.size.height += size.height - view.bounds.height
        }
        guard effectiveScale > 0 else { return Whiteboard.center }
        return CGPoint(x: (scrollView.contentOffset.x + area.midX) / effectiveScale, y: (scrollView.contentOffset.y + area.midY) / effectiveScale)
    }

    private func center(on point: CGPoint, in area: CGRect? = nil) {
        let area = area ?? pageArea
        scrollView.contentOffset = clamped(CGPoint(x: point.x * bakedScale - area.midX, y: point.y * bakedScale - area.midY))
    }

    private func boardFrame(_ index: Int) -> CGRect {
        Whiteboard.frame(of: pages[index], ink: document.loadedInk(pages[index].id) ?? PKDrawing())
    }

    private func presentedFrame(_ index: Int) -> CGRect {
        layout.solo == index ? boardFrame(index) : layout.frames[index]
    }

    private func rememberView(evenPresenting: Bool = false) {
        guard lastBounds != .zero, effectiveScale > 0, evenPresenting || !isPresenting else { return }
        if let soloID { boardViews[soloID] = (boardMiddle(), zoom) } else { stackZoom = zoom }
    }

    private func arrange(solo id: UUID?) {
        rememberView()
        if zoomPanel != nil {
            closeZoomWindow()
            session.zoomWindowDidClose()
        }
        select(nil)
        if inkLasso != nil { setInkSelection([:]) }
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        if lastBounds != .zero, view.window != nil {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.18
            scrollView.layer.add(fade, forKey: "board")
        }
        for slot in Array(slots.keys) { removeSlot(slot) }
        soloID = id
        layout = PageStackLayout(pages: pages, solo: id.flatMap(index(of:)))
        canvasWindow = nil
        pendingPage = nil
        if lastBounds != .zero { measure() }
    }

    private func openBoard(_ index: Int) {
        pendingPage = nil
        guard soloID != pages[index].id else { return }
        arrange(solo: pages[index].id)
        guard lastBounds != .zero else { return }
        placeBoard()
        updateWindow(force: true)
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private func closeBoard() {
        guard soloID != nil else { return }
        arrange(solo: nil)
        if lastBounds != .zero { bake(zoom: stackZoom) }
    }

    private func bring(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        if pages[index].isBoard {
            openBoard(index)
        } else if isSolo {
            scrollToPage(index, animated: false)
        }
    }

    private func placeBoard() {
        guard let id = soloID, let index = layout.solo else { return }
        if let left = boardViews[id] {
            bake(zoom: left.zoom)
            return center(on: left.center)
        }
        bake(zoom: 1)
        if let ink = document.loadedInk(id) { return showContent(of: index, ink: ink) }
        center(on: Whiteboard.contentBounds(of: pages[index], ink: PKDrawing()).map { CGPoint(x: $0.midX, y: $0.midY) } ?? Whiteboard.center, in: readableArea)
        let placed = scrollView.contentOffset
        Task { [weak self] in
            guard let self else { return }
            let ink = await document.ink(id)
            guard soloID == id, zoom == 1, scrollView.contentOffset == placed, !isPresenting, let index = self.index(of: id) else { return }
            showContent(of: index, ink: ink)
            updateWindow(force: true)
        }
    }

    private func showContent(of index: Int, ink: PKDrawing) {
        let area = readableArea
        guard Whiteboard.contentBounds(of: pages[index], ink: ink) != nil else { return center(on: Whiteboard.center, in: area) }
        let frame = Whiteboard.frame(of: pages[index], ink: ink)
        let fits = min(area.width / (frame.width * fitScale), area.height / (frame.height * fitScale))
        bake(zoom: min(max(fits, minimumZoom), 1))
        center(on: CGPoint(x: frame.midX, y: frame.midY), in: area)
    }

    private func canvasLabel(_ page: NotebookPage, number: Int) -> String {
        page.isBoard ? String(localized: "Whiteboard, page \(number), handwriting") : DailyJournal.canvasLabel(page: number, day: page.day)
    }

    private func nameCard(in slot: PageSlotView, at index: Int) {
        slot.card?.accessibilityLabel = String(localized: "Whiteboard, page \(index + 1)")
        slot.card?.accessibilityIdentifier = "page.board.\(index + 1)"
    }

    private func drawCard(in slot: PageSlotView) {
        guard let card = slot.card else { return }
        let page = slot.page, id = page.id, assets = document.package.assetsDirectory, titles = linkTitles
        let width = min(max(slot.bounds.width, 320), 1100), scale = max(traitCollection.displayScale, 1), night = slot.night
        Task { [weak self, weak card] in
            guard let self else { return }
            let ink = await document.ink(id)
            let key = "\(page.appearanceKey)-\(NotebookFind.fingerprint(ink))"
            guard let card, card.shownKey != key else { return }
            card.shownKey = key
            let image = await Task.detached(priority: .userInitiated) {
                SharedSlide(image: PageRenderer.image(of: page, ink: ink, assets: assets, width: width, scale: scale, links: titles, night: night))
            }.value.image
            if card.shownKey == key { card.image = image }
        }
    }

    func nativeToolPickerDidChange() {
        applyDrawingPolicy(drawingPolicy)
        layoutZoomPanel()
        updateInsets()
        guard !isModalShowing, textView == nil else { return }
        configureNativeToolPicker()
    }

    func setModalShowing(_ showing: Bool) {
        guard showing != isModalShowing else { return }
        isModalShowing = showing
        if showing { session.dish = nil }
        if !showing, textView == nil, !anchor.isFirstResponder { anchor.becomeFirstResponder() }
    }

    func setDrawingPolicy(_ policy: PKCanvasViewDrawingPolicy) {
        applyDrawingPolicy(policy)
    }

    private func applyDrawingPolicy(_ policy: PKCanvasViewDrawingPolicy) {
        drawingPolicy = policy
        let effective = effectivePolicy
        for canvas in allCanvases + pool where canvas.drawingPolicy != effective { canvas.drawingPolicy = effective }
        updateScrollTouches()
    }

    private var drawingPolicy: PKCanvasViewDrawingPolicy = .default

    private var effectivePolicy: PKCanvasViewDrawingPolicy {
        switch drawingPolicy {
        case .anyInput, .pencilOnly: drawingPolicy
        default: session.showsNativeTools && !UIPencilInteraction.prefersPencilOnlyDrawing ? .anyInput : .pencilOnly
        }
    }

    private var fingersCanLasso: Bool {
        switch drawingPolicy {
        case .anyInput: true
        case .pencilOnly: false
        default: !UIPencilInteraction.prefersPencilOnlyDrawing
        }
    }

    private func updateScrollTouches() {
        let fingersDraw = switch effectivePolicy {
        case _ where isPresenting: fingersPoint
        case _ where textOverlay != nil: true
        case _ where inkLasso != nil: false
        case _ where document.isReadOnly || replay != nil || isFinding: false
        case .anyInput: true
        default: false
        }
        self.fingersDraw = fingersDraw
        scrollView.panGestureRecognizer.minimumNumberOfTouches = fingersDraw ? 2 : 1
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        laserGesture.allowedTouchTypes = fingersPoint ? Self.scrollTouchTypes + [pencil] : [pencil]
    }

    func paneBecameActive() {
        if textView == nil, !isModalShowing { anchor.becomeFirstResponder() }
    }

    private var stackFrames: [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        for (index, page) in pages.enumerated() where layout.isLaidOut(index, in: pages) { frames[page.id] = layout.frames[index] }
        return frames
    }

    private var liveInk: [UUID: PKDrawing] {
        var result: [UUID: PKDrawing] = [:]
        for id in canvases.keys { result[id] = document.loadedInk(id) }
        return result
    }

    func setSelectingInk(_ selecting: Bool) {
        guard selecting != (inkLasso != nil), isViewLoaded else { return }
        if selecting {
            select(nil)
            inkMenuSuspended = false
            let overlay = InkLassoOverlay(frame: contentView.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.scale = bakedScale
            overlay.addGestureRecognizer(lassoPan)
            contentView.addSubview(overlay)
            inkLasso = overlay
        } else {
            restoreLiftedInk()
            clearPasteSpot()
            inkMenuSuspended = false
            inkLasso?.removeFromSuperview()
            inkLasso = nil
            setInkSelection([:])
        }
        for canvas in canvases.values where canvas.isLoaded { setDrawingEnabled(!document.isReadOnly && !isLocked, canvas) }
        nativeToolPickerDidChange()
        updateScrollTouches()
    }

    private func setInkSelection(_ selection: InkSelection) {
        let kept = selection.filter { !$0.value.isEmpty }
        let isNew = kept != inkSelection
        // A style that was set but not yet written belongs to the ink it was set for: write it before that changes.
        if isNew, pendingRestyle != nil { commitRestyle() }
        inkSelection = kept
        if isNew {
            restyleBaseline = nil
            if !kept.isEmpty { session.inkSelectionToken &+= 1 }
        }
        if !kept.isEmpty { clearPasteSpot() }
        inkLasso?.showSelection(InkLasso.bounds(of: inkSelection, drawings: liveInk, frames: stackFrames))
        let count = inkSelection.values.reduce(0) { $0 + $1.count }
        if session.inkSelectionCount != count {
            session.inkSelectionCount = count
        }
        publishInkSelection()
    }

    /// Tells the editor where the selection is on the page view, so the menu can stand beside the ink it acts on.
    /// Nothing is published while a lasso is being drawn or the selection is being dragged.
    private func publishInkSelection() {
        var frame: CGRect?
        if let overlay = inkLasso, !inkMenuSuspended, !inkSelection.isEmpty, bakedScale > 0, let bounds = overlay.selectionBounds {
            let inContent = CGRect(x: bounds.minX * bakedScale, y: bounds.minY * bakedScale,
                                   width: bounds.width * bakedScale, height: bounds.height * bakedScale)
                .insetBy(dx: -8, dy: -8)
            frame = view.convert(inContent, from: contentView)
        }
        if session.inkSelectionFrame != frame { session.inkSelectionFrame = frame }
    }

    private func stackPoint(_ gesture: UIGestureRecognizer) -> CGPoint {
        let point = gesture.location(in: contentView)
        return CGPoint(x: point.x / bakedScale, y: point.y / bakedScale)
    }

    @objc private func lassoPanned(_ gesture: UIPanGestureRecognizer) {
        guard let overlay = inkLasso, bakedScale > 0 else { return }
        let point = stackPoint(gesture)
        switch gesture.state {
        case .began:
            inkMenuSuspended = true
            clearPasteSpot()
            if let bounds = overlay.selectionBounds, bounds.insetBy(dx: -14, dy: -14).contains(point) {
                lassoMoveOrigin = point
                publishInkSelection()
                liftInk()
            } else {
                lassoMoveOrigin = nil
                setInkSelection([:])
                overlay.begin(at: point)
            }
        case .changed:
            if let origin = lassoMoveOrigin {
                overlay.drag(by: CGSize(width: point.x - origin.x, height: point.y - origin.y))
            } else {
                overlay.add(point)
            }
        case .ended:
            inkMenuSuspended = false
            if let origin = lassoMoveOrigin {
                lassoMoveOrigin = nil
                moveInkSelection(by: CGSize(width: point.x - origin.x, height: point.y - origin.y), copying: false)
            } else {
                catchInk(inside: InkLasso.outline(from: overlay.end()))
            }
        default:
            inkMenuSuspended = false
            lassoMoveOrigin = nil
            _ = overlay.end()
            restoreLiftedInk()
            publishInkSelection()
        }
    }

    func catchInk(inside outline: [CGPoint]) {
        guard inkLasso != nil, outline.count >= 3 else { return }
        var caught: InkSelection = [:]
        let box = ShapeRecognizer.bounds(of: outline)
        for (id, frame) in stackFrames where frame.intersects(box) {
            guard let ink = document.loadedInk(id), !ink.strokes.isEmpty else { continue }
            let local = outline.map { CGPoint(x: $0.x - frame.minX, y: $0.y - frame.minY) }
            caught[id] = InkLasso.strokes(in: ink, inside: local)
        }
        setInkSelection(caught)
        let count = session.inkSelectionCount
        AccessibilityNotification.Announcement(count == 0 ? String(localized: "No ink selected") : String(localized: "\(count) strokes selected")).post()
    }

    private func liftInk() {
        commitRestyle()
        guard let overlay = inkLasso else { return }
        var images: [(image: UIImage, rect: CGRect)] = []
        let frames = stackFrames, screen = traitCollection.displayScale
        for (id, indices) in inkSelection {
            guard let ink = document.loadedInk(id), let frame = frames[id], let page = pages.first(where: { $0.id == id }) else { continue }
            let chosen = Set(indices)
            let picked = PKDrawing(strokes: ink.strokes.enumerated().filter { chosen.contains($0.offset) }.map(\.element))
            let bounds = picked.bounds.insetBy(dx: -2, dy: -2)
            guard !bounds.isNull, !bounds.isEmpty else { continue }
            var image: UIImage?
            UITraitCollection(userInterfaceStyle: page.inkAppearance(night: night)).performAsCurrent {
                image = picked.image(from: bounds, scale: min(screen * bakedScale, 6))
            }
            if let image { images.append((image, bounds.offsetBy(dx: frame.minX, dy: frame.minY))) }
            if let canvas = canvases[id] {
                isApplyingDrawing = true
                canvas.drawing = InkLasso.removing([id: indices], from: [id: ink])[id] ?? ink
                isApplyingDrawing = false
            }
        }
        overlay.lift(images)
    }

    private func restoreLiftedInk() {
        inkLasso?.drop()
        for id in inkSelection.keys {
            if let canvas = canvases[id], let ink = document.loadedInk(id) { show(ink, in: canvas) }
        }
        publishInkSelection()
    }

    private func moveInkSelection(by delta: CGSize, copying: Bool) {
        commitRestyle()
        guard !inkSelection.isEmpty, copying || abs(delta.width) + abs(delta.height) >= 1 else { return restoreLiftedInk() }
        let moved = InkLasso.moved(inkSelection, by: delta, copying: copying, drawings: liveInk, frames: stackFrames)
        isMovingInk = true
        let done = document.updateInk(moved.drawings, actionName: copying ? String(localized: "Duplicate Ink") : String(localized: "Move Ink"))
        isMovingInk = false
        inkLasso?.drop()
        if done { setInkSelection(moved.selection) } else { restoreLiftedInk() }
    }

    func duplicateInkSelection() {
        moveInkSelection(by: CGSize(width: 18, height: 18), copying: true)
    }

    func deleteInkSelection() {
        deleteInkSelection(actionName: String(localized: "Delete Ink"))
    }

    private func deleteInkSelection(actionName: String) {
        commitRestyle()
        guard !inkSelection.isEmpty else { return }
        let removed = InkLasso.removing(inkSelection, from: liveInk)
        isMovingInk = true
        document.updateInk(removed, actionName: actionName)
        isMovingInk = false
        setInkSelection([:])
    }

    // MARK: Restyling the selected ink

    /// What a restyle changes in the selected ink, measured against how it stood when its style was first touched, so
    /// the ink never jumps to a width worked out from a guess: it grows and shrinks from what it is.
    private struct InkRestyleChange: Equatable {
        var tint: UInt32?
        var isIdentity: Bool { tint == nil }
    }

    func restyleInkSelection(to preset: ToolPreset) {
        guard !inkSelection.isEmpty, !document.isReadOnly else { return }
        if restyleBaseline == nil { restyleBaseline = selectedInkStyle() }
        guard restyleBaseline != nil else { return }
        // Apply the chosen colour to every selected stroke, even if the first stroke already has it.
        let change = InkRestyleChange(tint: preset.tint)
        guard change != pendingRestyle else { return }
        pendingRestyle = change
        pendingRestyleStyle = preset

        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            self?.showRestylePreview()
        }

        restyleTask?.cancel()
        restyleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.commitRestyle()
        }
    }

    private func showRestylePreview() {
        guard let change = pendingRestyle else { return }
        for (id, indices) in inkSelection {
            guard let base = document.loadedInk(id), let canvas = canvases[id] else { continue }
            isApplyingDrawing = true
            canvas.drawing = base.restyled(Set(indices), widthScale: 1, tint: change.tint, opacity: nil)
            canvas.strokeCount = nil
            isApplyingDrawing = false
        }
    }

    /// Puts the document's own ink back on the canvases, where a preview of a style that wasn't kept is showing.
    private func revertRestylePreview() {
        for id in inkSelection.keys {
            if let canvas = canvases[id], let ink = document.loadedInk(id) { show(ink, in: canvas) }
        }
    }

    /// Writes the colour change into the notebook as one undo step.
    func commitRestyle() {
        previewTask?.cancel()
        previewTask = nil
        restyleTask?.cancel()
        restyleTask = nil
        guard let change = pendingRestyle else { return }
        let style = pendingRestyleStyle
        pendingRestyle = nil
        pendingRestyleStyle = nil
        guard !change.isIdentity, !inkSelection.isEmpty else { return revertRestylePreview() }
        var changed: [UUID: PKDrawing] = [:]
        for (id, indices) in inkSelection {
            guard let ink = document.loadedInk(id) else { continue }
            changed[id] = ink.restyled(Set(indices), widthScale: 1, tint: change.tint, opacity: nil)
        }
        guard !changed.isEmpty else { return revertRestylePreview() }
        isMovingInk = true
        let done = document.updateInk(changed, actionName: String(localized: "Change Ink Colour"))
        isMovingInk = false
        if done { restyleBaseline = style } else { revertRestylePreview() }
        setInkSelection(inkSelection)
    }

    /// The style of the first selected stroke, as the menu over the selection shows it.
    func selectedInkStyle() -> ToolPreset? {
        for page in pages {
            guard let indices = inkSelection[page.id], let ink = document.loadedInk(page.id) else { continue }
            for i in indices.sorted() where ink.strokes.indices.contains(i) {
                let stroke = ink.strokes[i]
                guard let kind = PKInkingTool.InkType(rawValue: stroke.ink.inkType.rawValue),
                      let size = InkCalibration.middleSize(of: stroke) else { continue }
                let width = InkCalibration.width(forPointSize: size, of: kind)
                let colour = InkCalibration.bytes(of: stroke.ink.color)
                // A stroke's point widths can swell with pressure. When it matches a saved tool's
                // ink and colour, prefer that tool's exact discrete setting over a pressure-derived guess.
                let saved = Toolbox.shared.shelf.usable
                    .filter { $0.ink == kind.rawValue && ($0.tint & 0xFFFF_FF00) == (colour & 0xFFFF_FF00) }
                    .min { abs($0.width - width) < abs($1.width - width) }
                if let saved { return saved }
                return ToolPreset(ink: kind, color: colour, width: width)
            }
        }
        return nil
    }

    private func isOnInkSelection(_ contentPoint: CGPoint) -> Bool {
        guard let bounds = inkLasso?.selectionBounds, bakedScale > 0 else { return false }
        return bounds.insetBy(dx: -14, dy: -14).contains(CGPoint(x: contentPoint.x / bakedScale, y: contentPoint.y / bakedScale))
    }

    private func selectedStrokesInStack() -> [PKStroke] {
        let frames = stackFrames
        var strokes: [PKStroke] = []
        for page in pages {
            guard let indices = inkSelection[page.id], let ink = document.loadedInk(page.id), let frame = frames[page.id] else { continue }
            for i in indices.sorted() where ink.strokes.indices.contains(i) {
                var stroke = ink.strokes[i]
                stroke.transform = stroke.transform.concatenating(CGAffineTransform(translationX: frame.minX, y: frame.minY))
                strokes.append(stroke)
            }
        }
        return strokes
    }

    func copyInkSelection() {
        commitRestyle()
        let strokes = selectedStrokesInStack()
        guard !strokes.isEmpty else { return }
        InkClipboard.shared.set(strokes)
        AccessibilityNotification.Announcement(String(localized: "\(strokes.count) strokes copied")).post()
    }

    func cutInkSelection() {
        commitRestyle()
        let strokes = selectedStrokesInStack()
        guard !strokes.isEmpty, !document.isReadOnly else { return }
        InkClipboard.shared.set(strokes)
        deleteInkSelection(actionName: String(localized: "Cut Ink"))
        AccessibilityNotification.Announcement(String(localized: "\(strokes.count) strokes cut")).post()
    }

    private var visibleStackRect: CGRect {
        guard bakedScale > 0 else { return .zero }
        let shown = scrollView.convert(scrollView.bounds, to: contentView)
        return CGRect(x: shown.minX / bakedScale, y: shown.minY / bakedScale, width: shown.width / bakedScale, height: shown.height / bakedScale)
    }

    func pasteInk() {
        let clipboard = InkClipboard.shared
        guard let bounds = clipboard.bounds else { return }
        clipboard.pastes += 1
        let step = CGFloat(24 * clipboard.pastes)
        let along = CGPoint(x: bounds.midX + step, y: bounds.midY + step)
        let visible = visibleStackRect
        pasteInk(at: visible.contains(along) ? along : CGPoint(x: visible.midX, y: visible.midY))
    }

    func pasteInk(at point: CGPoint) {
        commitRestyle()
        let clipboard = InkClipboard.shared
        let frames = stackFrames
        guard !document.isReadOnly, !clipboard.isEmpty, let bounds = clipboard.bounds,
              let target = InkLasso.page(at: point, frames: frames), let frame = frames[target],
              let ink = document.loadedInk(target) else { return }
        let move = CGAffineTransform(translationX: point.x - bounds.midX - frame.minX, y: point.y - bounds.midY - frame.minY)
        let pasted = clipboard.strokes.map { stroke in
            PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform.concatenating(move), mask: stroke.mask, randomSeed: stroke.randomSeed)
        }
        let all = ink.strokes + pasted
        isMovingInk = true
        let done = document.updateInk([target: PKDrawing(strokes: all)], actionName: String(localized: "Paste Ink"))
        isMovingInk = false
        guard done else { return }
        if inkLasso != nil { setInkSelection([target: Array(ink.strokes.count..<all.count)]) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AccessibilityNotification.Announcement(String(localized: "\(pasted.count) strokes pasted")).post()
    }

    private func lassoTapped(at point: CGPoint) {
        // A tap on the selection leaves it as it is: the menu is already beside it.
        if let bounds = inkLasso?.selectionBounds, bounds.insetBy(dx: -14, dy: -14).contains(point) { return }
        setInkSelection([:])
        offerPaste(at: point)
    }

    @objc private func heldForPaste(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, inkLasso != nil, bakedScale > 0 else { return }
        let point = stackPoint(gesture)
        if let bounds = inkLasso?.selectionBounds, bounds.insetBy(dx: -14, dy: -14).contains(point) { return }
        guard !InkClipboard.shared.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        offerPaste(at: point)
    }

    /// Puts a Paste button where the paper was tapped or held, when there is ink to paste.
    private func offerPaste(at stackPoint: CGPoint) {
        guard !InkClipboard.shared.isEmpty, !document.isReadOnly, bakedScale > 0 else { return }
        inkPasteStackPoint = stackPoint
        session.inkPasteSpot = view.convert(CGPoint(x: stackPoint.x * bakedScale, y: stackPoint.y * bakedScale), from: contentView)
    }

    private func clearPasteSpot() {
        inkPasteStackPoint = nil
        if session.inkPasteSpot != nil { session.inkPasteSpot = nil }
    }

    func pasteInkAtHeldSpot() {
        guard let point = inkPasteStackPoint else { return pasteInk() }
        clearPasteSpot()
        pasteInk(at: point)
    }

    func selectedInk() -> [PKDrawing] {
        commitRestyle()
        return pages.compactMap { page in
            guard let indices = inkSelection[page.id], let ink = document.loadedInk(page.id) else { return nil }
            let chosen = Set(indices)
            let strokes = ink.strokes.enumerated().filter { chosen.contains($0.offset) }.map(\.element)
            return strokes.isEmpty ? nil : PKDrawing(strokes: strokes)
        }
    }

    func selectedInkByPage() -> [(pageID: UUID, ink: PKDrawing)] {
        commitRestyle()
        return pages.compactMap { page in
            guard let indices = inkSelection[page.id], let ink = document.loadedInk(page.id) else { return nil }
            let chosen = Set(indices)
            let strokes = ink.strokes.enumerated().filter { chosen.contains($0.offset) }.map(\.element)
            return strokes.isEmpty ? nil : (page.id, PKDrawing(strokes: strokes))
        }
    }

    func replaceInkSelection(with text: String) -> ItemSelection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let page = pages.first(where: { inkSelection[$0.id]?.isEmpty == false }),
              let bounds = selectedInk().first?.bounds, !bounds.isNull else { return nil }
        let item = InkText.box(for: trimmed, replacing: bounds, pageSize: page.size)
        let action = String(localized: "Turn Ink into Text")
        isMovingInk = true
        let done = document.updateInk(InkLasso.removing(inkSelection, from: liveInk), actionName: action)
        isMovingInk = false
        guard done else { return nil }
        document.updateItems(onPage: page.id, actionName: action) { $0.append(item) }
        setInkSelection([:])
        return ItemSelection(pageID: page.id, itemID: item.id)
    }

    func setSelectingText(_ selecting: Bool) {
        commitRestyle()
        guard selecting != (textOverlay != nil), isViewLoaded else { return }
        if selecting {
            select(nil)
            let overlay = TextSelectOverlay(frame: contentView.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.scale = bakedScale
            overlay.addGestureRecognizer(textPan)
            overlay.addGestureRecognizer(textTap)
            contentView.addSubview(overlay)
            if let zoomTarget { contentView.bringSubviewToFront(zoomTarget) }
            textOverlay = overlay
        } else {
            textOverlay?.removeFromSuperview()
            textOverlay = nil
            textAnchor = nil
            textRequest += 1
            setTextSelection(nil)
        }
        for canvas in canvases.values where canvas.isLoaded { setDrawingEnabled(!document.isReadOnly && !isLocked, canvas) }
        nativeToolPickerDidChange()
        updateScrollTouches()
    }

    private func pdfPage(at point: CGPoint) -> (index: Int, point: CGPoint)? {
        let index = layout.pageIndex(atY: point.y)
        guard layout.isLaidOut(index, in: pages), layout.frames[index].contains(point), case .pdf = pages[index].background else { return nil }
        return (index, CGPoint(x: point.x - layout.frames[index].minX, y: point.y - layout.frames[index].minY))
    }

    @objc private func textPanned(_ gesture: UIPanGestureRecognizer) {
        guard textOverlay != nil, bakedScale > 0 else { return }
        let point = stackPoint(gesture)
        switch gesture.state {
        case .began:
            let down = textOverlay?.touchDown.map { CGPoint(x: $0.x / bakedScale, y: $0.y / bakedScale) }
            setTextSelection(nil)
            textAnchor = pdfPage(at: down ?? point)
            fallthrough
        case .changed, .ended:
            guard let anchor = textAnchor, layout.isLaidOut(anchor.index, in: pages) else { return }
            let frame = layout.frames[anchor.index]
            let reached = CGPoint(x: min(max(point.x - frame.minX, 0), frame.width), y: min(max(point.y - frame.minY, 0), frame.height))
            requestText(.range(from: anchor.point, to: reached), onPage: anchor.index, announces: gesture.state == .ended)
            if gesture.state == .ended { textAnchor = nil }
        default:
            textAnchor = nil
        }
    }

    @objc private func textTapped(_ gesture: UITapGestureRecognizer) {
        guard textOverlay != nil, bakedScale > 0 else { return }
        guard let hit = pdfPage(at: stackPoint(gesture)) else { return setTextSelection(nil) }
        requestText(.word(at: hit.point), onPage: hit.index, announces: true)
    }

    func selectAllText() {
        let index = pendingPage ?? currentPage
        guard textOverlay != nil, pages.indices.contains(index) else { return }
        requestText(.everything, onPage: index, announces: true)
    }

    private func requestText(_ request: PDFTextReader.Request, onPage index: Int, announces: Bool) {
        textRequest += 1
        guard pages.indices.contains(index), case .pdf(let file, let pdfIndex) = pages[index].background else {
            setTextSelection(nil)
            if announces { AccessibilityNotification.Announcement(String(localized: "This page has no text to select")).post() }
            return
        }
        let token = textRequest, page = pages[index], url = document.package.assetURL(file)
        Task { [weak self] in
            guard let self else { return }
            let found = await pdfText.select(request, file: url, index: pdfIndex, pageSize: page.size)
            guard token == textRequest, textOverlay != nil else { return }
            setTextSelection(found.map { (page.id, $0) })
            guard announces else { return }
            let words = found?.text.split(whereSeparator: \.isWhitespace).count ?? 0
            AccessibilityNotification.Announcement(words == 0 ? String(localized: "This page has no text to select") : String(localized: "\(words) words selected")).post()
        }
    }

    private func setTextSelection(_ selection: (pageID: UUID, selection: TextSelection)?) {
        textSelection = selection
        var rects: [CGRect] = []
        if let selection, let index = index(of: selection.pageID), layout.isLaidOut(index, in: pages) {
            let frame = layout.frames[index]
            rects = selection.selection.lines.map { $0.offsetBy(dx: frame.minX, dy: frame.minY) }
        }
        textOverlay?.show(rects)
        let text = selection?.selection.text
        if session.selectedText != text { session.selectedText = text }
    }

    func highlightSelectedText(_ color: HighlightColor) {
        guard let selected = textSelection, !document.isReadOnly else { return }
        setTextSelection(nil)
        let ink = PKInk(.marker, color: color.uiColor), document = document
        let strokes = selected.selection.lines.map { TextHighlight.stroke(over: $0, ink: ink) }
        document.perform {
            let drawing = await document.ink(selected.pageID)
            document.updateInk([selected.pageID: PKDrawing(strokes: drawing.strokes + strokes)], actionName: String(localized: "Highlight Text"))
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AccessibilityNotification.Announcement(String(localized: "Text highlighted")).post()
    }

    func setFinding(_ finding: Bool) {
        guard finding != isFinding, isViewLoaded else { return }
        isFinding = finding
        if finding {
            select(nil)
        } else {
            findRects = [:]
            findCurrent = nil
            for slot in slots.values { showFind(in: slot) }
        }
        for canvas in canvases.values where canvas.isLoaded { setDrawingEnabled(!document.isReadOnly && !isLocked, canvas) }
        nativeToolPickerDidChange()
        updateScrollTouches()
        updateInsets()
    }

    func showFind(_ matches: [FindMatch], current: FindMatch?) {
        guard isFinding else { return }
        findRects = Dictionary(grouping: matches, by: \.pageID).mapValues { $0.map(\.rect) }
        let moved = current != findCurrent
        findCurrent = current
        for slot in slots.values { showFind(in: slot) }
        if moved, let current { reveal(current) }
    }

    private func showFind(in slot: PageSlotView) {
        let rects = slot.card == nil ? findRects[slot.page.id] ?? [] : []
        guard isFinding, !rects.isEmpty else {
            slot.findView?.removeFromSuperview()
            slot.findView = nil
            return
        }
        let view = slot.findView ?? FindHighlightView()
        if view.superview !== slot { slot.addSubview(view) }
        slot.bringSubviewToFront(view)
        view.frame = slot.bounds
        view.show(rects, current: findCurrent?.pageID == slot.page.id ? findCurrent?.rect : nil, scale: bakedScale,
                  onDark: slot.page.isDark(night: night))
        slot.findView = view
    }

    private func reveal(_ match: FindMatch) {
        guard let index = index(of: match.pageID) else { return }
        bring(index)
        session.pageDidChange(index)
        reveal(match.rect, onPage: index, margin: 56)
    }

    private func reveal(_ rect: CGRect, onPage index: Int, margin: CGFloat) {
        guard layout.isLaidOut(index, in: pages), effectiveScale > 0 else { return }
        let frame = layout.frames[index], scale = effectiveScale
        let target = CGRect(x: (frame.minX + rect.minX) * scale, y: (frame.minY + rect.minY) * scale, width: rect.width * scale, height: rect.height * scale)
        var area = readableArea
        area.size.height = max(min(area.height, view.bounds.maxY - keyboardOverlap - area.minY), 80)
        let visible = area.offsetBy(dx: scrollView.contentOffset.x, dy: scrollView.contentOffset.y)
        guard !visible.insetBy(dx: 8, dy: min(margin, max((visible.height - target.height) / 2, 0))).contains(target) else { return }
        let x = visible.minX <= target.minX && target.maxX <= visible.maxX ? scrollView.contentOffset.x : target.midX - area.midX
        let offset = clamped(CGPoint(x: x, y: target.midY - area.midY))
        let moves = abs(offset.y - scrollView.contentOffset.y) + abs(offset.x - scrollView.contentOffset.x) > 0.5
        pendingPage = moves ? index : nil
        scrollView.setContentOffset(offset, animated: moves)
    }

    private var allCanvases: [PageCanvasView] { Array(canvases.values) + (zoomCanvas.map { [$0] } ?? []) }

    func setZoomWindow(_ open: Bool) {
        guard open != (zoomPanel != nil), isViewLoaded else { return }
        if open { openZoomWindow() } else { closeZoomWindow() }
    }

    private func openZoomWindow() {
        guard !isLocked, !document.isReadOnly, !pages.isEmpty else { return session.zoomWindowDidClose() }
        select(nil)
        let index = pendingPage ?? currentPage
        if !layout.isLaidOut(index, in: pages) { bring(index) }
        let panel = ZoomWindowPanel()
        panel.isLeftHanded = UserDefaults.standard.bool(forKey: SettingsKey.leftHanded)
        panel.onAction = { [weak self] in self?.zoomAction($0) }
        view.insertSubview(panel, belowSubview: laser)
        zoomPanel = panel
        let canvas = makeCanvas()
        syncTool(canvas)
        canvas.accessibilityIdentifier = "zoom.canvas"
        panel.host(canvas)
        zoomCanvas = canvas
        let target = ZoomTargetView()
        target.pan.addTarget(self, action: #selector(zoomTargetPanned))
        target.onStep = { [weak self] in self?.zoomAction($0 > 0 ? .forward : .back) }
        scrollView.panGestureRecognizer.require(toFail: target.pan)
        contentView.addSubview(target)
        zoomTarget = target
        layoutZoomPanel()
        placeZoomWindow(onPage: index, center: visibleCenter(ofPage: index))
        updateInsets()
        revealZoomTarget()
        UIAccessibility.post(notification: .layoutChanged, argument: canvas)
    }

    private func closeZoomWindow() {
        guard zoomPanel != nil else { return }
        zoomAdvance?.cancel()
        if let canvas = zoomCanvas {
            if canvas.isFirstResponder { anchor.becomeFirstResponder() }
            canvas.delegate = nil
        }
        zoomPanel?.removeFromSuperview()
        zoomTarget?.removeFromSuperview()
        zoomPanel = nil
        zoomCanvas = nil
        zoomPaper = nil
        zoomTarget = nil
        zoomWindow = nil
        session.zoomPanelLift = 0
        updateInsets()
        scrollView.contentOffset = clamped(scrollView.contentOffset)
        updateWindow(force: true)
    }

    private func layoutZoomPanel() {
        guard let panel = zoomPanel else { return }
        let paper = min(max(view.bounds.height * 0.26, 170), 280) - ZoomWindowPanel.minimumBarHeight
        let height = paper + panel.barHeight(forWidth: view.bounds.width)
        let frame = CGRect(x: 0, y: view.bounds.maxY - height, width: view.bounds.width, height: height)
        let lift = max(height - view.safeAreaInsets.bottom, 0)
        if session.zoomPanelLift != lift { session.zoomPanelLift = lift }
        guard panel.frame != frame else { return }
        let resized = panel.frame.size != frame.size
        panel.frame = frame
        panel.layoutIfNeeded()
        if resized { resizeZoomWindow() }
    }

    private func zoomSize(onPage index: Int) -> CGSize? {
        guard let area = zoomPanel?.canvasArea.bounds.size, area.width > 0, area.height > 0, pages.indices.contains(index) else { return nil }
        let width = pages[index].sheetSize.width * ZoomWindow.widths[zoomLevel]
        return CGSize(width: width, height: area.height * width / area.width)
    }

    private func placeZoomWindow(onPage index: Int, center: CGPoint?) {
        guard let size = zoomSize(onPage: index) else { return }
        let page = pages[index]
        zoomWindow = ZoomWindow(pageID: page.id, pageSize: page.size, center: center ?? CGPoint(x: page.size.width / 2, y: page.size.height / 2),
                                size: size, lineHeight: ZoomWindow.lineHeight(for: page, windowHeight: size.height))
        zoomReachedBand = false
        document.pinInk(Set(canvases.keys).union([page.id]))
        showZoomWindow()
    }

    private func resizeZoomWindow() {
        guard var window = zoomWindow, let index = index(of: window.pageID), let size = zoomSize(onPage: index) else { return }
        window.resize(to: size)
        zoomWindow = window
        showZoomWindow()
    }

    private func refreshZoomWindow() {
        guard var window = zoomWindow else { return }
        guard let index = index(of: window.pageID) else {
            closeZoomWindow()
            return session.zoomWindowDidClose()
        }
        window.fit(pageSize: pages[index].size)
        zoomWindow = window
        showZoomWindow()
    }

    private func showZoomWindow() {
        guard let window = zoomWindow, let panel = zoomPanel, let canvas = zoomCanvas, let index = index(of: window.pageID) else { return }
        let page = pages[index], area = panel.canvasArea.bounds
        guard area.width > 0, window.rect.width > 0 else { return }
        let scale = area.width / window.rect.width
        if canvas.zoomScale != scale || canvas.minimumZoomScale != scale || canvas.maximumZoomScale != scale {
            canvas.minimumZoomScale = min(canvas.minimumZoomScale, scale)
            canvas.maximumZoomScale = max(canvas.maximumZoomScale, scale)
            canvas.zoomScale = scale
            canvas.minimumZoomScale = scale
            canvas.maximumZoomScale = scale
        }
        if canvas.frame != area { canvas.frame = area }
        let size = CGSize(width: page.size.width * scale, height: page.size.height * scale)
        if canvas.contentSize != size { canvas.contentSize = size }
        let offset = CGPoint(x: window.rect.minX * scale, y: window.rect.minY * scale)
        if canvas.contentOffset != offset { canvas.contentOffset = offset }
        syncTool(canvas)
        canvas.overrideUserInterfaceStyle = page.inkAppearance(night: night)
        canvas.accessibilityLabel = String(localized: "Zoom window, page \(index + 1)")
        if canvas.pageID != page.id { loadZoomInk(page.id, into: canvas) }
        panel.setTitle(String(localized: "Zoom Window · Page \(index + 1)"))
        panel.setEnabled(zoomLevel > 0, for: .closer)
        panel.setEnabled(zoomLevel < ZoomWindow.widths.count - 1, for: .further)

        showZoomPaper(page, rect: window.rect, scale: scale, in: panel)
        layoutZoomTarget()
    }

    private func showZoomPaper(_ page: NotebookPage, rect: CGRect, scale: CGFloat, in panel: ZoomWindowPanel) {
        var look = page
        look.inkHash = nil
        if zoomPaper?.page != look || zoomPaper?.night != night || zoomPaper?.links != linkTitles || zoomPaper?.unit != scale {
            if zoomPaper?.page.id != page.id { panel.paper.subviews.forEach { $0.removeFromSuperview() } }
            let paper = PagePaperView(page: look, assets: document.package.assetsDirectory, night: night, items: true, links: linkTitles)
            paper.fit(unit: scale, zoom: 1)
            let previous = panel.paper.subviews
            paper.onDrawn = { [weak paper] in
                previous.forEach { $0.removeFromSuperview() }
                paper?.onDrawn = nil
            }
            panel.paper.addSubview(paper)
            panel.paper.backgroundColor = PageRenderer.paperColor(look.effectivePaperColor, night: look.turnsDark(night))
            zoomPaper = paper
        }
        let pixel = max(traitCollection.displayScale, 1)
        for case let paper as PagePaperView in panel.paper.subviews where paper.unit > 0 {
            paper.fit(unit: paper.unit, zoom: scale / paper.unit)
            paper.center = CGPoint(x: (-rect.minX * scale * pixel).rounded() / pixel, y: (-rect.minY * scale * pixel).rounded() / pixel)
        }
        let shown = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        zoomPaper?.show(near: shown.insetBy(dx: -shown.width / 4, dy: 0), density: pixel)
    }

    private func loadZoomInk(_ pageID: UUID, into canvas: PageCanvasView) {
        canvas.pageID = pageID
        if let ink = document.loadedInk(pageID) { return showZoomInk(ink, in: canvas) }
        canvas.isLoaded = false
        setDrawingEnabled(false, canvas)
        Task { [weak self] in
            guard let self else { return }
            let ink = await document.ink(pageID)
            if zoomCanvas === canvas, canvas.pageID == pageID { showZoomInk(ink, in: canvas) }
        }
    }

    private func showZoomInk(_ ink: PKDrawing, in canvas: PageCanvasView) {
        isApplyingDrawing = true
        canvas.drawing = ink
        canvas.strokeCount = nil
        isApplyingDrawing = false
        canvas.isLoaded = true
        setDrawingEnabled(!document.isReadOnly && !isLocked, canvas)
    }

    private func layoutZoomTarget() {
        guard let target = zoomTarget else { return }
        guard let window = zoomWindow, let index = index(of: window.pageID), layout.isLaidOut(index, in: pages) else { return target.isHidden = true }
        let frame = layout.frames[index], scale = bakedScale
        target.isHidden = false
        target.frame = CGRect(x: (frame.minX + window.rect.minX) * scale, y: (frame.minY + window.rect.minY) * scale,
                              width: window.rect.width * scale, height: window.rect.height * scale)
        target.setNeedsLayout()
        target.accessibilityPlace = String(localized: "Page \(index + 1)")
        contentView.bringSubviewToFront(target)
    }

    private func revealZoomTarget() {
        guard let window = zoomWindow, let index = index(of: window.pageID) else { return }
        reveal(window.rect.insetBy(dx: 0, dy: -ZoomTargetView.tabSize.height / max(bakedScale, 0.1)), onPage: index, margin: 12)
    }

    private func zoomAction(_ action: ZoomWindowPanel.Action) {
        zoomAdvance?.cancel()
        switch action {
        case .back: moveZoomWindow { $0.back() }
        case .forward: moveZoomWindow(orTurnPage: true) { $0.advance() }
        case .newLine: moveZoomWindow(orTurnPage: true) { $0.newLine() }
        case .here:
            let index = pendingPage ?? currentPage
            if layout.isLaidOut(index, in: pages) { placeZoomWindow(onPage: index, center: visibleCenter(ofPage: index)) }
        case .closer, .further:
            zoomLevel = min(max(zoomLevel + (action == .closer ? -1 : 1), 0), ZoomWindow.widths.count - 1)
            resizeZoomWindow()
            revealZoomTarget()
        case .close:
            closeZoomWindow()
            session.zoomWindowDidClose()
        }
    }

    private func moveZoomWindow(orTurnPage: Bool = false, _ change: (inout ZoomWindow) -> Bool) {
        guard var window = zoomWindow else { return }
        zoomReachedBand = false
        if change(&window) {
            zoomWindow = window
            showZoomWindow()
        } else if orTurnPage, window.isAtPageEnd, let index = index(of: window.pageID), layout.isLaidOut(index + 1, in: pages) {
            let size = window.rect.size
            placeZoomWindow(onPage: index + 1, center: CGPoint(x: window.lineStart + size.width / 2, y: size.height / 2 + window.lineHeight))
        } else {
            return
        }
        revealZoomTarget()
    }

    private func zoomStrokeEnded(_ canvas: PageCanvasView, before: PKDrawing?) {
        guard let window = zoomWindow, canvas.tool is PKInkingTool, let before, canvas.drawing.strokes.count == before.strokes.count + 1,
              let stroke = canvas.drawing.strokes.last else { return }
        if window.reachesAdvanceBand(stroke.renderBounds) { zoomReachedBand = true }
        guard zoomReachedBand else { return }
        zoomAdvance?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.moveZoomWindow(orTurnPage: true) { $0.advance() } }
        zoomAdvance = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ZoomWindow.rest, execute: work)
    }

    @objc private func zoomTargetPanned(_ gesture: UIPanGestureRecognizer) {
        guard var window = zoomWindow, bakedScale > 0 else { return }
        switch gesture.state {
        case .began:
            zoomAdvance?.cancel()
            zoomDragOrigin = window.rect.origin
        case .changed, .ended:
            guard let origin = zoomDragOrigin else { return }
            let moved = gesture.translation(in: contentView)
            window.move(to: CGPoint(x: origin.x + moved.x / bakedScale, y: origin.y + moved.y / bakedScale))
            zoomWindow = window
            zoomReachedBand = false
            showZoomWindow()
            if gesture.state == .ended { zoomDragOrigin = nil }
        default:
            zoomDragOrigin = nil
        }
    }

    func showReplay(_ timeline: ReplayTimeline?, at time: TimeInterval) {
        let changed = (replay == nil) != (timeline == nil)
        replay = timeline.map { ($0, time) }
        if changed {
            undoProxy.isSuspended = replay != nil
            if replay != nil { select(nil) }
            for canvas in canvases.values where canvas.isLoaded { setDrawingEnabled(!document.isReadOnly && !isLocked, canvas) }
            nativeToolPickerDidChange()
            updateScrollTouches()
        }
        for (id, canvas) in canvases where canvas.isLoaded {
            let written = replay.flatMap { $0.timeline.hasInk(onPage: id) ? $0.timeline.written(onPage: id, by: time) : nil }
            guard written != replayPages[id]?.written, let ink = document.loadedInk(id) else { continue }
            isApplyingDrawing = true
            canvas.drawing = replayed(ink, on: id)
            isApplyingDrawing = false
        }
        if replay == nil { replayPages = [:] }
    }

    private func replayed(_ ink: PKDrawing, on pageID: UUID?) -> PKDrawing {
        guard let pageID else { return ink }
        guard let replay, replay.timeline.hasInk(onPage: pageID) else {
            replayPages[pageID] = nil
            return ink
        }
        return replayPages[pageID, default: ReplayInk.Page(ink, order: replay.timeline.strokes(onPage: pageID))]
            .drawing(written: replay.timeline.written(onPage: pageID, by: replay.time))
    }

    private func seekReplay(to point: CGPoint) {
        guard let replay, bakedScale > 0 else { return }
        let local = contentView.convert(point, from: scrollView)
        for slot in slots.values where slot.frame.contains(local) && slot.card == nil {
            let onPage = CGPoint(x: (local.x - slot.frame.minX) / bakedScale, y: (local.y - slot.frame.minY) / bakedScale)
            guard let ink = document.loadedInk(slot.page.id), let stroke = ReplayInk.stroke(at: onPage, in: ink),
                  let time = replay.timeline.time(ofStroke: stroke, onPage: slot.page.id) else { return }
            session.seekReplay(to: time)
        }
    }

    private var fingersPoint: Bool {
        switch drawingPolicy {
        case .anyInput: true
        case .pencilOnly: false
        default: !UIPencilInteraction.prefersPencilOnlyDrawing
        }
    }

    func setPresenting(_ presenting: Bool) {
        guard presenting != isPresenting else { return }
        isPresenting = presenting
        UIApplication.shared.isIdleTimerDisabled = presenting
        laserGesture.isEnabled = presenting
        laser.clear()
        mirrored = nil
        if presenting { ExternalDisplay.shared.begin(for: self) } else { ExternalDisplay.shared.end(for: self) }
        if presenting { select(nil) }
        for canvas in canvases.values where canvas.isLoaded { setDrawingEnabled(!document.isReadOnly && !isLocked, canvas) }
        nativeToolPickerDidChange()
        updateScrollTouches()
        guard isViewLoaded, lastBounds != .zero else { return }
        if presenting {
            rememberView(evenPresenting: true)
            updateInsets()
            present(page: currentPage)
        } else {
            let page = currentPage
            updateInsets()
            if isSolo {
                placeBoard()
            } else {
                bake(zoom: stackZoom)
                scrollToPage(page, animated: false)
            }
            updateWindow(force: true)
        }
    }

    func present(page index: Int) {
        guard pages.indices.contains(index) else { return }
        bring(index)
        pendingPage = index
        fit(.page)
    }

    func setLaserColor(_ color: LaserColor) {
        laser.color = color.uiColor
    }

    @objc private func pointLaser(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: laser)
        switch gesture.state {
        case .began:
            laser.begin(at: point)
            mirrorLaser(.began(onPresentedPage(point)))
        case .changed:
            laser.move(to: point)
            mirrorLaser(.moved(onPresentedPage(point)))
        default:
            laser.end()
            mirrorLaser(.ended)
        }
    }

    private var presentedPage: Int? {
        let index = pendingPage ?? session.currentPage
        return isPresenting && pages.indices.contains(index) ? index : nil
    }

    private func onPresentedPage(_ point: CGPoint) -> CGPoint {
        guard let index = presentedPage, effectiveScale > 0 else { return .zero }
        let frame = presentedFrame(index), local = contentView.convert(point, from: laser)
        return CGPoint(x: (local.x / bakedScale - frame.minX) / frame.width, y: (local.y / bakedScale - frame.minY) / frame.height)
    }

    private func mirrorLaser(_ event: LaserEvent) {
        ExternalDisplay.shared.laser(event, color: laser.color, by: self)
    }

    @objc private func secondScreenChanged() {
        mirrored = nil
        mirrorPresentation()
    }

    private func mirrorPresentation() {
        guard let index = presentedPage, effectiveScale > 0, let pixels = ExternalDisplay.shared.pixelSize(for: self) else { return }
        let frame = presentedFrame(index), area = readableArea
        let page = layout.solo == index ? Whiteboard.piece(of: pages[index], in: frame) : pages[index]
        let visible = CGRect(x: (scrollView.contentOffset.x + area.minX) / effectiveScale, y: (scrollView.contentOffset.y + area.minY) / effectiveScale,
                             width: area.width / effectiveScale, height: area.height / effectiveScale).intersection(frame)
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        ExternalDisplay.shared.setViewport(visible.isNull || visible.isEmpty ? whole : CGRect(
            x: (visible.minX - frame.minX) / frame.width, y: (visible.minY - frame.minY) / frame.height,
            width: visible.width / frame.width, height: visible.height / frame.height), by: self)
        let lifted = session.liftedTapes
        let liftedKey = page.hasItems ? page.items.filter { lifted.contains($0.id) }.map(\.id.uuidString).joined() : ""
        let key = "\(page.id)-\(page.thumbnailKey)-\(Int(pixels.width))x\(Int(pixels.height))-\(liftedKey)-\(page.inkRect)"
        guard key != mirrored else { return }
        mirrored = key
        let assets = document.package.assetsDirectory, titles = linkTitles
        let width = PresentationStage.renderWidth(pageSize: page.size, pixels: pixels)
        Task { [weak self] in
            guard let self else { return }
            let ink = await self.document.ink(page.id)
            let image = await Task.detached(priority: .userInitiated) {
                SharedSlide(image: PageRenderer.image(of: page, ink: ink, assets: assets, width: width, links: titles, lifted: lifted))
            }.value.image
            guard self.mirrored == key else { return }
            ExternalDisplay.shared.show(image, pageSize: page.size, by: self)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        [laserGesture, itemTap, itemHold, strokeHold, tapeTap, pasteHold].contains { $0 === gestureRecognizer || $0 === other }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === pasteHold { return inkLasso != nil }
        guard gestureRecognizer === lassoPan else { return true }
        if touch.type == .pencil || fingersCanLasso { return true }
        return isOnInkSelection(touch.location(in: contentView))
    }

    private func dropLaser() {
        guard isPresenting, laser.isTracking else { return }
        laser.clear()
        mirrorLaser(.cleared)
        laserGesture.isEnabled = false
        laserGesture.isEnabled = true
    }

    @objc private func toolChanged() {
        if let toolPicker {
            if !sameTool(toolPicker.selectedTool, toolbox.tool) { toolPicker.selectedTool = toolbox.tool }
            if toolPicker.isRulerActive != toolbox.isRulerActive { toolPicker.isRulerActive = toolbox.isRulerActive }
        }
        for canvas in allCanvases + pool {
            syncTool(canvas)
            setDrawingEnabled(canvas.isLoaded && !document.isReadOnly && !isLocked, canvas)
        }
        if toolbox.typesHandwriting { InkText.warmUp() }
        if !unreadWriting.isEmpty, !(toolbox.typesHandwriting && PencilGestures.writes(toolbox.tool)) { typeUnreadWriting() }
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        pencil(.setting(SettingsKey.pencilDoubleTap), preferred: UIPencilInteraction.preferredTapAction, at: tap.hoverPose?.location)
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended else { return }
        pencil(.setting(SettingsKey.pencilSqueeze), preferred: UIPencilInteraction.preferredSqueezeAction, at: squeeze.hoverPose?.location)
    }

    @objc private func scriptedSqueeze(_ gesture: UITapGestureRecognizer) {
        pencil(.palette, preferred: .ignore, at: gesture.location(in: view))
    }

    private func pencil(_ action: PencilAction, preferred: UIPencilPreferredAction, at point: CGPoint?) {
        guard view.window != nil, session.isActivePane(), !isModalShowing, textView == nil, !document.isReadOnly else { return }
        let mode = session.mode, writing = mode == .writing || mode == .focus
        switch action {
        case .system:
            guard writing else { return }
            switch preferred {
            case .switchEraser: toolbox.switchEraser()
            case .switchPrevious: toolbox.switchPrevious()
            case .showColorPalette, .showInkAttributes, .showContextualPalette: toggleDish(at: point)
            default: break
            }
        case .eraser:
            if writing { toolbox.switchEraser() }
        case .undo:
            if writing || mode == .selecting { undoProxy.undo() }
        case .selectInk:
            guard writing || mode == .selecting else { return }
            session.enter(writing ? .selecting : .writing)
            AccessibilityNotification.Announcement(writing ? String(localized: "Selecting ink. Draw round ink on any page, then drag it.")
                                                           : String(localized: "Back to writing")).post()
        case .toggleTools:
            if writing { session.toggleTools() }
        case .palette:
            if writing { toggleDish(at: point) }
        case .zoomWindow:
            if writing { session.setZoomWindow(!session.isZoomWindowOpen) }
        }
    }

    private func toggleDish(at point: CGPoint?) {
        if session.dish != nil { return session.dish = nil }
        session.dish = point ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        scrollView === self.scrollView ? contentView : nil
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        guard !isBaking else { return }
        updateWindow()
        if inkLasso != nil { publishInkSelection() }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        pendingPage = nil
        updateWindow()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        pendingPage = nil
        dropLaser()
        clearPasteSpot()
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        guard scrollView === self.scrollView else { return }
        pendingPage = nil
        dropLaser()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        guard !isBaking else { return }
        updateInsets()
        updateWindow()
        if inkLasso != nil { publishInkSelection() }
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        guard scrollView === self.scrollView else { return }
        guard !isBaking else { return }
        let pinch = scrollView.zoomScale
        guard abs(pinch - 1) > 0.001 else { return }
        let before = effectiveScale
        let offset = scrollView.contentOffset
        let pixel = 1 / max(traitCollection.displayScale, 1)
        scrollView.setContentOffset(offset, animated: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bake(zoom: zoom * pinch) { scale in
            let ratio = scale / before
            return CGPoint(x: (offset.x * ratio / pixel).rounded() * pixel, y: (offset.y * ratio / pixel).rounded() * pixel)
        }
        updateWindow(force: true)
        CATransaction.commit()
        if inkLasso != nil { publishInkSelection() }
    }
}
