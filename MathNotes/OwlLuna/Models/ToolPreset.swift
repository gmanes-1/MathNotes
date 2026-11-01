import UIKit
import PencilKit
import Observation

// MARK: - ToolPreset

/// A pen in the tray: a PencilKit ink type, its colour (with opacity in the alpha byte), and its width.
struct ToolPreset: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var ink: String
    /// Packed RGBa. The alpha byte is the pen's opacity.
    var color: UInt32
    var width: Double

    init(id: UUID = UUID(), ink: PKInkingTool.InkType, color: UInt32, width: Double) {
        self.id = id
        self.ink = ink.rawValue
        self.color = color
        self.width = width
    }

    init(id: UUID = UUID(), kind: PKInkingTool.InkType) {
        self.id = id
        self.ink = kind.rawValue
        self.color = Self.bytes(of: .black)
        self.width = Double(kind.defaultWidth)
    }

    init?(_ tool: PKTool) {
        guard let inking = tool as? PKInkingTool else { return nil }
        self.init(ink: inking.inkType, color: Self.bytes(of: inking.color), width: inking.width)
    }

    static func bytes(of color: UIColor) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
             .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return byte(red) << 24 | byte(green) << 16 | byte(blue) << 8 | byte(alpha)
    }

    var inkType: PKInkingTool.InkType? { PKInkingTool.InkType(rawValue: ink) }

    // MARK: Colour and opacity

    static let leastOpacity = 0.1

    var tint: UInt32 { color | 0xFF }

    var opacity: Double {
        get { Double(color & 0xFF) / 255 }
        set { color = color & 0xFFFF_FF00 | UInt32((min(max(newValue, Self.leastOpacity), 1) * 255).rounded()) }
    }

    mutating func setTint(_ tint: UInt32) {
        color = tint & 0xFFFF_FF00 | color & 0xFF
    }

    var opacityName: String { opacity.formatted(.percent.precision(.fractionLength(0))) }

    var uiColor: UIColor { Self.uiColor(color) }

    static func uiColor(_ color: UInt32) -> UIColor {
        UIColor(red:   CGFloat(color >> 24 & 0xFF) / 255,
                green: CGFloat(color >> 16 & 0xFF) / 255,
                blue:  CGFloat(color >>  8 & 0xFF) / 255,
                alpha: CGFloat(color & 0xFF) / 255)
    }

    // MARK: Widths

    static func widthRange(of ink: PKInkingTool.InkType) -> ClosedRange<Double> {
        let valid = ink.validWidthRange
        return Double(valid.lowerBound)...Double(valid.upperBound)
    }

    static func clamped(_ width: Double, to range: ClosedRange<Double>) -> Double {
        min(max(width, range.lowerBound), range.upperBound)
    }

    var widthRange: ClosedRange<Double> { Self.widthRange(of: inkType ?? .pen) }

    var widthFraction: Double {
        let range = widthRange
        guard range.upperBound > range.lowerBound else { return 0.5 }
        return min(max((width - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var widthTravel: Double { widthFraction }

    static func width(at fraction: Double, of ink: PKInkingTool.InkType) -> Double {
        let range = widthRange(of: ink), t = min(max(fraction, 0), 1)
        let width = range.lowerBound + (range.upperBound - range.lowerBound) * t
        return clamped((width * 100).rounded() / 100, to: range)
    }

    var tool: PKInkingTool? {
        guard let inkType else { return nil }
        let valid = inkType.validWidthRange
        let final = min(max(CGFloat(width), valid.lowerBound), valid.upperBound)
        return PKInkingTool(inkType, color: uiColor, width: final)
    }

    // MARK: Names

    var kindName: String { inkType.map(Self.name(of:)) ?? String(localized: "Pen") }
    var symbol: String { inkType.map(Self.symbol(of:)) ?? "pencil.tip" }
    var name: String { String(localized: "\(kindName), \(colorName)") }

    static func name(of ink: PKInkingTool.InkType) -> String {
        switch ink {
        case .pen: String(localized: "Pen")
        case .pencil: String(localized: "Pencil")
        case .marker: String(localized: "Marker")
        case .monoline: String(localized: "Monoline")
        case .fountainPen: String(localized: "Fountain Pen")
        case .watercolor: String(localized: "Watercolour")
        case .crayon: String(localized: "Crayon")
        default: String(localized: "Pen")
        }
    }

    static func symbol(of ink: PKInkingTool.InkType) -> String {
        switch ink {
        case .pen: "pencil.tip"
        case .pencil: "pencil"
        case .marker: "highlighter"
        case .monoline: "pencil.line"
        case .watercolor: "paintbrush"
        case .crayon: "scribble"
        default: "paintbrush.pointed"
        }
    }

    /// The tools the tray offers as starters, and the only ones a new shelf begins with.
    static var kinds: [PKInkingTool.InkType] { [.pen, .pencil, .marker] }

    /// The kinds of ink a pen can be given, in the order they are offered.
    static var allKinds: [PKInkingTool.InkType] {
        var kinds: [PKInkingTool.InkType] = [.pen, .monoline, .fountainPen, .pencil, .marker, .crayon, .watercolor]
        if #available(iOS 26, *) { kinds.insert(.reed, at: 3) }
        return kinds
    }

    // MARK: Palette

    /// The app's inks, and four tints for the highlighter.
    static let inks: [UInt32] = [0x1B22_30FF, 0x6E73_7CFF, 0x7A52_30FF, 0xC945_2FFF, 0xE07A_1FFF, 0xE8B0_23FF,
                                 0x2F8F_4EFF, 0x1F8A_8AFF, 0x2747_B8FF, 0x3D8F_D9FF, 0x7A3E_9DFF, 0xD957_8CFF]
    static let tints: [UInt32] = [0xFFD4_26FF, 0x7ED9_8BFF, 0xFF8F_B8FF, 0x7CC4_FFFF]

    static func palette(for ink: PKInkingTool.InkType?) -> [UInt32] {
        ink == .marker ? tints + inks : inks + tints
    }

    static func colorName(_ color: UInt32) -> String {
        switch color | 0xFF {
        case 0xE8B0_23FF: return String(localized: "Mustard")
        case 0x3D8F_D9FF: return String(localized: "Sky Blue")
        case 0x7A3E_9DFF: return String(localized: "Plum")
        case 0x7ED9_8BFF: return String(localized: "Light Green")
        case 0xFF8F_B8FF: return String(localized: "Light Pink")
        case 0x7CC4_FFFF: return String(localized: "Light Blue")
        default: break
        }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        uiColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if brightness < 0.2 { return String(localized: "Black") }
        if saturation < 0.12 { return brightness > 0.9 ? String(localized: "White") : String(localized: "Grey") }
        switch hue * 360 {
        case ..<15, 345...: return String(localized: "Red")
        case ..<40: return brightness < 0.6 ? String(localized: "Brown") : String(localized: "Orange")
        case ..<65: return String(localized: "Yellow")
        case ..<165: return String(localized: "Green")
        case ..<195: return String(localized: "Teal")
        case ..<255: return String(localized: "Blue")
        case ..<290: return String(localized: "Purple")
        default: return String(localized: "Pink")
        }
    }

    var colorName: String { Self.colorName(color) }

    func isSameTool(as other: ToolPreset) -> Bool {
        ink == other.ink && color == other.color && abs(width - other.width) < 0.01
    }
}

// MARK: - ToolShelf

/// The pens in the tool tray, the same in every notebook and window. Kept in the app's settings.
@MainActor
@Observable
final class ToolShelf {
    static let limit = 8

    /// A new shelf starts with Apple's kit: Pen, Pencil, Marker, in black at Apple's default widths.
    static let starters = ToolPreset.kinds.map { ToolPreset(kind: $0) }

    private(set) var presets: [ToolPreset]
    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        presets = (defaults?.data(forKey: SettingsKey.toolPresets).flatMap { try? JSONDecoder().decode([ToolPreset].self, from: $0) } ?? Self.starters)
            .map { tool in
                var copy = tool
                copy.width = ToolPreset.clamped(copy.width, to: copy.widthRange)
                return copy
            }
    }

    var usable: [ToolPreset] { presets.filter { $0.inkType != nil } }

    var isFull: Bool { usable.count >= Self.limit }

    func holds(_ tool: ToolPreset) -> Bool { presets.contains { $0.isSameTool(as: tool) } }

    @discardableResult
    func add(_ tool: ToolPreset) -> Bool {
        guard !isFull, !holds(tool), tool.inkType != nil else { return false }
        presets.append(tool)
        save()
        return true
    }

    func change(_ id: UUID, _ change: (inout ToolPreset) -> Void) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        var changed = presets[index]
        change(&changed)
        changed.id = id
        guard changed != presets[index], changed.inkType != nil else { return }
        presets[index] = changed
        save()
    }

    func remove(_ id: UUID) {
        presets.removeAll { $0.id == id }
        save()
    }

    func move(_ id: UUID, by step: Int) {
        let shown = usable
        guard let from = shown.firstIndex(where: { $0.id == id }), shown.indices.contains(from + step),
              let source = presets.firstIndex(where: { $0.id == id }),
              let target = presets.firstIndex(where: { $0.id == shown[from + step].id }) else { return }
        presets.swapAt(source, target)
        save()
    }

    func restock() {
        guard usable.isEmpty else { return }
        presets += Self.freshStarters
        save()
    }

    var isAsItStarted: Bool {
        presets.count == Self.starters.count && zip(presets, Self.starters).allSatisfy { $0.isSameTool(as: $1) }
    }

    func reset() {
        presets = Self.freshStarters
        save()
    }

    private static var freshStarters: [ToolPreset] {
        starters.map { ToolPreset(ink: $0.inkType ?? .pen, color: $0.color, width: $0.width) }
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: SettingsKey.toolPresets)
    }
}

