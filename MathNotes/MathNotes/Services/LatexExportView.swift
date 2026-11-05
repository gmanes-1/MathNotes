import SwiftUI
import PencilKit
import UIKit

// MARK: - Page -> image helper (use this if you only have a PKDrawing per page)

enum PageSnapshot {
    /// Renders ink on white, always in "light" mode so the ink is dark (chalkboard paper would otherwise give white ink).
    static func image(drawing: PKDrawing, pageSize: CGSize, scale: CGFloat = 2) -> UIImage {
        let rect = CGRect(origin: .zero, size: pageSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: pageSize, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(rect)
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                drawing.image(from: rect, scale: scale).draw(in: rect)
            }
        }
    }
}

// MARK: - The sheet

/// One row per page. Convert each page; the .tex is assembled only when you tap Copy for Overleaf or Share.
struct LatexExportView: View {
    @ObservedObject var engine: LatexEngine
    let document: NotebookDocument

    @Environment(\.dismiss) private var dismiss
    @State private var statuses: [UUID: PageStatus] = [:]
    @State private var quality: [UUID: LatexEngine.Quality] = [:]
    @State private var busy: UUID?
    @State private var running = false
    @State private var stopRequested = false
    @State private var message = ""
    @State private var showModel = false
    @State private var showFullDoc = false
    @State private var shareURL: URL?
    @State private var viewingCode: PageCode?
    @AppStorage("paragraphMode") private var paragraphMode = "smart"

    private var pending: [Int] {
        document.pages.indices.filter {
            let s = statuses[document.pages[$0].id]
            return s == .notConverted || s == .changed
        }
    }

    private var convertedCount: Int {
        statuses.values.filter { $0 == .converted || $0 == .changed }.count
    }

    var body: some View {
        NavigationStack {
            listContent
                .navigationTitle("Convert to LaTeX")
                .navigationBarTitleDisplayMode(.inline)
                .barGround(.surface)
                .toolbar { toolbarContent }
                .onAppear {
                    UserDefaults.standard.set(paragraphMode, forKey: "paragraphMode")
                    reload()
                }
                .onChange(of: paragraphMode) { _, new in
                    UserDefaults.standard.set(new, forKey: "paragraphMode")
                }
                .sheet(isPresented: $showModel) {
                    ModelSetupView(engine: engine)
                }
                .sheet(isPresented: $showFullDoc) {
                    FullDocumentView(document: document, statuses: statuses)
                }
                .sheet(item: $viewingCode) { code in
                    LatexCodeSheet(title: "Page \(code.number)", code: code.body)
                }
                .sheet(item: shareBoxBinding) { box in
                    ShareSheet(items: [box.url])
                }
        }
        .tint(Color.accentColor)
        .presentationCornerRadius(Radius.sheet)
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        List {
            pagesSection
            convertAllSection
            optionsSection
            fullDocumentSection
        }
        .latexSheetStyle()
    }

    @ViewBuilder
    private var pagesSection: some View {
        Section {
            ForEach(Array(document.pages.enumerated()), id: \.element.id) { index, page in
                row(index, page)
                    .listRowBackground(Color.paper)
            }
        } header: {
            Text("Pages").latexHeader()
        } footer: {
            statusFooter
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
        }
    }

    @ViewBuilder
    private var convertAllSection: some View {
        Section {
            Button {
                Task { await convertPending() }
            } label: {
                Label {
                    Text(convertButtonTitle)
                } icon: {
                    Image(systemName: "wand.and.stars")
                }
                .frame(maxWidth: .infinity)
            }
            .prominentButton()
            .disabled(running || busy != nil || pending.isEmpty)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .accessibilityIdentifier("latex.convertAll")

            if running {
                Button("Stop after this page", role: .destructive) {
                    stopRequested = true
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.mathNotes(.destructive))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("latex.stop")
            }
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        Section {
            Picker("New paragraphs", selection: $paragraphMode) {
                Text("Smart").tag("smart")
                Text("Gaps only").tag("gaps")
                Text("Every line").tag("everyLine")
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.paper)

            Picker("Engine", selection: Binding(
                get: { engine.backend },
                set: { engine.setBackend($0) }
            )) {
                Text("Built-in (recommended)").tag(LatexEngine.Backend.cloud)
                Text("On-device model").tag(LatexEngine.Backend.device)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.paper)
        } header: {
            Text("Conversion options").latexHeader()
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart: a new paragraph starts after a bigger gap, after a line that ends short, or when a line is indented.")
                if engine.backend == .cloud {
                    Text("Built-in: each page is converted by the managed MathNotes service (Gemini vision), then verified and auto-fixed — nothing to set up. Needs internet.")
                } else {
                    Text("On-device: runs the imported GLM-OCR model offline. Import it when asked.")
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
        }
    }

    @ViewBuilder
    private var fullDocumentSection: some View {
        Section {
            Button {
                showFullDoc = true
            } label: {
                Label("Full document & templates", systemImage: "doc.text")
                    .foregroundStyle(Color.ink)
            }
            .disabled(convertedCount == 0)
            .listRowBackground(Color.paper)
            .accessibilityIdentifier("latex.fullDocument")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
                .buttonStyle(.mathNotes(.secondary, inBar: true))
                .accessibilityIdentifier("latex.close")
        }
        .boardBackground()
    }

    private var shareBoxBinding: Binding<ShareBox?> {
        Binding(
            get: { shareURL.map(ShareBox.init) },
            set: { shareURL = $0?.url }
        )
    }

    // MARK: - Footer & button text

    @ViewBuilder
    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(footerText)
            if busy != nil, !engine.progress.isEmpty {
                Text(engine.progress)
            }
        }
    }

