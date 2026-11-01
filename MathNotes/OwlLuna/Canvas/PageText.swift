import UIKit

extension TextBox.Tint {
    var displayName: String {
        switch self {
        case .ink: String(localized: "Ink")
        case .tomato: String(localized: "Tomato")
        case .cobalt: String(localized: "Cobalt")
        case .moss: String(localized: "Moss")
        case .plum: String(localized: "Plum")
        }
    }

    /// Lighter on Charcoal and Chalkboard, so typed text stays readable there.
    func color(onDark: Bool) -> UIColor {
        switch self {
        case .ink: UIColor(hex: onDark ? 0xF7F1E3 : 0x1B2230)
        case .tomato: UIColor(hex: onDark ? 0xFF9A86 : 0xC9452F)
        case .cobalt: UIColor(hex: onDark ? 0xA6BBFF : 0x2F4DA0)
        case .moss: UIColor(hex: onDark ? 0xA9D6AD : 0x3D5A40)
        case .plum: UIColor(hex: onDark ? 0xE5B1DB : 0x5A2F52)
        }
    }
}

extension TextBox.Alignment {
    var displayName: String {
        switch self {
        case .leading: String(localized: "Left")
        case .center: String(localized: "Centre")
        case .trailing: String(localized: "Right")
        }
    }

    var symbol: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }

    var textAlignment: NSTextAlignment {
        switch self {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
    }
}

extension TextBox.Face {
    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .serif: String(localized: "Serif")
        case .mono: String(localized: "Mono")
        case .fraunces: "Fraunces"
        }
    }
}

extension TextBox.List {
    var displayName: String {
        switch self {
        case .bullet: String(localized: "Bullets")
        case .number: String(localized: "Numbers")
        case .check: String(localized: "Checklist")
        }
    }

    var symbol: String {
        switch self {
        case .bullet: "list.bullet"
        case .number: "list.number"
        case .check: "checklist"
        }
    }
}

extension TextBox.Highlight {
    /// The highlighter's tint of the same name, as it was when the app kept its own palette.
    /// The custom `ToolPreset.tints` table is gone, so the four values are spelled out here.
    private var tint: UInt32 {
        switch self {
        case .yellow: 0xFFD426FF
        case .green:  0x7ED98BFF
        case .pink:   0xFF8FB8FF
        case .blue:   0x7CC4FFFF
        }
    }

    var displayName: String {
        switch self {
        case .yellow: String(localized: "Yellow")
        case .green:  String(localized: "Light Green")
        case .pink:   String(localized: "Light Pink")
        case .blue:   String(localized: "Light Blue")
        }
    }

    /// Fainter on Charcoal and Chalkboard, so the light text over it stays readable there.
    func color(onDark: Bool) -> UIColor {
        ToolPreset.uiColor(tint).withAlphaComponent(onDark ? 0.4 : 0.55)
    }
}

/// Laying out and drawing typed text, the same way in the editor, thumbnails and exported PDFs. Thread-safe.
extension TextBox {
    static let sizes: [(name: String, points: CGFloat)] = [
        (String(localized: "Small"), 13), (String(localized: "Body"), 17), (String(localized: "Large"), 24), (String(localized: "Title"), 34),
    ]

    func font(scale: CGFloat = 1) -> UIFont {
        let size = fontSize * scale, weight: UIFont.Weight = isBold ? .bold : .regular
        let upright: UIFont = switch face {
        case .system: .systemFont(ofSize: size, weight: weight)
        case .serif: Self.system(.serif, size: size, weight: weight)
        case .mono: Self.system(.monospaced, size: size, weight: weight)
        case .fraunces: MathNotesFonts.text(size: size, bold: isBold) as UIFont
        }
        return isItalic ? Self.italic(upright, ownCut: face != .fraunces) : upright
    }

