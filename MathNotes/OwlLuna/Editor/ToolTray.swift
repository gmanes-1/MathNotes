import SwiftUI
import PencilKit

enum TrayEdge: String, CaseIterable, Sendable {
    case top, bottom, leading, trailing

    static let key = "toolTrayEdge"

    static var saved: TrayEdge { UserDefaults.standard.string(forKey: key).flatMap(TrayEdge.init(rawValue:)) ?? .bottom }

    var isVertical: Bool { self == .leading || self == .trailing }

    var alignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    var edge: Edge {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .top: "Move Tools to Top"
        case .bottom: "Move Tools to Bottom"
        case .leading: "Move Tools to Left"
        case .trailing: "Move Tools to Right"
        }
    }

    static func nearest(to point: CGPoint, in size: CGSize) -> TrayEdge {
        let distances: [(TrayEdge, CGFloat)] = [(.top, point.y), (.bottom, size.height - point.y),
                                                (.leading, point.x), (.trailing, size.width - point.x)]
        return distances.min { $0.1 < $1.1 }?.0 ?? .bottom
    }
}

struct ToolTray: View {
    let session: EditorSession
    let room: CGFloat
    var edge = TrayEdge.bottom
    let use: (ToolExtra) -> Void
    var moved: (CGSize) -> Void = { _ in }
    var dropped: (CGPoint) -> Void = { _ in }
    @State private var toolbox = Toolbox.shared
    @State private var hidden: Edge.Set = []
    @State private var editing: UUID?
    @State private var editingEraser = false
    @State private var customising = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 48
    static let gap = Space.x2
    static let slot: CGFloat = 38
    static let button: CGFloat = 44
    private static let inset = Space.x2
    private static let rule: CGFloat = 17
    private static let margin = Space.x4
    private static let fade: CGFloat = 20
    private static let grip: CGFloat = 28
    static let space = "editor.pane"

    struct Plan: Equatable {
        var pens: CGFloat
        var extras: Int
    }

    static func plan(pens: Int, extras: Int, room: CGFloat) -> Plan {
        let need: CGFloat = CGFloat(pens + (pens < ToolShelf.limit ? 1 : 0)) * slot
        let fixed: CGFloat = button * 3 + rule * 2 + inset * 2 + grip
        let space: CGFloat = room - margin * 2 - fixed
        var shown = extras
        while shown > 0, space - CGFloat(shown) * button < min(need, slot * 3) { shown -= 1 }
        return Plan(pens: max(min(need, space - CGFloat(shown) * button), slot), extras: shown)
    }