// MARK: - ToolChoice

enum ToolChoice: Codable, Hashable, Sendable {
    case pen(UUID), eraser, lasso
}

// MARK: - Eraser

struct Eraser: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case strokes, part
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .strokes: String(localized: "Whole Strokes")
            case .part: String(localized: "Part of a Stroke")
            }
        }
    }

    var kind = Kind.strokes
    var width = Double(PKEraserTool.EraserType.fixedWidthBitmap.defaultWidth)

    static var widths: ClosedRange<Double> {
        let range = PKEraserTool.EraserType.fixedWidthBitmap.validWidthRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    var tool: PKEraserTool {
        switch kind {
        case .strokes: PKEraserTool(.vector)
        case .part: PKEraserTool(.fixedWidthBitmap, width: min(max(width, Self.widths.lowerBound), Self.widths.upperBound))
        }
    }
}

// MARK: - ToolExtra

enum ToolExtra: String, Codable, CaseIterable, Identifiable, Sendable {
    case picture, text, sticker, link, tape, ruler, zoomWindow, typing
    var id: String { rawValue }

    static let starters: [ToolExtra] = [.picture, .text]

    var title: String {
        switch self {
        case .picture: String(localized: "Picture")
        case .text: String(localized: "Text Box")
        case .sticker: String(localized: "Sticker")
        case .link: String(localized: "Link")
        case .tape: String(localized: "Study Tape")
        case .ruler: String(localized: "Ruler")
        case .zoomWindow: String(localized: "Zoom Window")
        case .typing: String(localized: "Handwriting to Text")
        }
    }