    private static func system(_ design: UIFontDescriptor.SystemDesign, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        return font.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: size) } ?? font
    }

    /// The face's own italic, or the upright leant over where it has none.
    private static func italic(_ font: UIFont, ownCut: Bool) -> UIFont {
        let descriptor = font.fontDescriptor
        if ownCut, let italic = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) {
            let cut = UIFont(descriptor: italic, size: font.pointSize)
            if cut.fontDescriptor.symbolicTraits.contains(.traitItalic) { return cut }
        }
        return UIFont(descriptor: descriptor.withMatrix(CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)), size: font.pointSize)
    }

    /// The text as it is measured and drawn, and where a checklist's boxes go in it.
    private struct Typeset {
        var text: NSAttributedString
        /// The tab that starts each item of a checklist, by line.
        var checks: [(line: Int, location: Int)] = []
        var font: UIFont
        /// Between a marker and the words.
        var gap: CGFloat = 0
    }

    /// A list's lines start with their marker and a tab across to the indent the rest of the line keeps to; a checklist's
    /// boxes are drawn in the room its tab leaves. With `markersOnly` the words are there but clear, for drawing under the
    /// editor's own; `editing` leaves the markers out and stands every line at the indent, as the editor holds the words.
    private func typeset(_ string: String, color: UIColor, highlight: UIColor? = nil, scale: CGFloat = 1, markersOnly: Bool = false,
                         editing: Bool = false) -> Typeset {
        let font = font(scale: scale)
        var words: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: markersOnly ? UIColor.clear : color]
        if !markersOnly, isUnderlined { words[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if !markersOnly, let highlight { words[.backgroundColor] = highlight }
        guard let list else {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment.textAlignment
            paragraph.lineBreakMode = .byWordWrapping
            words[.paragraphStyle] = paragraph
            let text = NSMutableAttributedString(string: string, attributes: words)
            if words.count > 3 { Self.plainNewlines(in: text) }
            return Typeset(text: text, font: font)
        }
        let lines = (string as NSString).components(separatedBy: "\n"), numbers = Self.numbers(of: lines)
        let side = Self.checkSide(font), gap = font.pointSize * 0.4
        let markers = lines.indices.map { index -> String? in
            guard let number = numbers[index] else { return nil }
            return switch list {
            case .bullet: "•"
            case .number: "\(number)."
            case .check: ""
            }
        }
        let widest = list == .check ? side : markers.compactMap { $0 }.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let indent = max(widest + gap, font.pointSize * 1.5)
        let tabs = list == .check ? [NSTextTab(textAlignment: .natural, location: indent)]
            : [NSTextTab(textAlignment: .right, location: indent - gap), NSTextTab(textAlignment: .natural, location: indent)]
        func paragraph(first: CGFloat) -> NSParagraphStyle {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .natural
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.firstLineHeadIndent = first
            paragraph.headIndent = indent
            paragraph.tabStops = tabs
            paragraph.defaultTabInterval = indent
            return paragraph
        }
        let item = paragraph(first: editing ? indent : 0), plain = paragraph(first: indent)
        let text = NSMutableAttributedString()
        var checks: [(line: Int, location: Int)] = []
        for (index, line) in lines.enumerated() {
            var look = words
            look[.paragraphStyle] = markers[index] == nil ? plain : item
            if list == .check, checked.contains(index), !markersOnly { look[.foregroundColor] = color.withAlphaComponent(0.5) }
            if let marker = markers[index], !editing {
                if list == .check { checks.append((index, text.length)) }
                text.append(NSAttributedString(string: list == .check ? "\t" : "\t\(marker)\t",
                                               attributes: [.font: font, .foregroundColor: color, .paragraphStyle: item]))
            }
            text.append(NSAttributedString(string: index < lines.count - 1 ? line + "\n" : line, attributes: look))
        }
        Self.plainNewlines(in: text)
        return Typeset(text: text, checks: checks, font: font, gap: gap)
    }

    /// The returns between lines are neither underlined nor washed.
    private static func plainNewlines(in text: NSMutableAttributedString) {
        let string = text.string as NSString
        var range = string.range(of: "\n")
        while range.location != NSNotFound {
            text.removeAttribute(.underlineStyle, range: range)
            text.removeAttribute(.backgroundColor, range: range)
            range = string.range(of: "\n", range: NSRange(location: NSMaxRange(range), length: string.length - NSMaxRange(range)))
        }
    }

    private static func checkSide(_ font: UIFont) -> CGFloat { font.capHeight * 1.12 }

    /// Each box of a checklist by line, and the room beside its first line where a tap ticks it, from the box's top
    /// left, at the scale it was set at.
    private func checkboxes(_ set: Typeset, width: CGFloat) -> [(line: Int, box: CGRect, room: CGRect)] {
        guard !set.checks.isEmpty else { return [] }
        let storage = NSTextStorage(attributedString: set.text), manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let side = Self.checkSide(set.font)
        return set.checks.map { check in
            let glyph = manager.glyphIndexForCharacter(at: check.location)
            let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = line.minY + manager.location(forGlyphAt: glyph).y
            let tab = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let x = tab.minX < 0.5 ? tab.maxX - set.gap - side : tab.minX + set.gap
            let box = CGRect(x: x, y: baseline - set.font.capHeight / 2 - side / 2, width: side, height: side)
            return (check.line, box, CGRect(x: tab.minX, y: line.minY, width: tab.width, height: line.height))
        }
    }

    private static func drawCheckbox(_ box: CGRect, ticked: Bool, color: UIColor, in ctx: CGContext) {
        let line = max(box.width * 0.1, 0.75), side = box.width
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(line)
        ctx.addPath(CGPath(roundedRect: box.insetBy(dx: line / 2, dy: line / 2), cornerWidth: side * 0.14, cornerHeight: side * 0.14, transform: nil))
        ctx.strokePath()
        if ticked {
            ctx.setLineWidth(line * 1.6)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addLines(between: [CGPoint(x: box.minX + side * 0.24, y: box.minY + side * 0.52), CGPoint(x: box.minX + side * 0.43, y: box.minY + side * 0.72),
                                   CGPoint(x: box.minX + side * 0.78, y: box.minY + side * 0.28)])
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// An empty box, or one ending in a return, is as tall as the line the caret sits on.
    func height(width: CGFloat) -> CGFloat {
        let measured = string.isEmpty || string.hasSuffix("\n") ? string + " " : string
        let bounds = typeset(measured, color: .black).text.boundingRect(with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
                                                                        options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return max(bounds.height, font().lineHeight).rounded(.up)
    }

    /// The width its longest line wants, for a box that hasn't been given one.
    func naturalWidth(limit: CGFloat) -> CGFloat {
        let bounds = typeset(string, color: .black).text.boundingRect(with: CGSize(width: limit, height: .greatestFiniteMagnitude),
                                                                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return min(bounds.width.rounded(.up) + 2, limit)
    }

    /// Draws in page points, in a y-down context; at a `scale`, in points that many times larger. With `markersOnly`
    /// only a list's bullets, numbers and boxes are drawn, where the editor's words leave room for them.
    func draw(in ctx: CGContext, rect: CGRect, onDark: Bool, scale: CGFloat = 1, markersOnly: Bool = false) {
        guard !string.isEmpty else { return }
        let color = tint.color(onDark: onDark)
        let set = typeset(string, color: color, highlight: highlight?.color(onDark: onDark), scale: scale, markersOnly: markersOnly)
        UIGraphicsPushContext(ctx)
        set.text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        UIGraphicsPopContext()
        for check in checkboxes(set, width: rect.width) {
            Self.drawCheckbox(check.box.offsetBy(dx: rect.minX, dy: rect.minY), ticked: checked.contains(check.line), color: color, in: ctx)
        }
    }

    /// The words as the editor's text view holds them, set as they are drawn.
    func editingText(scale: CGFloat, onDark: Bool) -> NSAttributedString {
        typeset(string, color: tint.color(onDark: onDark), highlight: highlight?.color(onDark: onDark), scale: scale, editing: true).text
    }

    /// What a new line typed into the editor's text view starts with.
    func typingAttributes(scale: CGFloat, onDark: Bool) -> [NSAttributedString.Key: Any] {
        var fresh = self
        fresh.checked = []
        return fresh.typeset("x", color: tint.color(onDark: onDark), highlight: highlight?.color(onDark: onDark), scale: scale, editing: true)
            .text.attributes(at: 0, effectiveRange: nil)
    }

    /// The line of a checklist whose box is at a point, in page points from the box's top left.
    func checkbox(at point: CGPoint, width: CGFloat) -> Int? {
        checkboxes(typeset(string, color: .black), width: width)
            .filter { $0.room.insetBy(dx: -6, dy: -2).contains(point) }
            .min { hypot($0.box.midX - point.x, $0.box.midY - point.y) < hypot($1.box.midX - point.x, $1.box.midY - point.y) }?.line
    }

    /// Where each box of a checklist is, by line, from the box's top left; at a `scale`, `width` and the boxes are in
    /// points that many times larger.
    func checkboxes(width: CGFloat, scale: CGFloat = 1) -> [(line: Int, rect: CGRect)] {
        checkboxes(typeset(string, color: .black, scale: scale), width: width).map { ($0.line, $0.box) }
    }
}

/// What a link is called: its own label, or the name of what it opens (a bookmark name or page number, a notebook's
/// title, a web address without its scheme).
struct LinkTitles: Sendable, Equatable {
    private var titles: [UUID: String] = [:]
    /// The library's notebooks by ID. Nil when they weren't looked up: then a link to a notebook uses the name it was made with.
    private var notebooks: [UUID: String]?

    init(pages: [NotebookPage] = [], notebooks: [UUID: String]? = nil) {
        for (index, page) in pages.enumerated() {
            titles[page.id] = page.bookmark.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Page \(index + 1)")
        }
        self.notebooks = notebooks
    }

    func resolves(_ link: PageLink) -> Bool {
        switch link.destination {
        case .page(let id): titles[id] != nil
        case .notebook(let id, _, _): notebooks.map { $0[id] != nil } ?? true
        case .web: true
        }
    }

    func title(for link: PageLink) -> String {
        guard link.label.isEmpty else { return link.label }
        switch link.destination {
        case .page(let id): return titles[id] ?? String(localized: "Missing page")
        case .notebook(let id, _, let name): return notebooks?[id] ?? (name.isEmpty ? String(localized: "Notebook") : name)
        case .web(let url): return WebAddress.display(url)
        }
    }
}

extension PageLink {
    /// What its tab looks like.
    enum Kind: Sendable { case page, notebook, web }

    var kind: Kind {
        switch destination {
        case .page: .page
        case .notebook: .notebook
        case .web: .web
        }
    }

    /// The link an exported PDF carries for something outside the document.
    var externalURL: URL? {
        switch destination {
        case .page: nil
        case .web(let url): url
        case .notebook(let id, let page, _): AppAction.url(forNotebook: id, page: page)
        }
    }
}

/// The index tab a link is drawn as. Thread-safe.
enum PageLinkArt {
    static let height: CGFloat = 30
    private static let ink = UIColor(hex: 0x1B2230)
    private static let cream = UIColor(hex: 0xF7F1E3)
    private static let mustard = UIColor(hex: 0xE8B023)
    private static let sage = UIColor(hex: 0xA9D6AD)
    private static let sky = UIColor(hex: 0xA6BBFF)
    private static let faded = UIColor(hex: 0xB9B4A8)

    private static func label(_ title: String, size: CGFloat, color: UIColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color,
                                                              .paragraphStyle: paragraph])
    }

    /// The size a new link is placed at, wide enough for its title.
    static func size(for title: String) -> CGSize {
        let text = label(title, size: 14, color: ink).size().width.rounded(.up)
        return CGSize(width: min(max(height + 8 + text + 12, 84), 320), height: height)
    }

    /// An arrow for a page, a book for another notebook, an arrow leaving the page for the web.
    private static func glyph(_ kind: PageLink.Kind, in tab: CGRect, unit: CGFloat, ctx: CGContext) {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tab.minX + x * unit, y: tab.minY + y * unit) }
        switch kind {
        case .page:
            ctx.addLines(between: [point(9.5, 15), point(21, 15)])
            ctx.addLines(between: [point(16, 10), point(21, 15), point(16, 20)])
        case .web:
            ctx.addLines(between: [point(10.5, 19.5), point(19.5, 10.5)])
            ctx.addLines(between: [point(12.5, 10.5), point(19.5, 10.5), point(19.5, 17.5)])
        case .notebook:
            ctx.addPath(CGPath(roundedRect: CGRect(x: tab.minX + 9.5 * unit, y: tab.minY + 8 * unit, width: 11 * unit, height: 14 * unit),
                               cornerWidth: 1.5 * unit, cornerHeight: 1.5 * unit, transform: nil))
            ctx.addLines(between: [point(13, 8), point(13, 22)])
        }
        ctx.strokePath()
    }

    /// Draws in a y-down context. The tab is as wide as the chip is tall; the title shrinks before it is cut short.
    static func draw(title: String, kind: PageLink.Kind = .page, resolved: Bool, in ctx: CGContext, rect: CGRect) {
        let unit = rect.height / height
        let chip = CGPath(roundedRect: rect.insetBy(dx: unit, dy: unit), cornerWidth: 6 * unit, cornerHeight: 6 * unit, transform: nil)
        ctx.saveGState()
        ctx.addPath(chip)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2 * unit)
        ctx.strokePath()
        ctx.addPath(chip)
        ctx.clip()
        ctx.setFillColor(cream.cgColor)
        ctx.fill(rect)
        let tab = CGRect(x: rect.minX, y: rect.minY, width: rect.height, height: rect.height)
        let tint = switch kind {
        case .page: mustard
        case .notebook: sage
        case .web: sky
        }
        ctx.setFillColor((resolved ? tint : faded).cgColor)
        ctx.fill(tab)
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth((kind == .notebook ? 1.8 : 2.2) * unit)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        glyph(kind, in: tab, unit: unit, ctx: ctx)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(chip)
        ctx.setStrokeColor(ink.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(unit)
        ctx.strokePath()
        ctx.restoreGState()

        let room = rect.maxX - tab.maxX - 18 * unit
        guard room > 4 else { return }
        var size = 14 * unit
        let natural = label(title, size: size, color: ink).size().width
        if natural > room { size *= max(room / natural, 0.7) }
        let text = label(title, size: size, color: resolved ? ink : ink.withAlphaComponent(0.6))
        let line = text.size().height
        UIGraphicsPushContext(ctx)
        text.draw(with: CGRect(x: tab.maxX + 8 * unit, y: rect.midY - line / 2, width: room, height: line),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        UIGraphicsPopContext()
    }
}

extension PageItem {
    /// The upright rectangle that holds the item however it is turned.
    var boundingBox: CGRect {
        let w = abs(size.width * cos(rotation)) + abs(size.height * sin(rotation))
        let h = abs(size.width * sin(rotation)) + abs(size.height * cos(rotation))
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    }
}
