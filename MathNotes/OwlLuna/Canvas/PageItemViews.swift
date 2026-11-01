import UIKit

/// One picture, sticker, text box or link in the editor, under the canvas, or a strip of study tape over it.
/// Its frame follows the page's baked scale.
final class PageItemView: UIView {
    private(set) var item: PageItem
    private let assets: URL
    private var loadedFile: String?
    /// A picture is shown by its own layer and nothing is drawn behind it, so it has no bitmap the size of the item.
    private let picture = CALayer()
    /// Where a sticker, text box, link or tape is drawn. A picture has none.
    private var art: ItemArtView?
    private var onDark = false
    private var linkTitle = ""
    private var linkResolved = true
    private var isLifted = false
    var onActivate: ((UUID) -> Void)?
    /// Ticks a line of a checklist, or takes its tick off, for VoiceOver.
    var onTick: ((UUID, Int) -> Void)?

    init(item: PageItem, assets: URL) {
        self.item = item
        self.assets = assets
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        picture.contentsGravity = .resize
        layer.addSublayer(picture)
        isAccessibilityElement = true
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ newItem: PageItem, onDark: Bool = false, links: LinkTitles = LinkTitles(), lifted: Bool = false) {
        let title = newItem.link.map(links.title(for:)) ?? "", resolved = newItem.link.map(links.resolves) ?? true
        let changed = newItem.content != item.content || onDark != self.onDark || title != linkTitle || resolved != linkResolved || lifted != isLifted
        item = newItem
        self.onDark = onDark
        linkTitle = title
        linkResolved = resolved
        isLifted = lifted
        // Tape takes the touches that land on it, so a tap lifts it and nothing is written on it.
        isUserInteractionEnabled = newItem.isOverInk
        if changed { reload() }
    }

    func layout(scale: CGFloat) {
        transform = .identity
        bounds = CGRect(x: 0, y: 0, width: item.size.width * scale, height: item.size.height * scale)
        center = CGPoint(x: item.center.x * scale, y: item.center.y * scale)
        transform = CGAffineTransform(rotationAngle: item.rotation)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.frame = bounds
        picture.contentsRect = item.crop ?? PageItem.wholePicture
        CATransaction.commit()
        art?.frame = bounds
        art?.fitScale()
    }

    /// The picture as shown, the whole file, for cropping it without reading it again.
    var shownPicture: Any? { picture.contents }

    /// Pixels per point for drawn art: the screen's, until its bitmap would pass about a screenful of pixels.
    static func drawingScale(for size: CGSize, screen: CGFloat) -> CGFloat {
        let budget: CGFloat = 2400 * 2400, side: CGFloat = 8192
        return min(screen, (budget / max(size.width * size.height, 1)).squareRoot(), side / max(size.width, size.height, 1))
    }