    var symbol: String {
        switch self {
        case .picture: "photo"
        case .text: "character.textbox"
        case .sticker: "seal"
        case .link: "link"
        case .tape: "rectangle.dashed"
        case .ruler: "ruler"
        case .zoomWindow: "plus.magnifyingglass"
        case .typing: "character.cursor.ibeam"
        }
    }
}

// MARK: - Toolbox

@MainActor
@Observable
final class Toolbox {
    static let shared = Toolbox()
    static let didChange = Notification.Name("owlluna.toolbox.changed")

    private struct Saved: Codable {
        var choice: ToolChoice?
        var eraser: Eraser?
        var extras: [String]?
    }

    let shelf: ToolShelf
    private(set) var choice: ToolChoice
    private(set) var eraser: Eraser
    private(set) var extras: Set<ToolExtra>
    var isRulerActive = false {
        didSet { if isRulerActive != oldValue { post() } }
    }
    var typesHandwriting = false {
        didSet { if typesHandwriting != oldValue { post() } }
    }
    @ObservationIgnored private var memory = PencilToolMemory<ToolChoice>()
    @ObservationIgnored private var lastPen: UUID?
    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        shelf = ToolShelf(defaults: defaults)
        shelf.restock()
        let saved = defaults?.data(forKey: SettingsKey.toolbox).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        eraser = saved?.eraser ?? Eraser()
        extras = saved?.extras.map { Set($0.compactMap(ToolExtra.init(rawValue:))) } ?? Set(ToolExtra.starters)
        let pens = shelf.usable
        switch saved?.choice {
        case .pen(let id)? where pens.contains { $0.id == id }: choice = .pen(id)
        case .eraser?: choice = .eraser
        default: choice = pens.first.map { .pen($0.id) } ?? .eraser
        }
        if case .pen = choice {
            memory.select(choice, isEraser: false)
        } else if let firstPen = pens.first {
            memory.select(.pen(firstPen.id), isEraser: false)
            memory.select(choice, isEraser: choice == .eraser)
        } else {
            memory.select(choice, isEraser: choice == .eraser)
        }
    }

    var pen: ToolPreset? {
        guard case .pen(let id) = choice else { return nil }
        return shelf.usable.first { $0.id == id }
    }

    var tool: PKTool {
        switch choice {
        case .pen: pen?.tool ?? PKInkingTool(.pen)
        case .eraser: eraser.tool
        case .lasso: shelf.usable.first { $0.id == lastPen }?.tool ?? shelf.usable.first?.tool ?? PKInkingTool(.pen)
        }
    }

    func take(_ new: ToolChoice) {
        if case .pen(let id) = new, !shelf.usable.contains(where: { $0.id == id }) { return }
        guard new != choice else { return }
        if case .pen(let id) = choice { lastPen = id }
        memory.select(new, isEraser: new == .eraser)
        choice = new
        save()
        post()
    }

    func changePen(_ id: UUID, _ change: (inout ToolPreset) -> Void) {
        shelf.change(id, change)
        if choice == .pen(id) { post() }
    }

    /// A new pen like the one in hand, in the first of its colours the shelf doesn't have yet.
    @discardableResult
    func addPen() -> UUID? {
        let pens = shelf.usable
        guard let like = pen ?? pens.first(where: { $0.id == lastPen }) ?? pens.first, let ink = like.inkType else { return nil }
        let taken = Set(shelf.usable.filter { $0.ink == like.ink }.map(\.tint))
        guard let color = ToolPreset.palette(for: ink).first(where: { !taken.contains($0) }) else { return nil }
        var new = ToolPreset(ink: ink, color: color, width: like.width)
        new.opacity = like.opacity
        guard shelf.add(new) else { return nil }
        take(.pen(new.id))
        return new.id
    }

    func removePen(_ id: UUID) {
        let pens = shelf.usable
        guard pens.count > 1, let index = pens.firstIndex(where: { $0.id == id }) else { return }
        if choice == .pen(id) { take(.pen(pens[index == 0 ? 1 : index - 1].id)) }
        shelf.remove(id)
    }

    func resetPens() {
        let hadPen = choice != .eraser && choice != .lasso
        shelf.reset()
        lastPen = nil
        memory = PencilToolMemory()
        if let first = shelf.usable.first {
            if hadPen { choice = .pen(first.id) }
            memory.select(.pen(first.id), isEraser: false)
        }
        memory.select(choice, isEraser: choice == .eraser)
        save()
        post()
    }

    func setEraser(_ new: Eraser) {
        guard new != eraser else { return }
        eraser = new
        save()
        if choice == .eraser { post() }
    }

    func setExtra(_ extra: ToolExtra, shown: Bool) {
        guard extras.contains(extra) != shown else { return }
        if shown { extras.insert(extra) } else { extras.remove(extra) }
        if !shown, extra == .ruler { isRulerActive = false }
        if !shown, extra == .typing { typesHandwriting = false }
        save()
    }

    func switchEraser() {
        if let tool = memory.eraserSwitch(eraser: .eraser) { take(tool) }
    }

    func switchPrevious() {
        if let tool = memory.previous { take(tool) }
    }

    private func post() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func save() {
        let saved = Saved(choice: choice, eraser: eraser,
                          extras: ToolExtra.allCases.filter(extras.contains).map(\.rawValue))
        guard let defaults, let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: SettingsKey.toolbox)
    }
}