    var body: some View {
        let pens = toolbox.shelf.usable
        let extras = ToolExtra.allCases.filter(toolbox.extras.contains)
        let plan = Self.plan(pens: pens.count, extras: extras.count, room: room)
        let scrolls = plan.pens < CGFloat(pens.count + (toolbox.shelf.isFull ? 0 : 1)) * Self.slot - 0.5
        let vertical = edge.isVertical
        let stack = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        stack {
            gripHandle
            penRow(pens)
                .frame(width: vertical ? Self.button : plan.pens, height: vertical ? plan.pens : Self.button)
                .mask {
                    stack {
                        LinearGradient(colors: [.black.opacity(scrolls && hidden.contains(.leading) ? 0 : 1), .black],
                                       startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing)
                            .frame(width: vertical ? nil : Self.fade, height: vertical ? Self.fade : nil)
                        Color.black
                        LinearGradient(colors: [.black, .black.opacity(scrolls && hidden.contains(.trailing) ? 0 : 1)],
                                       startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing)
                            .frame(width: vertical ? nil : Self.fade, height: vertical ? Self.fade : nil)
                    }
                }
            rule
            eraserButton
            lassoButton
            rule
            ForEach(extras.prefix(plan.extras)) { extraButton($0) }
            customiseButton
        }
        .padding(vertical ? .vertical : .horizontal, Self.inset)
        .frame(width: vertical ? Self.height : nil, height: vertical ? nil : Self.height)
        .board(in: RoundedRectangle.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tools"))
        .accessibilityIdentifier("editor.tools.tray")
    }

    private var gripHandle: some View {
        Image(systemName: "line.3.horizontal")
            .rotationEffect(.degrees(edge.isVertical ? 0 : 90))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.textSecondary)
            .frame(width: edge.isVertical ? Self.button : Self.grip, height: edge.isVertical ? Self.grip : Self.button)
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                .onChanged { moved($0.translation) }
                .onEnded { dropped($0.location) })
            .accessibilityLabel(Text("Move Tools"))
            .accessibilityHint(Text("Drag to another edge of the screen"))
            .accessibilityActions {
                ForEach(TrayEdge.allCases.filter { $0 != edge }, id: \.self) { other in
                    Button(other.title) { session.toolTrayEdge = other }
                }
            }
            .accessibilityIdentifier("editor.tools.grip")
    }

    private var rule: some View {
        let vertical = edge.isVertical
        return Rectangle().fill(Color.hairline)
            .frame(width: vertical ? 24 : 1, height: vertical ? 1 : 24)
            .padding(vertical ? .vertical : .horizontal, Space.x2)
    }

    // MARK: Pens

    private func penRow(_ pens: [ToolPreset]) -> some View {
        let vertical = edge.isVertical
        return ScrollViewReader { proxy in
            ScrollView(vertical ? .vertical : .horizontal) {
                (vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))) {
                    ForEach(Array(pens.enumerated()), id: \.element.id) { index, pen in
                        penButton(pen, at: index, of: pens.count).id(pen.id)
                    }
                    if !toolbox.shelf.isFull {
                        Button(action: addPen) { Label("New Pen", systemImage: "plus") }
                            .buttonStyle(NewPenButtonStyle(vertical: vertical))
                            .accessibilityHint(Text("Adds a pen like the one in hand, in another colour"))
                            .accessibilityIdentifier("editor.tools.add")
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: vertical ? .vertical : .horizontal)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Edge.Set.self) { geometry in
                guard room > 0 else { return [] }
                let x = vertical ? geometry.contentOffset.y : geometry.contentOffset.x
                let end = vertical ? geometry.contentSize.height - geometry.containerSize.height : geometry.contentSize.width - geometry.containerSize.width
                return (x > 1 ? Edge.Set.leading : []).union(x < end - 1 ? .trailing : [])
            } action: { _, edges in hidden = edges }
            .onChange(of: toolbox.choice) { _, choice in
                guard case .pen(let id) = choice else { return }
                withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { proxy.scrollTo(id) }
            }
            .onChange(of: pens.map(\.id)) {
                guard case .pen(let id) = toolbox.choice else { return }
                withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { proxy.scrollTo(id) }
            }
        }
    }

    private func penButton(_ pen: ToolPreset, at index: Int, of count: Int) -> some View {
        let inHand = toolbox.choice == .pen(pen.id)
        return Button { if inHand { editing = pen.id } else { take(.pen(pen.id), named: pen.name) } } label: {
            ToolSwatch(preset: pen, inUse: inHand, onDark: session.inkIsLight, turned: session.paperIsNight)
        }
        .buttonStyle(ToolSwatchButtonStyle(vertical: edge.isVertical))
        .panel("Pen Options", isPresented: Binding(get: { editing == pen.id }, set: { if !$0, editing == pen.id { editing = nil } })) {
            ScrollView { PenOptions(id: pen.id, toolbox: toolbox, onDark: session.inkIsLight, turned: session.paperIsNight) { remove(pen) } }
                .scrollBounceBehavior(.basedOnSize)
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in change(pen) })
        .accessibilityLabel(Text(pen.name))
        .accessibilityValue(pen.opacity < 1
                            ? Text("Width \(pen.width.formatted(.number.precision(.fractionLength(0...1)))), opacity \(pen.opacityName)")
                            : Text("Width \(pen.width.formatted(.number.precision(.fractionLength(0...1))))"))
        .accessibilityAddTraits(inHand ? .isSelected : [])
        .accessibilityActions {
            Button("Change Pen") { change(pen) }
            if index > 0 { Button("Move Left") { toolbox.shelf.move(pen.id, by: -1) } }
            if index < count - 1 { Button("Move Right") { toolbox.shelf.move(pen.id, by: 1) } }
            if count > 1 { Button("Remove") { remove(pen) } }
        }
        .accessibilityShowsLargeContentViewer { Label(pen.name, systemImage: pen.symbol) }
        .accessibilityIdentifier("editor.tools.\(index + 1)")
    }

    private func take(_ choice: ToolChoice, named name: String) {
        toolbox.take(choice)
        if choice != .lasso, session.mode == .selecting { session.enter(.writing) }
        UISelectionFeedbackGenerator().selectionChanged()
        AccessibilityNotification.Announcement(name).post()
    }

    private func change(_ pen: ToolPreset) {
        guard editing != pen.id else { return }
        toolbox.take(.pen(pen.id))
        UISelectionFeedbackGenerator().selectionChanged()
        editing = pen.id
    }

    private func addPen() {
        guard let id = toolbox.addPen() else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            editing = id
        }
    }

    private func remove(_ pen: ToolPreset) {
        if editing == pen.id { editing = nil }
        toolbox.removePen(pen.id)
        AccessibilityNotification.Announcement(String(localized: "\(pen.name) removed from the tools")).post()
    }

    // MARK: Eraser, lasso and shortcuts

    private var eraserButton: some View {
        let inHand = toolbox.choice == .eraser
        return Button { if inHand { editingEraser = true } else { take(.eraser, named: String(localized: "Eraser")) } } label: {
            Label("Eraser", systemImage: "eraser")
        }
        .buttonStyle(TrayIconStyle(isOn: inHand))
        .panel("Eraser", isPresented: $editingEraser) {
            ScrollView { EraserOptions(toolbox: toolbox) }
                .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityValue(Text(toolbox.eraser.kind.displayName))
        .accessibilityAddTraits(inHand ? .isSelected : [])
        .accessibilityIdentifier("editor.tools.eraser")
    }

    private var lassoButton: some View {
        let inHand = toolbox.choice == .lasso
        return Button {
            take(.lasso, named: String(localized: "Lasso"))
            session.enter(.selecting)
        } label: {
            Label("Lasso", systemImage: "lasso")
        }
        .buttonStyle(TrayIconStyle(isOn: inHand))
        .accessibilityAddTraits(inHand ? .isSelected : [])
        .accessibilityIdentifier("editor.tools.lasso")
    }

    private func extraButton(_ extra: ToolExtra) -> some View {
        let isOn: Bool
        switch extra {
        case .ruler: isOn = toolbox.isRulerActive
        case .zoomWindow: isOn = session.isZoomWindowOpen
        case .typing: isOn = toolbox.typesHandwriting
        default: isOn = false
        }
        return Button { use(extra) } label: { Label(extra.title, systemImage: extra.symbol) }
            .buttonStyle(TrayIconStyle(isOn: isOn))
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityIdentifier("editor.tools.extra.\(extra.rawValue)")
    }

    private var customiseButton: some View {
        Button { customising = true } label: { Label("Customise Tools", systemImage: "slider.horizontal.3") }
            .buttonStyle(TrayIconStyle(isOn: customising))
            .panel("Customise Tools", isPresented: $customising) {
                ScrollView { ShortcutOptions(toolbox: toolbox) }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .accessibilityIdentifier("editor.tools.customise")
    }
}

private struct ShortcutOptions: View {
    let toolbox: Toolbox
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let list = textSize.isAccessibilitySize
        let width: CGFloat = textSize > .accessibility2 ? 440 : 328
        let layout = list ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x2)) : AnyLayout(FlowLayout(spacing: Space.x2))
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Shortcuts in the Tray")
                .font(.headline)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            layout {
                ForEach(ToolExtra.allCases) { extra in
                    let shown = toolbox.extras.contains(extra)
                    ShortcutTag(extra: extra, isShown: shown, fills: list) { toolbox.setExtra(extra, shown: !shown) }
                        .padding(.vertical, -Space.x1)
                        .accessibilityIdentifier("editor.tools.shortcut.\(extra.rawValue)")
                }
            }
        }
        .padding(Space.x4)
        .frame(minWidth: 328, idealWidth: width, maxWidth: width, alignment: .leading)
    }
}