    private func reload() {
        accessibilityHint = String(localized: "Touch and hold to move or resize")
        accessibilityTraits = .image
        accessibilityValue = nil
        accessibilityCustomActions = nil
        isAccessibilityElement = true
        if item.assetFile == nil {
            picture.contents = nil
            loadedFile = nil
            showArt()
        } else {
            art?.removeFromSuperview()
            art = nil
        }
        switch item.content {
        case .sticker:
            accessibilityLabel = item.sticker.map { String(localized: "Sticker, \($0.displayName)") } ?? String(localized: "Sticker")
        case .image(let file):
            accessibilityLabel = item.source == nil ? String(localized: "Picture") : String(localized: "Sticker")
            guard file != loadedFile else { return }
            loadedFile = file
            let assets = assets
            Task { [weak self] in
                let image = await Task.detached(priority: .userInitiated) { PageItemRenderer.image(file, assets: assets).map(SharedImage.init) }.value
                guard let self, self.loadedFile == file else { return }
                self.picture.contents = image?.image
            }
        case .text(let box):
            accessibilityLabel = box.string
            accessibilityTraits = .staticText
            guard box.list == .check else { break }
            let lines = box.lines.enumerated().filter { TextBox.isItem($0.element) }
            accessibilityLabel = lines.map { box.checked.contains($0.offset) ? String(localized: "\($0.element), ticked") : $0.element }
                .joined(separator: "\n")
            accessibilityCustomActions = lines.map { line, text in
                let name = box.checked.contains(line) ? String(localized: "Untick \(text)") : String(localized: "Tick \(text)")
                return UIAccessibilityCustomAction(name: name) { [weak self] _ in
                    guard let self, let onTick = self.onTick else { return false }
                    onTick(self.item.id, line)
                    return true
                }
            }
        case .link(let link):
            accessibilityTraits = .link
            switch link.kind {
            case .page:
                accessibilityLabel = linkResolved ? String(localized: "Link to \(linkTitle)") : String(localized: "Link to a page that was deleted")
                accessibilityHint = String(localized: "Opens the page. Touch and hold to move or resize.")
            case .notebook:
                accessibilityLabel = linkResolved ? String(localized: "Link to the notebook \(linkTitle)") : String(localized: "Link to a notebook that was deleted")
                accessibilityHint = String(localized: "Opens the notebook. Touch and hold to move or resize.")
            case .web:
                accessibilityLabel = String(localized: "Web link, \(linkTitle)")
                accessibilityHint = String(localized: "Opens the address in your browser. Touch and hold to move or resize.")
            }
        case .tape:
            accessibilityLabel = String(localized: "Study tape")
            accessibilityValue = isLifted ? String(localized: "Lifted") : String(localized: "Covering")
            accessibilityTraits = .button
            accessibilityHint = String(localized: "Lifts the tape or puts it back. Touch and hold to move or resize.")
        case .unknown:
            isAccessibilityElement = false
        }
    }

    private func showArt() {
        if art == nil {
            let art = ItemArtView(frame: bounds)
            art.paint = { [weak self] ctx, rect in self?.drawArt(in: ctx, rect: rect) }
            addSubview(art)
            self.art = art
            art.fitScale()
        }
        art?.setNeedsDisplay()
    }

    private func drawArt(in ctx: CGContext, rect: CGRect) {
        switch item.content {
        case .sticker:
            item.sticker?.draw(in: ctx, rect: rect)
        case .text(let box):
            let scale = rect.width / max(item.size.width, 1)
            ctx.scaleBy(x: scale, y: scale)
            box.draw(in: ctx, rect: CGRect(origin: .zero, size: item.size), onDark: onDark)
        case .link(let link):
            PageLinkArt.draw(title: linkTitle, kind: link.kind, resolved: linkResolved, in: ctx, rect: rect)
        case .tape(let color):
            TapeArt.draw(color, lifted: isLifted, in: ctx, rect: rect)
        case .image, .unknown:
            break
        }
    }

    override func accessibilityActivate() -> Bool {
        onActivate?(item.id)
        return onActivate != nil
    }
}

/// The bitmap an item is drawn into, at no more pixels than `PageItemView.drawingScale` allows.
private final class ItemArtView: UIView {
    var paint: (CGContext, CGRect) -> Void = { _, _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        fitScale()
    }

    func fitScale() {
        let screen = window?.traitCollection.displayScale ?? traitCollection.displayScale
        guard screen > 0 else { return }
        let wanted = PageItemView.drawingScale(for: bounds.size, screen: screen)
        if contentScaleFactor != wanted { contentScaleFactor = wanted }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        paint(ctx, bounds)
    }
}

/// A list's bullets, numbers and boxes under the words of a text box being typed in, where its text view leaves room.
final class TextMarkersView: UIView {
    private var box: TextBox?
    private var onDark = false
    private var scale: CGFloat = 1

