import Foundation

// The LaTeX preamble settings used by LatexTidy.preamble(...).
// This replaces the DocTemplate that lived in PageLatex.swift in your old app.
// Stored in UserDefaults so a settings screen can edit it later.

// MARK: - Document templates

struct DocTemplate: Codable, Equatable, Identifiable {
    var name = "Article"
    var fontSize = 12            // 10, 11, 12
    var paper = "a4paper"        // a4paper / letterpaper
    var margin = 1.0             // inches
    var lineSpread = 1.0
    var parSkip = 0.8            // em between paragraphs
    var indent = false
    var twoColumn = false
    var showTitle = true
    var showDate = false
    var numberPages = true
    var author = ""
    var header = ""
    var id: String { name }

    static let presets: [DocTemplate] = [
        DocTemplate(),
        DocTemplate(name: "Homework", fontSize: 11, margin: 0.9, header: "Homework"),
        DocTemplate(name: "Lecture notes", fontSize: 11, margin: 0.8, parSkip: 0.6, showDate: true),
        DocTemplate(name: "Compact (2 columns)", fontSize: 10, margin: 0.6, parSkip: 0.4, twoColumn: true, showTitle: false),
        DocTemplate(name: "Classic (indented)", fontSize: 12, lineSpread: 1.3, parSkip: 0, indent: true),
    ]

    private static let cur = "docTemplate.current", sav = "docTemplate.saved"
    static func load() -> DocTemplate {
        guard let d = UserDefaults.standard.data(forKey: cur),
              let t = try? JSONDecoder().decode(DocTemplate.self, from: d) else { return DocTemplate() }
        return t
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.cur) }
    }
    static func loadSaved() -> [DocTemplate] {
        guard let d = UserDefaults.standard.data(forKey: sav),
              let a = try? JSONDecoder().decode([DocTemplate].self, from: d) else { return [] }
        return a
    }
    static func storeSaved(_ a: [DocTemplate]) {
        if let d = try? JSONEncoder().encode(a) { UserDefaults.standard.set(d, forKey: sav) }
    }
}