    private var footerText: String {
        if message.isEmpty {
            return "Each page is converted once. Only pages you change are converted again."
        } else {
            return message
        }
    }

    private var convertButtonTitle: String {
        if running {
            return "Converting…"
        } else {
            return "Convert all pending pages (\(pending.count))"
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ i: Int, _ page: NotebookPage) -> some View {
        let st = statuses[page.id] ?? .notConverted
        HStack(spacing: 12) {
            let saved = (st == .converted || st == .changed) ? PageLatexStore.read(document: document, page: page) : nil
            Button {
                if let saved { viewingCode = PageCode(id: page.id, number: i + 1, body: saved.body) }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Page \(i + 1)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.ink)
                        Text(label(st)).font(.caption).foregroundStyle(color(st))
                        if let q = quality[page.id], q.status == "best_effort", let first = q.issues.first {
                            Text("Best effort: \(first)")
                                .font(.caption2)
                                .foregroundStyle(Color.orange)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if let q = quality[page.id], !q.status.isEmpty {
                        Label(q.status == "verified" ? "Verified" : "Best effort",
                              systemImage: q.status == "verified" ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(q.status == "verified" ? Color.green : Color.orange)
                            .accessibilityIdentifier("latex.page.\(i + 1).quality")
                    }
                    if saved != nil {
                        Label("View LaTeX", systemImage: "chevron.left.forwardslash.chevron.right")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(saved != nil)
            .accessibilityHint(saved == nil ? Text("") : Text("Shows this page's LaTeX code"))
            .accessibilityIdentifier("latex.page.\(i + 1).code")
            if busy == page.id {
                ProgressView()
            } else {
                Button(buttonTitle(st)) {
                    Task { await convertOne(i) }
                }
                .buttonStyle(.mathNotes(.secondary, compact: true))
                .disabled(running || busy != nil)
                .accessibilityIdentifier("latex.page.\(i + 1)")
            }
        }
    }

    private func label(_ s: PageStatus) -> String {
        switch s {
        case .empty: return "Empty page"
        case .notConverted: return "Not converted"
        case .converted: return "Converted"
        case .changed: return "Changed since last conversion"
        }
    }

    private func color(_ s: PageStatus) -> Color {
        switch s {
        case .converted: return Color.accentColor
        case .changed: return Color.tomato
        default: return Color.textSecondary
        }
    }

    private func buttonTitle(_ s: PageStatus) -> String {
        switch s {
        case .changed: return "Update"
        case .converted: return "Redo"
        default: return "Convert"
        }
    }

    // MARK: - Actions

    private func reload() {
        var s: [UUID: PageStatus] = [:]
        for page in document.pages {
            let ink = document.loadedInk(page.id)
            if let ink, ink.strokes.isEmpty {
                s[page.id] = .empty
                quality[page.id] = nil
            } else if let saved = PageLatexStore.read(document: document, page: page) {
                let current = document.loadedInk(page.id)?.inkSignature ?? ""
                s[page.id] = saved.inkSignature == current ? .converted : .changed
                if let status = saved.status {
                    quality[page.id] = LatexEngine.Quality(status: status, issues: saved.issues ?? [],
                                                           model: saved.model ?? "", attempts: saved.attempts ?? 0)
                } else {
                    quality[page.id] = nil
                }
            } else {
                s[page.id] = .notConverted
                quality[page.id] = nil
            }
        }
        statuses = s
    }

    private func convertOne(_ i: Int) async -> Bool {
        guard document.pages.indices.contains(i) else { return false }
        if engine.backend == .device, engine.state == .needsModel { showModel = true; return false }
        let page = document.pages[i]
        busy = page.id
        message = "Reading page \(i + 1)…"
        let ok: Bool
        do {
            guard let img = await LatexPageSource.image(document: document, pageIndex: i) else {
                message = "Page \(i + 1) is blank."
                busy = nil
                reload()
                return false
            }
            // The previous page's LaTeX goes along so notation and numbering stay consistent.
            let context = i > 0 ? PageLatexStore.read(document: document, page: document.pages[i - 1])?.body : nil
            let r = try await engine.convert(img, context: context)
            let q = engine.lastQuality
            let ink = await document.ink(page.id)
            PageLatexStore.write(document: document, page: page,
                                 body: r.body, title: r.title, signature: ink.inkSignature,
                                 status: q?.status, issues: q?.issues, model: q?.model, attempts: q?.attempts)
            if let q, q.status == "best_effort", let first = q.issues.first {
                message = "Page \(i + 1): best effort — \(first)"
            } else {
                message = r.body.isEmpty ? "Page \(i + 1): nothing recognised." : ""
            }
            ok = true
        } catch {
            message = error.localizedDescription
            ok = false
        }
        busy = nil
        reload()
        return ok
    }

    private func convertPending() async {
        running = true
        stopRequested = false
        var finished = true
        for i in pending {
            if stopRequested { finished = false; break }
            if !(await convertOne(i)) { finished = false; break }
        }
        running = false
        // When every page is done, the whole document's code is shown.
        if finished, convertedCount > 0 { showFullDoc = true }
    }
}

// MARK: - Share helpers

private struct ShareBox: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Full document

/// Assembles all converted pages into one .tex and offers Copy / Share.
struct FullDocumentView: View {
    let document: NotebookDocument
    let statuses: [UUID: PageStatus]

    @Environment(\.dismiss) private var dismiss
    @State private var template = DocTemplate.load()
    @State private var assembled = ""
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            listContent
                .navigationTitle("Full document")
                .navigationBarTitleDisplayMode(.inline)
                .barGround(.surface)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .buttonStyle(.mathNotes(.primary, inBar: true))
                            .accessibilityIdentifier("latex.document.done")
                    }
                    .boardBackground()
                }
                .onAppear { assemble() }
                .onChange(of: template) { _, _ in assemble() }
                .sheet(item: shareBoxBinding) { box in
                    ShareSheet(items: [box.url])
                }
        }
        .tint(Color.accentColor)
        .presentationCornerRadius(Radius.sheet)
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            templateSection
            actionsSection
            codeSection
        }
        .latexSheetStyle()
    }

    /// The whole .tex, selectable, as it will be copied or shared.
    @ViewBuilder
    private var codeSection: some View {
        Section {
            LatexCodeBox(code: assembled.isEmpty ? String(localized: "Nothing converted yet.") : assembled)
                .listRowBackground(Color.paper)
                .listRowInsets(EdgeInsets(top: Space.x3, leading: Space.x3, bottom: Space.x3, trailing: Space.x3))
        } header: {
            Text("LaTeX code").latexHeader()
        }
    }

    @ViewBuilder
    private var templateSection: some View {
        Section {
            Picker("Preset", selection: templateNameBinding) {
                ForEach(DocTemplate.presets) { p in
                    Text(p.name).tag(p.name)
                }
            }
            .foregroundStyle(Color.ink)
            .listRowBackground(Color.paper)
        } header: {
            Text("Template").latexHeader()
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            Text(diagnosticLine)
                .font(.footnote.monospaced())
                .foregroundStyle(Color.textSecondary)
                .listRowBackground(Color.paper)

            Button {
                UIPasteboard.general.string = assembled
            } label: {
                Label("Copy for Overleaf", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .prominentButton()
            .disabled(assembled.isEmpty)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Space.x2, leading: 0, bottom: Space.x2, trailing: 0))
            .accessibilityIdentifier("latex.copy")

            Button {
                shareTex()
            } label: {
                Label("Share .tex", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.mathNotes(.secondary))
            .disabled(assembled.isEmpty)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Space.x2, leading: 0, bottom: Space.x2, trailing: 0))
            .accessibilityIdentifier("latex.share")
        }
    }

    private var templateNameBinding: Binding<String> {
        Binding(
            get: { template.name },
            set: { name in
                if let p = DocTemplate.presets.first(where: { $0.name == name }) {
                    template = p
                }
            }
        )
    }

    private var shareBoxBinding: Binding<ShareBox?> {
        Binding(
            get: { shareURL.map(ShareBox.init) },
            set: { shareURL = $0?.url }
        )
    }

    private var assembledSummary: String {
        if assembled.isEmpty {
            return "(nothing yet)"
        } else {
            return "\(assembled.count) characters"
        }
    }
    
    private var diagnosticLine: String {
        let firstLine = assembled.split(separator: "\n").first.map(String.init) ?? ""
        return "\(template.name) · \(template.fontSize)pt · \(template.margin)in · \(assembledSummary) · \(firstLine)"
    }

    private func assemble() {
        var bodies: [String] = []
        for page in document.pages {
            if let saved = PageLatexStore.read(document: document, page: page), !saved.body.isEmpty {
                bodies.append(saved.body)
            }
        }
        let joined = bodies.joined(separator: "\n\n")
        assembled = LatexTidy.document(joined, title: document.title, template: template)
    }

    private func shareTex() {
        let safe: String
        if document.title.isEmpty {
            safe = "notes"
        } else {
            safe = document.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).tex")
        try? assembled.write(to: url, atomically: true, encoding: .utf8)
        shareURL = url
    }
}