    init() {
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ box: TextBox?, onDark: Bool, scale: CGFloat) {
        isHidden = box == nil
        guard box != self.box || onDark != self.onDark || scale != self.scale else { return }
        self.box = box
        self.onDark = onDark
        self.scale = scale
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let box, let ctx = UIGraphicsGetCurrentContext() else { return }
        box.draw(in: ctx, rect: bounds, onDark: onDark, scale: scale, markersOnly: true)
    }
}

/// The stitched outline and handle round the selected item. It sits above the canvas, so touches on the item move
/// it instead of drawing. Every change is reported as a whole item; `final` marks the end of a gesture.
final class ItemSelectionView: UIView, UIGestureRecognizerDelegate {
    static let outset: CGFloat = 8
    private static let handleSize: CGFloat = 44

    private(set) var item: PageItem
    var pageSize: CGSize
    var scale: CGFloat = 1
    var onChange: ((PageItem, _ final: Bool) -> Void)?
    /// Where it was tapped, in page points from the item's top left.
    var onTap: ((CGPoint) -> Void)?
    /// While its text is being typed the outline stays and the handles step aside.
    var isEditing = false {
        didSet {
            isUserInteractionEnabled = !isEditing
            show(item)
        }
    }

    private let outline = CAShapeLayer()
    private let underline = CAShapeLayer()
    private let handle = UIView()
    private let knob = UIImageView()
    private let side = UIView()
    private let grip = UIView()
    private var base: PageItem?
    private var pinch: CGFloat = 1
    private var twist: CGFloat = 0
    private var handleStart: CGPoint = .zero
    private(set) lazy var recognizers: [UIGestureRecognizer] = [
        UIPanGestureRecognizer(target: self, action: #selector(dragged)),
        UIPinchGestureRecognizer(target: self, action: #selector(pinched)),
        UIRotationGestureRecognizer(target: self, action: #selector(twisted)),
    ]
    private(set) lazy var handlePan = UIPanGestureRecognizer(target: self, action: #selector(dragHandle))
    private lazy var sidePan = UIPanGestureRecognizer(target: self, action: #selector(dragSide))

    init(item: PageItem, pageSize: CGSize) {
        self.item = item
        self.pageSize = pageSize
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = false
        for (layer, color, width) in [(underline, UIColor.ink.withAlphaComponent(0.55), 3.5 as CGFloat), (outline, UIColor.mustard, 2)] {
            layer.fillColor = nil
            layer.strokeColor = color.cgColor
            layer.lineWidth = width
            self.layer.addSublayer(layer)
        }
        outline.lineDashPattern = [7, 5]
        outline.lineCap = .round
        handle.frame = CGRect(x: 0, y: 0, width: Self.handleSize, height: Self.handleSize)
        knob.frame = handle.bounds.insetBy(dx: 8, dy: 8)
        knob.backgroundColor = .surface
        knob.layer.cornerRadius = knob.bounds.width / 2
        knob.layer.borderWidth = 1
        knob.layer.borderColor = UIColor.ink.withAlphaComponent(0.35).cgColor
        knob.image = UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        knob.tintColor = .ink
        knob.contentMode = .center
        handle.addSubview(knob)
        addSubview(handle)
        handle.addGestureRecognizer(handlePan)
        handle.isAccessibilityElement = true
        handle.accessibilityLabel = String(localized: "Resize and rotate")
        handle.accessibilityTraits = .adjustable
        (recognizers[0] as? UIPanGestureRecognizer)?.maximumNumberOfTouches = 1
        for recognizer in recognizers {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
        handlePan.delegate = self
        side.frame = CGRect(x: 0, y: 0, width: Self.handleSize, height: Self.handleSize)
        grip.frame = CGRect(x: (Self.handleSize - 10) / 2, y: (Self.handleSize - 28) / 2, width: 10, height: 28)
        grip.backgroundColor = .surface
        grip.layer.cornerRadius = 2
        grip.layer.borderWidth = 1
        grip.layer.borderColor = UIColor.ink.withAlphaComponent(0.35).cgColor
        side.addSubview(grip)
        addSubview(side)
        side.addGestureRecognizer(sidePan)
        side.isAccessibilityElement = true
        side.accessibilityLabel = String(localized: "Change width")
        side.accessibilityTraits = .adjustable
        sidePan.delegate = self
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        onTap?(CGPoint(x: (point.x - Self.outset) / max(scale, 0.01), y: (point.y - Self.outset) / max(scale, 0.01)))
    }

    required init?(coder: NSCoder) { fatalError() }

    var isChanging: Bool { base != nil }

    func show(_ newItem: PageItem) {
        item = newItem
        transform = .identity
        let outset = Self.outset
        bounds = CGRect(x: 0, y: 0, width: item.size.width * scale + outset * 2, height: item.size.height * scale + outset * 2)
        center = CGPoint(x: item.center.x * scale, y: item.center.y * scale)
        transform = CGAffineTransform(rotationAngle: item.rotation)
        let path = UIBezierPath(roundedRect: bounds.insetBy(dx: outset / 2, dy: outset / 2), cornerRadius: 4).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.path = path
        underline.path = path
        outline.strokeColor = UIColor.mustard.resolvedColor(with: traitCollection).cgColor
        underline.strokeColor = UIColor.ink.resolvedColor(with: traitCollection).withAlphaComponent(0.55).cgColor
        CATransaction.commit()
        // A text box or a strip of tape keeps its right edge for the width grip, so its corner handle moves to the left.
        let hasGrip = item.text != nil || item.tape != nil
        handle.center = CGPoint(x: hasGrip ? bounds.minX + outset / 2 : bounds.maxX - outset / 2, y: bounds.maxY - outset / 2)
        handle.isHidden = isEditing
        side.center = CGPoint(x: bounds.maxX - outset / 2, y: bounds.midY)
        side.isHidden = isEditing || !hasGrip
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point) || handle.frame.contains(point) || (!side.isHidden && side.frame.contains(point))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        recognizers.contains(gestureRecognizer) && recognizers.contains(other)
    }

    /// The page's own scroll and zoom wait for these, so two fingers on the item resize it and don't zoom the page.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other.view is UIScrollView
    }

    private func begin() {
        if base == nil {
            base = item
            pinch = 1
            twist = 0
        }
    }

    private func report(_ changed: PageItem, state: UIGestureRecognizer.State) {
        var changed = changed
        changed.center.x = min(max(changed.center.x, 0), pageSize.width)
        changed.center.y = min(max(changed.center.y, 0), pageSize.height)
        let others = (recognizers + [handlePan, sidePan]).contains { $0.state == .began || $0.state == .changed }
        switch state {
        case .changed:
            onChange?(changed, false)
        case .ended where others:
            onChange?(changed, false)
        case .ended:
            base = nil
            onChange?(changed, true)
        case .cancelled, .failed:
            guard !others, let base else { return }
            self.base = nil
            onChange?(base, false)
        default:
            break
        }
    }

    private func composed(from base: PageItem, translation: CGPoint = .zero) -> PageItem {
        var changed = base.scaled(by: pinch, limit: max(pageSize.width, pageSize.height) * 1.5)
        changed.rotation = Self.snapped(base.rotation + twist)
        changed.center = CGPoint(x: item.center.x + translation.x, y: item.center.y + translation.y)
        return changed
    }

    /// Settles on the quarter turns when within three degrees of one.
    static func snapped(_ angle: CGFloat) -> CGFloat {
        let quarter = CGFloat.pi / 2
        let nearest = (angle / quarter).rounded() * quarter
        return abs(angle - nearest) < 3 * .pi / 180 ? nearest : angle
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        if gesture.state == .began { begin() }
        guard let base else { return }
        let moved = gesture.translation(in: superview)
        gesture.setTranslation(.zero, in: superview)
        report(composed(from: base, translation: CGPoint(x: moved.x / max(scale, 0.01), y: moved.y / max(scale, 0.01))), state: gesture.state)
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { begin() }
        guard let base else { return }
        pinch = gesture.scale
        report(composed(from: base), state: gesture.state)
    }

    @objc private func twisted(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .began { begin() }
        guard let base else { return }
        twist = gesture.rotation
        report(composed(from: base), state: gesture.state)
    }

    @objc private func dragHandle(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        let point = gesture.location(in: superview)
        let vector = CGPoint(x: point.x - center.x, y: point.y - center.y)
        if gesture.state == .began {
            begin()
            handleStart = vector
        }
        guard let base else { return }
        let start = max(hypot(handleStart.x, handleStart.y), 1)
        pinch = hypot(vector.x, vector.y) / start
        twist = atan2(vector.y, vector.x) - atan2(handleStart.y, handleStart.x)
        report(composed(from: base), state: gesture.state)
    }

    /// The side grip changes the width: a text box wraps again and grows downwards, tape gets longer.
    @objc private func dragSide(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        if gesture.state == .began { begin() }
        guard let base else { return }
        let moved = gesture.translation(in: superview)
        let along = (moved.x * cos(base.rotation) + moved.y * sin(base.rotation)) / max(scale, 0.01)
        let width = min(max(base.size.width + along, 40), pageSize.width * 1.5)
        report(base.resized(to: CGSize(width: width, height: base.text?.height(width: width) ?? base.size.height)), state: gesture.state)
    }
}

/// Crop mode for a selected picture: all of it, what is cut off dimmed, and edges and corners to drag.
final class ItemCropView: UIView, UIGestureRecognizerDelegate {
    enum Edge: CaseIterable { case top, left, bottom, right }
    private enum Grab { case edges(Set<Edge>), slide }

    private static let outset: CGFloat = 22
    static let step: CGFloat = 0.05

    /// The picture as it was when cropping began.
    let item: PageItem
    private(set) var crop: CGRect
    var scale: CGFloat {
        didSet { if scale != oldValue { layoutPicture() } }
    }
    /// Reports the crop, in the picture's unit square, as each drag ends.
    var onChange: ((CGRect) -> Void)?

    private let picture = CALayer()
    private let shade = CAShapeLayer()
    private let underline = CAShapeLayer()
    private let outline = CAShapeLayer()
    private let knobs: [UIView] = (0..<8).map { _ in UIView() }
    private var grab: Grab?
    private var start = PageItem.wholePicture
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(dragged))
    private lazy var edges = Edge.allCases.map { CropEdgeElement(edge: $0, view: self) }

    init(item: PageItem, picture contents: Any?, assets: URL, scale: CGFloat) {
        self.item = item
        crop = item.crop ?? PageItem.wholePicture
        self.scale = scale
        super.init(frame: .zero)
        backgroundColor = .clear
        picture.contentsGravity = .resize
        picture.contents = contents
        shade.fillRule = .evenOdd
        shade.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
        for (line, width) in [(underline, 3.5 as CGFloat), (outline, 2)] {
            line.fillColor = nil
            line.lineWidth = width
        }
        for sublayer in [picture, shade, underline, outline] { layer.addSublayer(sublayer) }
        for knob in knobs {
            knob.backgroundColor = .surface
            knob.layer.cornerRadius = 2
            knob.layer.borderWidth = 1
            knob.isUserInteractionEnabled = false
            addSubview(knob)
        }
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)
        isAccessibilityElement = false
        accessibilityElements = edges
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ItemCropView, _) in view.showCrop() }
        if contents == nil, case .image(let file) = item.content {
            Task { [weak self] in
                let image = await Task.detached(priority: .userInitiated) { PageItemRenderer.image(file, assets: assets).map(SharedImage.init) }.value
                self?.picture.contents = image?.image
            }
        }
        layoutPicture()
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        crop = PageItem.wholePicture
        showCrop()
        onChange?(crop)
    }