private struct ShortcutTag: View {
    let extra: ToolExtra
    let isShown: Bool
    let fills: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let night = scheme == .dark
        let shape = RoundedRectangle.plate
        Button(action: action) {
            HStack(spacing: Space.x2) {
                Image(systemName: extra.symbol).font(.footnote.weight(.semibold))
                Text(extra.title)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
                Image(systemName: isShown ? "checkmark" : "plus").font(.caption.weight(.bold)).opacity(isShown ? 1 : 0.6)
            }
            .foregroundStyle(isShown ? Color.onMustard : night ? Color.ink : Color.labelInk)
            .padding(.horizontal, Space.x3)
            .padding(.vertical, Space.x1)
            .frame(minHeight: 32)
            .background(isShown ? Color.mustard : ToolSwatch.paper(onDark: false, night: night), in: shape)
            .overlay { shape.strokeBorder(Color.hairline, lineWidth: 1) }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(extra.title)
        .accessibilityAddTraits(isShown ? [.isButton, .isSelected] : .isButton)
    }
}

private struct PenOptions: View {
    let id: UUID
    let toolbox: Toolbox
    let onDark: Bool
    let turned: Bool
    let remove: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.colorScheme) private var scheme

    private static let cell: CGFloat = 44
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 6)

    var body: some View {
        if let pen = toolbox.shelf.usable.first(where: { $0.id == id }), let ink = pen.inkType {
            content(pen, ink)
                .frame(width: 304 + Space.x4 * 2)
        }
    }

    private func content(_ pen: ToolPreset, _ ink: PKInkingTool.InkType) -> some View {
        let width = pen.width.formatted(.number.precision(.fractionLength(0...1)))
        let night = scheme == .dark && !onDark
        let solid = Color(uiColor: ToolPreset.uiColor(pen.tint))
        let paper = ToolSwatch.paper(onDark: onDark, night: night)
        return VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x3) {
                Text(pen.kindName).font(.headline).foregroundStyle(Color.ink)
                Text(pen.opacity < 1 ? "\(pen.colorName), \(pen.opacityName)" : pen.colorName)
                    .font(.footnote).foregroundStyle(Color.textSecondary)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Self.columns, spacing: 0) {
                ForEach(ToolPreset.palette(for: ink), id: \.self) { color in
                    colourButton(color, chosen: pen.tint == color)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Colour"))

            WidthBar(travel: Binding(get: { pen.widthTravel }, set: { travel in
                toolbox.changePen(id) { $0.width = ToolPreset.width(at: travel, of: ink) }
            }), ink: solid, paper: paper, night: night, value: width, identifier: "editor.tools.pen.width")

            WidthBar(measure: .opacity, travel: Binding(get: { (pen.opacity - ToolPreset.leastOpacity) / (1 - ToolPreset.leastOpacity) }, set: { travel in
                toolbox.changePen(id) { $0.opacity = ((ToolPreset.leastOpacity + (1 - ToolPreset.leastOpacity) * travel) * 20).rounded() / 20 }
            }), ink: solid, paper: paper, night: night, turned: turned, value: pen.opacityName, identifier: "editor.tools.pen.opacity")

            place(pen)
        }
        .padding(Space.x4)
    }

    private func place(_ pen: ToolPreset) -> some View {
        let pens = toolbox.shelf.usable, index = pens.firstIndex { $0.id == id } ?? 0
        return HStack(spacing: 0) {
            Button { toolbox.shelf.move(id, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") }
                .disabled(index == 0)
                .accessibilityIdentifier("editor.tools.pen.left")
            Button { toolbox.shelf.move(id, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") }
                .disabled(index >= pens.count - 1)
                .accessibilityIdentifier("editor.tools.pen.right")
            Spacer(minLength: 0)
            Button(role: .destructive, action: remove) { Label("Remove", systemImage: "trash") }
                .disabled(pens.count < 2)
                .accessibilityIdentifier("editor.tools.pen.remove")
        }
        .buttonStyle(.barIcon)
        .padding(.top, Space.x1)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }

    private func colourButton(_ color: UInt32, chosen: Bool) -> some View {
        Button { toolbox.changePen(id) { $0.setTint(color) } } label: {
            Circle()
                .fill(Color(uiColor: ToolPreset.uiColor(color)))
                .overlay { Circle().strokeBorder(Color.ink.opacity(scheme == .dark ? 0.45 : 0.25), lineWidth: 1) }
                .frame(width: 28, height: 28)
                .padding(4)
                .overlay { if chosen { Circle().strokeBorder(Color.accentColor, lineWidth: 2) } }
                .frame(maxWidth: .infinity, minHeight: Self.cell)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(ToolPreset.colorName(color)))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

private struct EraserOptions: View {
    let toolbox: Toolbox
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let eraser = toolbox.eraser, night = scheme == .dark
        let width = eraser.width.formatted(.number.precision(.fractionLength(0)))
        VStack(alignment: .leading, spacing: Space.x3) {
            MathNotesSegmentedPicker("Eraser", selection: Binding(get: { eraser.kind }, set: { kind in
                var changed = eraser
                changed.kind = kind
                toolbox.setEraser(changed)
            }), options: Eraser.Kind.allCases) { Text($0.displayName) }
            if eraser.kind == .part {
                let widths = Eraser.widths, span = widths.upperBound - widths.lowerBound
                WidthBar(travel: Binding(get: { (eraser.width - widths.lowerBound) / span }, set: { travel in
                    var changed = eraser
                    changed.width = widths.lowerBound + span * travel
                    toolbox.setEraser(changed)
                }), ink: night ? Color.textSecondary : Color.labelInkSecondary,
                         paper: ToolSwatch.paper(onDark: false, night: night), night: night,
                         value: width, identifier: "editor.tools.eraser.width")
            }
        }
        .padding(Space.x4)
        .frame(width: 344)
    }
}

struct WidthBar: View {
    enum Measure { case width, opacity }

    var measure = Measure.width
    @Binding var travel: Double
    let ink: Color
    let paper: Color
    var night = false
    var turned = false
    let value: String
    let identifier: String
    @State private var isDragging = false
    @Environment(\.colorSchemeContrast) private var contrast

    private static let height: CGFloat = 44
    private static let knob: CGFloat = 32
    private static let shape = RoundedRectangle.track

    var body: some View {
        let name = title.font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
        let figure = Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(Color.textSecondary)
        return VStack(spacing: Space.x2) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    name.lineLimit(1)
                    Spacer(minLength: Space.x2)
                    figure.lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 0) {
                    name
                    figure
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityHidden(true)
            strip
        }
    }

    private var title: Text { measure == .width ? Text("Width") : Text("Opacity") }

    private var strip: some View {
        GeometryReader { proxy in
            let run = max(proxy.size.width - Self.knob - Space.x2 * 2, 1)
            ZStack(alignment: .leading) {
                Self.shape.fill(paper)
                Group {
                    switch measure {
                    case .width:
                        Swell()
                            .fill(ink)
                            .overlay { if night { Swell().stroke(ToolSwatch.rim(contrast), lineWidth: 1) } }
                            .frame(height: 20)
                    case .opacity:
                        wash
                    }
                }
                .padding(.horizontal, Space.x2 + Self.knob / 2)
                knob.offset(x: Space.x2 + run * travel)
            }
            .overlay { Self.shape.strokeBorder(Color.hairline, lineWidth: 1) }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    isDragging = true
                    travel = min(max((drag.location.x - Space.x2 - Self.knob / 2) / run, 0), 1)
                }
                .onEnded { _ in isDragging = false })
        }
        .frame(height: Self.height)
        .accessibilityRepresentation {
            Slider(value: $travel)
                .accessibilityLabel(title)
                .accessibilityValue(Text(value))
                .accessibilityIdentifier(identifier)
        }
    }

    private func faint(_ strength: Double) -> Color {
        night && !turned ? ToolSwatch.onPaper(UIColor(ink), at: strength) : ink.opacity(strength)
    }

    private var wash: some View {
        let band = RoundedRectangle.thumb
        let lines = VStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { _ in Rectangle().fill(night ? Color.black.opacity(0.4) : Color.ink.opacity(0.35)).frame(height: 1) }
        }
        return ZStack {
            if !night { lines }
            band.fill(LinearGradient(colors: [faint(ToolPreset.leastOpacity), ink], startPoint: .leading, endPoint: .trailing))
            if night { lines.mask(LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)) }
        }
        .frame(height: 16)
        .clipShape(band)
        .overlay { band.strokeBorder(night ? ToolSwatch.rim(contrast) : Color.ink.opacity(0.18), lineWidth: 1) }
        .frame(height: 20)
    }

    private var knob: some View {
        let blot = measure == .width ? 4 + 16 * travel : 16
        let strength = measure == .width ? 1 : ToolPreset.leastOpacity + (1 - ToolPreset.leastOpacity) * travel
        return Circle()
            .fill(night ? Color.surface : paper)
            .overlay { if measure == .opacity { Rectangle().fill(Color.ink.opacity(night ? 0.5 : 0.35)).frame(width: 22, height: 1) } }
            .overlay {
                Circle()
                    .fill(faint(strength))
                    .overlay { if night || measure == .opacity { Circle().strokeBorder(ToolSwatch.rim(contrast).opacity(night ? 1 : 0.5), lineWidth: 1) } }
                    .frame(width: blot, height: blot)
            }
            .overlay { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
            .frame(width: Self.knob, height: Self.knob)
            .shadow(color: .black.opacity(0.22), radius: isDragging ? 4 : 1.5, y: 1)
            .scaleEffect(isDragging ? 1.08 : 1)
            .animation(Motion.quick, value: isDragging)
    }

    private struct Swell: Shape {
        func path(in rect: CGRect) -> Path {
            let thin: CGFloat = 1, broad = rect.height / 2
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + thin, y: rect.midY - thin))
            path.addLine(to: CGPoint(x: rect.maxX - broad, y: rect.midY - broad))
            path.addArc(center: CGPoint(x: rect.maxX - broad, y: rect.midY), radius: broad, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + thin, y: rect.midY + thin))
            path.addArc(center: CGPoint(x: rect.minX + thin, y: rect.midY), radius: thin, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
            path.closeSubpath()
            return path
        }
    }
}