// MARK: - Code

private struct PageCode: Identifiable {
    let id: UUID
    let number: Int
    let body: String
}

/// LaTeX in a monospaced, selectable block that scrolls sideways for long lines.
struct LatexCodeBox: View {
    let code: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(verbatim: code)
                .font(.footnote.monospaced())
                .foregroundStyle(Color.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .padding(Space.x3)
        }
        .background(Color.well, in: RoundedRectangle(cornerRadius: Radius.bar, style: .continuous))
        .accessibilityIdentifier("latex.code")
    }
}

/// One page's converted LaTeX, with a way to copy it.
private struct LatexCodeSheet: View {
    let title: String
    let code: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x4) {
                    LatexCodeBox(code: code.isEmpty ? String(localized: "Nothing was recognised on this page.") : code)
                    Button {
                        UIPasteboard.general.string = code
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy LaTeX", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .prominentButton()
                    .disabled(code.isEmpty)
                    .accessibilityIdentifier("latex.page.copy")
                }
                .padding(Space.x5)
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .barGround(.surface)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.mathNotes(.primary, inBar: true))
                }
                .boardBackground()
            }
        }
        .tint(Color.accentColor)
        .presentationCornerRadius(Radius.sheet)
    }
}

// MARK: - MathNotes styling

private extension View {
    /// The LaTeX sheets on the app's surface, with paper rows.
    func latexSheetStyle() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.surface.ignoresSafeArea())
            .foregroundStyle(Color.ink)
    }

    func latexHeader() -> some View {
        metaStyle(.footnote)
            .textCase(nil)
    }
}