    /// How much of the picture is cut off past an edge, from 0 to 1.
    func cutOff(_ edge: Edge) -> CGFloat {
        switch edge {
        case .top: crop.minY
        case .left: crop.minX
        case .bottom: 1 - crop.maxY
        case .right: 1 - crop.maxX
        }
    }

    /// Moves an edge in by `amount` of the picture, or out for a negative amount.
    func nudge(_ edge: Edge, by amount: CGFloat) {
        let delta = switch edge {
        case .top: CGPoint(x: 0, y: amount)
        case .left: CGPoint(x: amount, y: 0)
        case .bottom: CGPoint(x: 0, y: -amount)
        case .right: CGPoint(x: -amount, y: 0)
        }
        crop = Self.moved(crop, edges: [edge], by: delta, least: least)
        showCrop()
        onChange?(crop)
    }

    /// The crop with `edges` moved by `delta` of the picture, kept inside it and no smaller than `least`.
    static func moved(_ crop: CGRect, edges: Set<Edge>, by delta: CGPoint, least: CGSize) -> CGRect {
        var minX = crop.minX, minY = crop.minY, maxX = crop.maxX, maxY = crop.maxY
        if edges.contains(.left) { minX = min(max(minX + delta.x, 0), maxX - least.width) }
        if edges.contains(.right) { maxX = max(min(maxX + delta.x, 1), minX + least.width) }
        if edges.contains(.top) { minY = min(max(minY + delta.y, 0), maxY - least.height) }
        if edges.contains(.bottom) { maxY = max(min(maxY + delta.y, 1), minY + least.height) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The same crop over another part of the picture, never past its edges.
    static func slid(_ crop: CGRect, by delta: CGPoint) -> CGRect {
        crop.offsetBy(dx: min(max(delta.x, -crop.minX), 1 - crop.maxX), dy: min(max(delta.y, -crop.minY), 1 - crop.maxY))
    }

    /// No side smaller than a fingertip can grab, unless the whole picture is.
    private var least: CGSize {
        let whole = item.cropped(to: nil).size
        return CGSize(width: min(PageItem.minimumSide / max(whole.width, 1), 1), height: min(PageItem.minimumSide / max(whole.height, 1), 1))
    }

    private var pictureFrame: CGRect { bounds.insetBy(dx: Self.outset, dy: Self.outset) }

    private var keptFrame: CGRect {
        let frame = pictureFrame
        return CGRect(x: frame.minX + crop.minX * frame.width, y: frame.minY + crop.minY * frame.height,
                      width: crop.width * frame.width, height: crop.height * frame.height)
    }

    private func layoutPicture() {
        let whole = item.cropped(to: nil)
        transform = .identity
        bounds = CGRect(x: 0, y: 0, width: whole.size.width * scale + Self.outset * 2, height: whole.size.height * scale + Self.outset * 2)
        center = CGPoint(x: whole.center.x * scale, y: whole.center.y * scale)
        transform = CGAffineTransform(rotationAngle: item.rotation)
        showCrop()
    }

    private func showCrop() {
        let frame = pictureFrame, kept = keptFrame
        let dimmed = CGMutablePath()
        dimmed.addRect(frame)
        dimmed.addRect(kept)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.frame = frame
        shade.path = dimmed
        underline.path = CGPath(rect: kept, transform: nil)
        outline.path = underline.path
        outline.strokeColor = UIColor.mustard.resolvedColor(with: traitCollection).cgColor
        underline.strokeColor = UIColor.ink.resolvedColor(with: traitCollection).withAlphaComponent(0.55).cgColor
        CATransaction.commit()
        let corners = [CGPoint(x: kept.minX, y: kept.minY), CGPoint(x: kept.maxX, y: kept.minY), CGPoint(x: kept.minX, y: kept.maxY), CGPoint(x: kept.maxX, y: kept.maxY)]
        let sides = [CGPoint(x: kept.midX, y: kept.minY), CGPoint(x: kept.minX, y: kept.midY), CGPoint(x: kept.midX, y: kept.maxY), CGPoint(x: kept.maxX, y: kept.midY)]
        let border = UIColor.ink.resolvedColor(with: traitCollection).withAlphaComponent(0.35).cgColor
        for (index, knob) in knobs.enumerated() {
            let corner = index < 4, across = index % 2 == 0
            knob.bounds.size = corner ? CGSize(width: 14, height: 14) : across ? CGSize(width: 28, height: 10) : CGSize(width: 10, height: 28)
            knob.center = corner ? corners[index] : sides[index - 4]
            knob.layer.borderColor = border
        }
        for element in edges {
            let reach = Self.outset
            element.accessibilityFrameInContainerSpace = switch element.edge {
            case .top: CGRect(x: kept.minX, y: kept.minY - reach, width: kept.width, height: reach * 2)
            case .bottom: CGRect(x: kept.minX, y: kept.maxY - reach, width: kept.width, height: reach * 2)
            case .left: CGRect(x: kept.minX - reach, y: kept.minY, width: reach * 2, height: kept.height)
            case .right: CGRect(x: kept.maxX - reach, y: kept.minY, width: reach * 2, height: kept.height)
            }
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        keptFrame.insetBy(dx: -Self.outset, dy: -Self.outset).contains(point)
    }

    /// The page's own scroll and zoom wait for the drag, so a touch on the crop moves the crop.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other.view is UIScrollView
    }

    /// Near an edge moves it, near a corner both of its edges, and further in the crop slides over the picture.
    private func grab(at point: CGPoint) -> Grab {
        let kept = keptFrame, reachX = min(Self.outset, kept.width / 3), reachY = min(Self.outset, kept.height / 3)
        var edges: Set<Edge> = []
        if point.x < kept.minX + reachX { edges.insert(.left) } else if point.x > kept.maxX - reachX { edges.insert(.right) }
        if point.y < kept.minY + reachY { edges.insert(.top) } else if point.y > kept.maxY - reachY { edges.insert(.bottom) }
        return edges.isEmpty ? .slide : .edges(edges)
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        let frame = pictureFrame
        guard frame.width > 0, frame.height > 0 else { return }
        let moved = gesture.translation(in: self)
        switch gesture.state {
        case .began:
            let point = gesture.location(in: self)
            grab = grab(at: CGPoint(x: point.x - moved.x, y: point.y - moved.y))
            start = crop
            fallthrough
        case .changed:
            let delta = CGPoint(x: moved.x / frame.width, y: moved.y / frame.height)
            switch grab {
            case .edges(let edges): crop = Self.moved(start, edges: edges, by: delta, least: least)
            case .slide: crop = Self.slid(start, by: delta)
            case nil: return
            }
            showCrop()
        case .ended:
            grab = nil
            onChange?(crop)
        case .cancelled, .failed:
            grab = nil
            crop = start
            showCrop()
        default:
            break
        }
    }
}

/// One edge of a crop for VoiceOver: swiping up cuts off more of the picture there, swiping down less.
private final class CropEdgeElement: UIAccessibilityElement {
    let edge: ItemCropView.Edge
    private weak var view: ItemCropView?

    init(edge: ItemCropView.Edge, view: ItemCropView) {
        self.edge = edge
        self.view = view
        super.init(accessibilityContainer: view)
        accessibilityTraits = .adjustable
        accessibilityIdentifier = "page.crop.\(edge)"
        accessibilityLabel = switch edge {
        case .top: String(localized: "Top Edge")
        case .left: String(localized: "Left Edge")
        case .bottom: String(localized: "Bottom Edge")
        case .right: String(localized: "Right Edge")
        }
    }

    override var accessibilityValue: String? {
        get { view.map { String(localized: "\(Double($0.cutOff(edge)).formatted(.percent.precision(.fractionLength(0)))) cut off") } }
        set {}
    }

    override func accessibilityIncrement() { view?.nudge(edge, by: ItemCropView.step) }
    override func accessibilityDecrement() { view?.nudge(edge, by: -ItemCropView.step) }
}