struct ToolSwatch: View {
    let preset: ToolPreset
    var inUse = false
    var onDark = false
    var turned = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    static let side: CGFloat = 32
    static let shape = RoundedRectangle.plate
    private static let chalkboard = Color(red: PaperColor.chalkboard.rgb.0, green: PaperColor.chalkboard.rgb.1, blue: PaperColor.chalkboard.rgb.2)

    static func paper(onDark: Bool, night: Bool = false) -> Color { onDark ? chalkboard : night ? Color.well : Color.labelCream }

    static func rim(_ contrast: ColorSchemeContrast) -> Color { Color.ink.opacity(contrast == .increased ? 0.9 : 0.55) }

    static func ink(_ preset: ToolPreset, onDark: Bool, solid: Bool = false, night: Bool = false, turned: Bool = false) -> Color {
        if night, !onDark, !turned, !solid, preset.opacity < 1 { return onPaper(ToolPreset.uiColor(preset.tint), at: preset.opacity) }
        let color = solid ? ToolPreset.uiColor(preset.tint) : preset.uiColor
        return Color(uiColor: onDark || turned ? PKInkingTool.convertColor(color, from: .light, to: .dark) : color)
    }

    static func onPaper(_ color: UIColor, at opacity: Double) -> Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let rest = 1 - opacity
        return Color(red: red * opacity + rest, green: green * opacity + rest, blue: blue * opacity + rest)
    }

    var body: some View {
        let shape = Self.shape
        let blot = 9 + 11 * preset.widthFraction
        let night = scheme == .dark && !onDark
        let rim = night ? Self.rim(contrast) : (onDark ? Color.white : Color.labelInk).opacity(contrast == .increased ? 0.6 : 0.22)
        ZStack {
            shape.fill(Self.paper(onDark: onDark, night: night))
            Circle()
                .fill(Self.ink(preset, onDark: onDark, night: night, turned: turned))
                .overlay { Circle().strokeBorder(rim, lineWidth: 1) }
                .frame(width: blot, height: blot)
                .offset(x: 3, y: 3)
            Image(systemName: preset.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(night ? Color.textSecondary : onDark ? Color.white.opacity(0.8) : Color.labelInkSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(3)
        }
        .frame(width: Self.side, height: Self.side)
        .overlay { shape.strokeBorder(inUse ? Color.accentColor : Color.hairline, lineWidth: inUse ? 2 : 1) }
        .overlay(alignment: .bottomTrailing) {
            if inUse {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.onPrimaryCloth)
                    .frame(width: 14, height: 14)
                    .background(Color.primaryCloth, in: Circle())
                    .offset(x: 3, y: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ToolSwatchButtonStyle: ButtonStyle {
    var vertical = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .frame(width: vertical ? ToolTray.button : ToolTray.slot, height: vertical ? ToolTray.slot : ToolTray.button)
            .contentShape(Rectangle())
            .contentShape(.hoverEffect, RoundedRectangle.plate.inset(by: 1))
            .hoverEffect(.highlight)
    }
}

struct TrayIconStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        Icon(configuration: configuration, isOn: isOn)
    }

    private struct Icon: View {
        let configuration: Configuration
        let isOn: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityShowBorders) private var showBorders

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .imageScale(.large)
                .foregroundStyle(Color.ink)
                .opacity(isEnabled ? 1 : 0.35)
                .frame(width: ToolSwatch.side, height: ToolSwatch.side)
                .background { if isOn || (configuration.isPressed && isEnabled) || showBorders { ToolSwatch.shape.fill(Color.well) } }
                .overlay { if isOn { ToolSwatch.shape.strokeBorder(Color.accentColor, lineWidth: 2) } }
                .frame(width: ToolTray.button, height: ToolTray.button)
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, RoundedRectangle.plate.inset(by: 1))
                .hoverEffect(.highlight)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityShowsLargeContentViewer { configuration.label.labelStyle(.titleAndIcon) }
        }
    }
}

struct NewPenButtonStyle: ButtonStyle {
    var vertical = false

    func makeBody(configuration: Configuration) -> some View {
        Icon(configuration: configuration, vertical: vertical)
    }

    private struct Icon: View {
        let configuration: Configuration
        let vertical: Bool
        @Environment(\.accessibilityShowBorders) private var showBorders

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: ToolSwatch.side, height: ToolSwatch.side)
                .background { if configuration.isPressed || showBorders { ToolSwatch.shape.fill(Color.well) } }
                .overlay {
                    ToolSwatch.shape.strokeBorder(Color.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .frame(width: vertical ? ToolTray.button : ToolTray.slot, height: vertical ? ToolTray.slot : ToolTray.button)
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, RoundedRectangle.plate.inset(by: 1))
                .hoverEffect(.highlight)
                .accessibilityShowsLargeContentViewer { configuration.label.labelStyle(.titleAndIcon) }
        }
    }
}