// MARK: - Page status & per-page storage

enum PageStatus { case empty, notConverted, converted, changed }

enum PageLatexStore {
    private static func url(_ document: NotebookDocument, _ page: NotebookPage) -> URL {
        document.package.assetsDirectory.appendingPathComponent("\(page.id.uuidString).latex.json")
    }

    struct Saved: Codable {
        var body: String
        var title: String
        var inkSignature: String
        var date: Date
        // Quality from the built-in verify-and-fix pipeline (older files decode without these).
        var status: String?
        var issues: [String]?
        var model: String?
        var attempts: Int?
    }

    static func read(document: NotebookDocument, page: NotebookPage) -> Saved? {
        let u = url(document, page)
        guard let data = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    static func write(document: NotebookDocument, page: NotebookPage,
                      body: String, title: String, signature: String,
                      status: String? = nil, issues: [String]? = nil,
                      model: String? = nil, attempts: Int? = nil) {
        let s = Saved(body: body, title: title, inkSignature: signature, date: .now,
                      status: status, issues: issues, model: model, attempts: attempts)
        guard let d = try? JSONEncoder().encode(s) else { return }
        try? d.write(to: url(document, page), options: .atomic)
    }
}

extension PKDrawing {
    var inkSignature: String {
        if strokes.isEmpty { return "empty" }
        var points = 0
        var col = 0.0
        for s in strokes {
            points += s.path.count
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            s.ink.color.getRed(&r, green: &g, blue: &b, alpha: &a)
            col += Double(r + 2 * g + 3 * b)
        }
        let bb = bounds
        let minX = Int(bb.minX)
        let minY = Int(bb.minY)
        let maxX = Int(bb.maxX)
        let maxY = Int(bb.maxY)
        return "\(strokes.count)-\(points)-\(Int(col * 10))-\(minX)-\(minY)-\(maxX)-\(maxY)"
    }
}
