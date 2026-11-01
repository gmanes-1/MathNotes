import SwiftUI
import Combine
import UIKit
import WebKit
import UniformTypeIdentifiers
import llama

// Replaces the previous LatexEngine.swift (same file name).
// This version runs GLM-OCR (a handwriting-to-LaTeX model) with llama.cpp instead of Gemma/MediaPipe.
//
// Needs PageLatex.swift (it defines DocTemplate, which the document template uses).
// In your MAIN file you must DELETE the old `struct ModelSetupView: View { ... }` (it is redefined below).
// The old `ModelPaths` enum there is no longer used; it can stay or go.

// MARK: - Where the two model files live inside the app

nonisolated enum GlmPaths {
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    static var model: URL { dir.appendingPathComponent("glm-ocr.gguf") }
    static var mmproj: URL { dir.appendingPathComponent("glm-ocr-mmproj.gguf") }
    static var filesExist: Bool {
        FileManager.default.fileExists(atPath: model.path) && FileManager.default.fileExists(atPath: mmproj.path)
    }
}

// MARK: - Prompt (the model was fine-tuned on exactly this instruction; do not reword it)

nonisolated private let glmTask = "OCR this handwritten math page. Convert ONLY the handwritten mathematical content into a complete, compilable LaTeX document. Ignore printed text, student info, page numbers, cancelled work and rough work. Output only LaTeX."

// GLM-OCR chat format. The image marker is replaced by the picture's tokens by llama.cpp (mtmd).
// If the output looks wrong, this is the first place to look.
nonisolated private func glmPrompt() -> String {
    let marker = String(cString: mtmd_default_marker())
    return "[gMASK]<sop><|user|>\n\(marker)\(glmTask)<|assistant|>\n"
}

// MARK: - Turns model output into a complete, compilable document (Overleaf-ready)

enum LatexTidy {

    /// Preamble built from the chosen template (font, paper, margins, spacing, header, theorems...).
    static func preamble(_ t: DocTemplate) -> String {
        var s = """
        \\documentclass[\(t.fontSize)pt,\(t.paper)\(t.twoColumn ? ",twocolumn" : "")]{article}
        \\usepackage[margin=\(String(format: "%.1f", t.margin))in]{geometry}
        \\usepackage[T1]{fontenc}
        \\usepackage{amsmath,amssymb,amsfonts,mathtools,amsthm,cancel,xcolor,enumitem,setspace}
        \\setstretch{\(String(format: "%.2f", t.lineSpread))}
        \\setlength{\\parindent}{\(t.indent ? "1.5em" : "0pt")}
        \\setlength{\\parskip}{\(String(format: "%.1f", t.parSkip))em}

        """
        if !t.header.isEmpty {
            s += "\\usepackage{fancyhdr}\n\\setlength{\\headheight}{14pt}\n\\pagestyle{fancy}\n\\fancyhead[L]{\(cleanTitle(t.header))}\n\\fancyhead[R]{}\n"
            if !t.numberPages { s += "\\fancyfoot{}\n" }
        } else if !t.numberPages {
            s += "\\pagestyle{empty}\n"
        }
        s += """
        \\theoremstyle{plain}
        \\newtheorem{theorem}{Theorem}
        \\newtheorem{lemma}[theorem]{Lemma}
        \\newtheorem{proposition}[theorem]{Proposition}
        \\newtheorem{corollary}[theorem]{Corollary}
        \\theoremstyle{definition}
        \\newtheorem{definition}[theorem]{Definition}
        \\newtheorem{example}[theorem]{Example}
        \\theoremstyle{remark}
        \\newtheorem*{remark}{Remark}
        """
        return s
    }

    struct Result { var title: String; var body: String }

    /// Complete .tex file: copy-paste into Overleaf's main.tex and it compiles.
    static func document(_ body: String, title: String = "", template: DocTemplate = .load()) -> String {
        let t = cleanTitle(title)
        var head = ""
        if template.showTitle, !t.isEmpty {
            head = "\n\\title{\(t)}\n\\author{\(cleanTitle(template.author))}\n\\date{\(template.showDate ? "\\today" : "")}"
        }
        let make = head.isEmpty ? "" : "\\maketitle\n\n"
        return preamble(template) + head + "\n\n\\begin{document}\n\n" + make
            + (body.isEmpty ? "% nothing recognised" : body)
            + "\n\n\\end{document}\n"
    }

    /// Finds the title ("TITLE: ..." line or \title{...}) and cleans the body.
    static func parse(_ raw: String) -> Result {
        var title = ""
        var rest: [String] = []
        for line in raw.components(separatedBy: "\n") {
            let k = line.trimmingCharacters(in: .whitespaces)
            if title.isEmpty, k.uppercased().hasPrefix("TITLE:") {
                title = String(k.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else {
                rest.append(line)
            }
        }
        if title.isEmpty,
           let re = try? NSRegularExpression(pattern: #"\\title\{([^}]*)\}"#),
           let m = re.firstMatch(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) {
            title = (raw as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
        return Result(title: title, body: body(rest.joined(separator: "\n")))
    }

    // Makes any text safe to use inside \title{...}.
    static func cleanTitle(_ t: String) -> String {
        var s = t.replacingOccurrences(of: "$", with: "")
        for c in ["\\", "{", "}", "*"] { s = s.replacingOccurrences(of: c, with: "") }
        for c in ["&", "%", "#", "_"] { s = s.replacingOccurrences(of: c, with: "\\" + c) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Cleans raw model output into a body that compiles inside our own preamble.
    static func body(_ raw: String) -> String {
        var t = raw
        for fence in ["```latex", "```tex", "```"] { t = t.replacingOccurrences(of: fence, with: "") }
        if let a = t.range(of: "\\begin{document}") { t = String(t[a.upperBound...]) }
        if let b = t.range(of: "\\end{document}") { t = String(t[..<b.lowerBound]) }

        // Drop preamble-ish lines, and lines the model repeats in a loop.
        let drop = ["\\documentclass", "\\usepackage", "\\title", "\\author", "\\date", "\\maketitle",
                    "\\newtheorem", "\\theoremstyle", "\\setlength", "\\geometry"]
        var counts: [String: Int] = [:], lines: [String] = []
        for line in t.components(separatedBy: "\n") {
            let k = line.trimmingCharacters(in: .whitespaces)
            if drop.contains(where: { k.hasPrefix($0) }) { continue }
            if k.count > 6, !k.hasPrefix("\\begin"), !k.hasPrefix("\\end") {
                counts[k, default: 0] += 1
                if counts[k]! > 3 { continue }
            }
            lines.append(balanceDollars(line))
        }
        var s = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // Unescaped % and # would break compilation (% even comments out the rest of the line).
        s = s.replacingOccurrences(of: #"(?<!\\)([%#])"#, with: #"\\$1"#, options: .regularExpression)

        s = balanceBraces(s)
        s = balanceDisplay(s)
        s = balanceEnvironments(s)
        return s
    }

    // MARK: Paragraphs, spacing, lists, bold

    /// Blank lines inside one band are not paragraph breaks (only real gaps in the ink are).
    static func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: #"\n[ \t]*(\n[ \t]*)+"#, with: "\n", options: .regularExpression)
    }

    private static func depthDelta(_ l: String) -> Int {
        var d = 0
        for env in ["equation", "align", "alignat", "flalign", "gather", "multline", "displaymath", "eqnarray"] {
            d += l.components(separatedBy: "\\begin{\(env)").count - 1
            d -= l.components(separatedBy: "\\end{\(env)").count - 1
        }
        d += l.components(separatedBy: "\\[").count - 1
        d -= l.components(separatedBy: "\\]").count - 1
        return d
    }

    /// Removes spacing commands and trailing \\ on text lines; turns "1)", "a)", "1." and "-" lines into lists.
    static func layout(_ body: String) -> String {
        let s0 = body.replacingOccurrences(
            of: #"\\(?:vspace|hspace)\*?\{[^}]*\}|\\(?:bigskip|medskip|smallskip|newline)\b"#,
            with: "", options: .regularExpression)

        var lines: [(text: String, math: Bool)] = []
        var depth = 0, dd = false
        for raw in s0.components(separatedBy: "\n") {
            var l = raw
            let wasMath = depth > 0 || dd
            depth = max(0, depth + depthDelta(l))
            if (l.components(separatedBy: "$$").count - 1) % 2 == 1 { dd.toggle() }
            let touches = wasMath || depth > 0 || dd
            if !touches {
                l = l.replacingOccurrences(of: #"\s*\\\\(\[[^\]]*\])?\s*$"#, with: "", options: .regularExpression)
            }
            lines.append((l, touches))
        }

        let patterns = [#"^\s*\(?(\d{1,2})\)\s+(.+)$"#,        // 0: 1)  (1)
                        #"^\s*(\d{1,2})\.\s+(.+)$"#,            // 1: 1.
                        #"^\s*\(?([a-h])\)\s+(.+)$"#,           // 2: a)  (a)
                        #"^\s*(?:[-•–]|\\textbullet)\s+(.+)$"#] // 3: bullet
        let res = patterns.map { try! NSRegularExpression(pattern: $0) }
        func item(_ l: String) -> (kind: Int, label: String, text: String)? {
            let ns = l as NSString
            for (k, re) in res.enumerated() {
                if let m = re.firstMatch(in: l, range: NSRange(location: 0, length: ns.length)) {
                    let text = ns.substring(with: m.range(at: m.numberOfRanges - 1))
                    let label = k == 3 ? "" : ns.substring(with: m.range(at: 1))
                    return (k, label, text)
                }
            }
            return nil
        }

        var out: [String] = []
        var i = 0
        while i < lines.count {
            let (t, m) = lines[i]
            guard !m, let first = item(t) else { out.append(t); i += 1; continue }
            var items = [first.text]
            var j = i + 1
            while j < lines.count {
                if lines[j].math { break }
                let tj = lines[j].text.trimmingCharacters(in: .whitespaces)
                if tj.isEmpty {
                    var k = j
                    while k < lines.count, lines[k].text.trimmingCharacters(in: .whitespaces).isEmpty { k += 1 }
                    if k < lines.count, !lines[k].math, let nx = item(lines[k].text), nx.kind == first.kind {
                        items.append(nx.text); j = k + 1; continue
                    }
                    break
                }
                if let nx = item(tj), nx.kind == first.kind { items.append(nx.text) }
                else if item(tj) != nil || tj.hasPrefix("\\") { break }
                else { items[items.count - 1] += " " + tj }
                j += 1
            }
            let start = Int(first.label) ?? 1
            let opt: String
            switch first.kind {
            case 0: opt = "[label=\\arabic*)" + (start != 1 ? ",start=\(start)" : "") + "]"
            case 1: opt = start != 1 ? "[start=\(start)]" : ""
            case 2: opt = "[label=\\alph*)]"
            default: opt = ""
            }
            let env = first.kind == 3 ? "itemize" : "enumerate"
            out.append("\\begin{\(env)}\(opt)")
            items.forEach { out.append("  \\item " + $0) }
            out.append("\\end{\(env)}")
            i = j
        }
        return out.joined(separator: "\n")
    }

    /// `emph` = the recognition of the emphasised ink only (other colour / highlighter).
    ///  - A WHOLE line that is emphasised is a title (headers are usually written in another colour):
    ///    it becomes \section*{...} ("2.1 ..." numbering picks sub-levels), NOT bold text.
    ///  - Any other emphasised phrase inside a sentence gets \textbf{}.
    static func embolden(_ body: String, using emph: String) -> String {
        func norm(_ s: String) -> String {
            s.replacingOccurrences(of: #"\\(?:textbf|textit|underline|emph)\{|\}"#, with: "", options: .regularExpression)
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
        }
        func similar(_ a: String, _ b: String) -> Bool {
            guard a.count >= 3, b.count >= 3 else { return false }
            if a == b { return true }
            let (big, small) = a.count >= b.count ? (a, b) : (b, a)
            return big.contains(small) && Double(small.count) >= 0.85 * Double(big.count)
        }

        // Lines in the emphasised OCR that are short and title-shaped: candidates for bold PHRASES,
        // not headings — headings were already handled by the band score before we got here.
        let emphPhrases = emph.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 && $0.count <= 60 && !$0.contains("$") && !$0.contains("\\") }

        var out = body

        /// Wrap the first matching occurrence, but never inside an existing \textbf{} or a section title.
        func wrapFirst(_ phrase: String) -> Bool {
            var from = out.startIndex
            while let r = out.range(of: phrase, options: .caseInsensitive, range: from..<out.endIndex) {
                let before = out[..<r.lowerBound]
                let lineStart = before.lastIndex(of: "\n").map { out.index(after: $0) } ?? out.startIndex
                let linePrefix = out[lineStart..<r.lowerBound]
                // Skip if already inside \textbf{...} or a sectioning command.
                if before.hasSuffix("\\textbf{") || before.hasSuffix("\\")
                    || linePrefix.range(of: #"^\\(?:sub)*section"#, options: .regularExpression) != nil {
                    from = r.upperBound
                    continue
                }
                out.replaceSubrange(r, with: "\\textbf{\(out[r])}")
                return true
            }
            return false
        }

        for raw in emphPhrases {
            // Skip anything that looks like a heading — heading() already promoted it, and we must not bold it twice.
            if heading(raw, geometry: 3, level: 2) != nil { continue }
            // Whole-line match first.
            if !wrapFirst(raw) {
                // Then individual significant words (only if the whole line failed and it's a short phrase).
                let words = raw.split(separator: " ").map(String.init).filter { $0.count >= 4 }
                if words.count <= 2 { for w in words { _ = wrapFirst(w) } }
            }
        }
        return out
    }

    /// A heading read from one line of recognised text.
    /// `level` is set only when the text itself says it (numbering "2.1", "\subsection", "##"); otherwise the ink decides.
    struct HeadingInfo: Equatable {
        var title: String
        var level: Int?
        var caps: Bool
    }

    private static func groups(_ pattern: String, _ s: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    /// Words that, at the start of a short line, announce a heading (English and Italian).
    private static let headingWords = #"^(?:chapter|section|part|lecture|lesson|unit|topic|module|capitolo|sezione|parte|lezione|argomento|paragrafo|unità|modulo)\b"#

    /// Decides whether the recognised text of a ONE-LINE band is a heading.
    /// `geometry` = evidence from the ink (underline, bigger writing, centred, alone on its lines).
    /// Text adds its own evidence: the model wrote a sectioning command, markdown "#", wrapped the whole
    /// line in \textbf / \underline / \large, or the line starts with "Chapter", "Lecture", "Capitolo"...
    /// Needs 2 points in total, so a single weak ink signal is never enough on its own.
    static func headingInfo(_ raw: String, geometry: Int) -> HeadingInfo? {
        var t = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: #"\s*\\\\\s*$"#, with: "", options: .regularExpression)
        guard !t.isEmpty, t.count <= 160 else { return nil }

        // 1. The model already wrote a heading: trust its level.
        if let g = groups(#"^\\((?:sub){0,2})section\*?\s*\{(.*)\}\s*$"#, t) {
            let level = g[1].count / 3 + 1
            let title = tidyTitle(g[2])
            return title.isEmpty ? nil : HeadingInfo(title: title, level: level, caps: isCaps(title))
        }
        if let g = groups(#"^(#{1,3})\s+(.+?)\s*#*$"#, t) {
            let title = tidyTitle(stripWrappers(g[2]).text)
            return title.isEmpty ? nil : HeadingInfo(title: title, level: g[1].count, caps: isCaps(title))
        }

        // 2. Unwrap \textbf{...}, \underline{...}, {\bf ...}, $\text{...}$, **...**, \Large ...
        let unwrapped = stripWrappers(t)
        t = unwrapped.text
        var evidence = geometry + (unwrapped.wrapped ? 2 : 0)
        if t.range(of: headingWords, options: [.regularExpression, .caseInsensitive]) != nil { evidence += 2 }
        guard evidence >= 2 else { return nil }

        // 3. Short.
        let words = t.split(separator: " ")
        guard !words.isEmpty, t.count <= 70, words.count <= 10 else { return nil }

        // 4. Mostly words: a little inline maths is fine ("Limits in $\mathbb{R}^n$"), formulas are not.
        if t.contains("$$") || t.contains("\\[") || t.contains("\\begin") { return nil }
        let inline = #"\$[^$]*\$|\\\([^)]*\\\)"#
        let mathChars = (try? NSRegularExpression(pattern: inline))?
            .matches(in: t, range: NSRange(location: 0, length: (t as NSString).length))
            .reduce(0) { $0 + $1.range.length } ?? 0
        let plain = t.replacingOccurrences(of: inline, with: " ", options: .regularExpression)
        guard mathChars <= 24, plain.filter(\.isLetter).count >= 3 else { return nil }
        guard !plain.contains("="), !plain.contains("$") else { return nil }
        // Accents (\'e, \`a, \"o...) and \& are text; any other command outside maths is not a heading.
        if plain.replacingOccurrences(of: #"\\['`^"~=.]\{?[A-Za-z]\}?|\\&"#, with: "", options: .regularExpression)
            .range(of: #"\\[A-Za-z]+"#, options: .regularExpression) != nil { return nil }

        // 5. Starts with a capital or a number; handwriting read in lowercase is let through only on strong ink evidence.
        guard let first = t.first else { return nil }
        if first.isLowercase {
            guard evidence >= 4 else { return nil }
            t = first.uppercased() + t.dropFirst()
        } else if !(first.isUppercase || first.isNumber || first == "$") {
            return nil
        }

        // 6. Not an environment opener ("Definition:", "Theorem 2.1", "Proof.").
        let firstWord = String(words[0]).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".:,;()"))
        if envNames[firstWord] != nil { return nil }

        // 7. Numbering decides the level. A numbered line needs real evidence, or it is a list item ("1. Compute...").
        var level: Int?
        if let g = groups(#"^(\d+(?:\.\d+){0,2})\s*[.)]?\s+(.+)$"#, t) {
            guard evidence >= 3 || g[1].contains(".") && evidence >= 2 && !t.hasPrefix(g[1] + ". ") else { return nil }
            level = min(3, g[1].components(separatedBy: ".").filter { !$0.isEmpty }.count)
        }

        // 8. Trailing punctuation. "Integrals:" and "What is a limit?" are headings on clear ink; a full stop or comma is a sentence.
        if let last = t.last, ".,;:?!".contains(last) {
            switch last {
            case ":" where evidence >= 3: t.removeLast()
            case "?" where evidence >= 3: break
            case "." where level != nil && t.range(of: #"\d\.$"#, options: .regularExpression) != nil: break
            default: return nil
            }
        }

        let title = tidyTitle(t)
        return title.isEmpty ? nil : HeadingInfo(title: title, level: level, caps: isCaps(title))
    }

    /// Removes formatting the model puts around a whole line. `wrapped` = something was removed.
    private static func stripWrappers(_ s: String) -> (text: String, wrapped: Bool) {
        var t = s.trimmingCharacters(in: .whitespaces)
        var wrapped = false
        let patterns = [
            #"^\\(?:textbf|textit|textsc|textup|underline|uline|uuline|emph|text|textrm|mathbf|mathrm|boldsymbol)\s*\{(.*)\}$"#,
            #"^\{\\(?:bf|bfseries|it|itshape|sc|scshape|large|Large|LARGE|huge|Huge)\s+(.*)\}$"#,
            #"^\$\s*\\(?:text|textbf|mathrm|mathbf|underline)\s*\{(.*)\}\s*\$$"#,
            #"^\*\*(.+)\*\*$"#,
            #"^__(.+)__$"#,
            #"^\\(?:large|Large|LARGE|huge|Huge|bfseries|centering|noindent)\s+(.*)$"#,
            #"^\\begin\{center\}\s*(.*?)\s*\\end\{center\}$"#,
        ]
        var changed = true
        while changed {
            changed = false
            for p in patterns {
                if let g = groups(p, t), balanced(g[1]) {
                    t = g[1].trimmingCharacters(in: .whitespaces)
                    wrapped = true
                    changed = true
                }
            }
        }
        // Bold/underline pieces left inside ("\textbf{Limits} and continuity") are just text in a title.
        t = t.replacingOccurrences(of: #"\\(?:textbf|underline|uline|emph|textit)\{([^{}]*)\}"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "**", with: "")
        return (t, wrapped)
    }

    private static func balanced(_ s: String) -> Bool {
        var depth = 0, prev: Character = " "
        for ch in s {
            if prev != "\\" {
                if ch == "{" { depth += 1 } else if ch == "}" { depth -= 1; if depth < 0 { return false } }
            }
            prev = ch
        }
        return depth == 0
    }

    private static func isCaps(_ t: String) -> Bool {
        let letters = t.replacingOccurrences(of: #"\$[^$]*\$"#, with: "", options: .regularExpression).filter(\.isLetter)
        return letters.count >= 3 && letters == letters.uppercased()
    }

    private static func tidyTitle(_ t: String) -> String {
        var s = t.trimmingCharacters(in: CharacterSet(charactersIn: " ;,").union(.whitespacesAndNewlines))
        s = s.replacingOccurrences(of: #"(?<!\\)&"#, with: #"\\&"#, options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return balanceBraces(s)
    }

    /// "\section*{...}", "\subsection*{...}" or "\subsubsection*{...}".
    static func command(_ title: String, level: Int) -> String {
        let cmd = ["section", "subsection", "subsubsection"][max(1, min(3, level)) - 1]
        return "\\\(cmd)*{\(title)}"
    }

    /// Kept for callers that want the finished command. `level` is used when the text doesn't decide it.
    static func heading(_ raw: String, geometry: Int, level hint: Int) -> String? {
        guard let h = headingInfo(raw, geometry: geometry) else { return nil }
        return command(h.title, level: h.level ?? (h.caps && hint <= 1 ? 1 : hint))
    }

    /// Headings the model wrote inside a longer band: "# Title", "\section{...}", or a line that is entirely
    /// \textbf{...} / \underline{...}. They become real headings on their own paragraph. Maths is left alone.
    static func promoteHeadings(_ body: String) -> String {
        var out: [String] = []
        var depth = 0, dd = false
        var hasTop = body.range(of: #"\\section\*?\{"#, options: .regularExpression) != nil
        let starts = #"^\s*(?:#{1,3}\s|\\(?:sub){0,2}section|\\textbf\{|\\underline\{|\\uline\{|\{\\bf\s|\*\*|\\Large|\\large|\\LARGE)"#
        for line in body.components(separatedBy: "\n") {
            let inMath = depth > 0 || dd
            depth = max(0, depth + depthDelta(line))
            if (line.components(separatedBy: "$$").count - 1) % 2 == 1 { dd.toggle() }
            guard !inMath, depth == 0, !dd,
                  line.range(of: starts, options: .regularExpression) != nil,
                  let h = headingInfo(line, geometry: 0) else { out.append(line); continue }
            let level = h.level ?? (h.caps || !hasTop ? 1 : 2)
            if level == 1 { hasTop = true }
            if let last = out.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { out.append("") }
            out.append(command(h.title, level: level))
            out.append("")
        }
        return out.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // MARK: Definition / theorem / proof environments

    /// Every word or abbreviation that opens an environment ("Def.", "Thm 2.1", "Prop:", "Pf", "Lem"...).
    private static let envNames: [String: String] = [
        "definition": "definition", "def": "definition", "defn": "definition", "dfn": "definition", "df": "definition",
        "theorem": "theorem", "thm": "theorem", "th": "theorem",
        "lemma": "lemma", "lem": "lemma",
        "proposition": "proposition", "prop": "proposition",
        "corollary": "corollary", "cor": "corollary",
        "remark": "remark", "rmk": "remark", "rem": "remark", "note": "remark",
        "example": "example", "ex": "example", "eg": "example",
        "proof": "proof", "pf": "proof",
    ]
    /// Whole words: also normal English, so "Remark that x..." is NOT a remark box.
    private static let fullWords: Set<String> = ["definition", "theorem", "lemma", "proposition",
                                                 "corollary", "remark", "example", "proof"]
    /// Short or ambiguous: only counted when followed by "." ":" a number or brackets ("Ex 3", "Note:").
    private static let weakKeys: Set<String> = ["note", "ex", "eg", "th", "df", "rem"]

    private struct EnvHeader { var env: String; var name: String; var rest: String }

    private static let headerRegex: NSRegularExpression? = {
        let keys = envNames.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let pattern = #"^\s*(?:\\(?:textbf|textit|underline|emph)\{|\*\*)*\s*("# + keys
            + #")\b\.?\s*(\d+(?:\.\d+)*)?\.?\s*(?:\(([^()]*)\))?\s*(?:\}|\*\*)*\s*[.:]?\s*"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// "Thm 2.1 (Pythagoras). Let x..." -> env theorem, name "Pythagoras", rest "Let x..."
    private static func envHeader(_ p: String) -> EnvHeader? {
        guard let re = headerRegex else { return nil }
        let ns = p as NSString
        guard let m = re.firstMatch(in: p, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let key = ns.substring(with: m.range(at: 1)).lowercased()
        guard let env = envNames[key] else { return nil }
        let header = ns.substring(with: m.range)
        var rest = ns.substring(from: m.range.location + m.range.length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let delimiter = header.contains { ".:()}*\\".contains($0) || $0.isNumber }
        if weakKeys.contains(key), !delimiter { return nil }
        if fullWords.contains(key), !delimiter, let f = rest.first, f.isLowercase { return nil }

        var name = ""
        if m.range(at: 3).location != NSNotFound {
            name = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
            if name.range(of: #"^[\d.\s]*$"#, options: .regularExpression) != nil { name = "" }   // "(1.2)" is a number
        }
        // "Proof of Lemma 3." -> \begin{proof}[Proof of Lemma 3]
        if env == "proof", name.isEmpty,
           let po = try? NSRegularExpression(pattern: #"^(of\s+[^.:\n]{1,40}?)\s*[.:]\s*"#, options: [.caseInsensitive]),
           let pm = po.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)) {
            let r = rest as NSString
            name = "Proof " + r.substring(with: pm.range(at: 1))
            rest = r.substring(from: pm.range.location + pm.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        name = name.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        return EnvHeader(env: env, name: name, rest: balanceBraces(rest))
    }

    /// Makes sure a line that starts with "Def." / "Thm" / "Proof" etc. starts its own paragraph.
    private static func splitAtEnvLines(_ body: String) -> String {
        var out: [String] = []
        var prevBlank = true
        var depth = 0
        for line in body.components(separatedBy: "\n") {
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            let inMath = depth > 0
            depth = max(0, depth + depthDelta(line))
            if !blank, !prevBlank, !inMath, envHeader(line) != nil { out.append("") }
            out.append(line)
            prevBlank = blank
        }
        return out.joined(separator: "\n")
    }

    private static func isSectionLine(_ q: String) -> Bool {
        q.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^\\(?:sub)*section\b"#, options: .regularExpression) != nil
    }

    /// After a definition/theorem: does this paragraph still belong to it?
    /// (starts in lowercase, with a formula, or with a list marker such as "(i)", "a)", "1)", "-")
    private static func isContinuation(_ q: String) -> Bool {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let f = t.first, envHeader(t) == nil, !isSectionLine(t) else { return false }
        if f.isLowercase || f == "$" { return true }
        if t.hasPrefix("\\[") || t.hasPrefix("\\begin{equation") || t.hasPrefix("\\begin{align")
            || t.hasPrefix("\\begin{gather") || t.hasPrefix("\\begin{multline") { return true }
        return t.range(of: #"^(\(?[ivx]+\)|\(?\d{1,2}\)|\(?[a-h]\)|[-•–]\s)"#, options: .regularExpression) != nil
    }

    /// End-of-proof mark (□ ∎ ■ \square \blacksquare \qed, "QED") at the end of a paragraph: removed, and reported.
    private static func stripQED(_ q: String) -> (text: String, ended: Bool) {
        var t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [#"\$?\s*\\(?:square|blacksquare|qedsymbol|qed|Box)\s*\$?\s*$"#,
                        #"\s*[∎□■]\s*$"#,
                        #"\s*\bq\.?\s?e\.?\s?d\.?\s*$"#]
        for pat in patterns {
            if let r = t.range(of: pat, options: [.regularExpression, .caseInsensitive]) {
                t.removeSubrange(r)
                var lines = t.components(separatedBy: "\n")
                if let last = lines.last { lines[lines.count - 1] = balanceDollars(last) }
                return (lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), true)
            }
        }
        return (t, false)
    }

    /// Turns "Def. ...", "Prop: ...", "Thm 2.1 (Name) ...", "Proof. ... ∎" into real environments.
    /// - A definition/theorem/... ends at its paragraph (plus continuation lines: lowercase, formula, list item).
    /// - A header alone on its line ("Def:") takes the next paragraph as its statement.
    /// - A proof runs until its end mark, the next environment or the next section title.
    static func structure(_ body: String) -> String {
        let paragraphs = splitAtEnvLines(body).components(separatedBy: "\n\n")
        var out: [String] = []
        var i = 0
        while i < paragraphs.count {
            let p = paragraphs[i]
            guard let h = envHeader(p) else { out.append(p); i += 1; continue }
            i += 1

            var content: [String] = []
            var closed = false
            func add(_ text: String) {
                if h.env == "proof" {
                    let r = stripQED(text)
                    if !r.text.isEmpty { content.append(r.text) }
                    if r.ended { closed = true }
                } else {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { content.append(t) }
                }
            }

            add(h.rest)
            if h.env == "proof" {
                while !closed, i < paragraphs.count {
                    let q = paragraphs[i]
                    if envHeader(q) != nil || isSectionLine(q) { break }
                    add(q); i += 1
                }
            } else {
                if content.isEmpty, i < paragraphs.count,
                   envHeader(paragraphs[i]) == nil, !isSectionLine(paragraphs[i]) {
                    add(paragraphs[i]); i += 1
                }
                while i < paragraphs.count, isContinuation(paragraphs[i]) { add(paragraphs[i]); i += 1 }
            }

            guard !content.isEmpty else { out.append(p); continue }
            let opt = h.name.isEmpty ? "" : "[\(h.name)]"
            out.append("\\begin{\(h.env)}\(opt)\n" + content.joined(separator: "\n\n") + "\n\\end{\(h.env)}")
        }
        return out.joined(separator: "\n\n")
    }

    // MARK: Safety nets so the file always compiles

    private static func balanceDollars(_ line: String) -> String {
        let stripped = line.replacingOccurrences(of: "\\$", with: "")
        var fixed = line
        if (stripped.components(separatedBy: "$$").count - 1) % 2 == 1 { fixed += "$$" }
        let single = stripped.replacingOccurrences(of: "$$", with: "").filter { $0 == "$" }.count
        if single % 2 == 1 { fixed += "$" }
        return fixed
    }

    private static func balanceBraces(_ s: String) -> String {
        var out = "", depth = 0, prev: Character = " "
        for ch in s {
            if prev != "\\" {
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    if depth == 0 { prev = ch; continue }
                    depth -= 1
                }
            }
            out.append(ch); prev = ch
        }
        return out + String(repeating: "}", count: depth)
    }

    private static func balanceDisplay(_ s: String) -> String {
        let o = s.components(separatedBy: "\\[").count - 1
        let c = s.components(separatedBy: "\\]").count - 1
        return o > c ? s + String(repeating: "\n\\]", count: o - c) : s
    }

    private static let allowedEnvs: Set<String> = [
        "equation", "align", "alignat", "flalign", "gather", "multline", "split", "aligned", "gathered",
        "cases", "array", "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix",
        "tabular", "itemize", "enumerate", "description", "center", "quote",
        "definition", "theorem", "lemma", "proposition", "corollary", "example", "remark", "proof",
    ]

    private static func balanceEnvironments(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\\(begin|end)\{([^}]*)\}"#) else { return s }
        let ns = s as NSString
        var stack: [String] = []
        var strip: [NSRange] = []
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let kind = ns.substring(with: m.range(at: 1))
            let name = ns.substring(with: m.range(at: 2))
            let base = name.hasSuffix("*") ? String(name.dropLast()) : name
            guard allowedEnvs.contains(base) else { strip.append(m.range); continue }
            if kind == "begin" { stack.append(name) }
            else if stack.last == name { stack.removeLast() }
            else { strip.append(m.range) }
        }
        var result = s
        for r in strip.reversed() { result = (result as NSString).replacingCharacters(in: r, with: "") }
        for name in stack.reversed() { result += "\n\\end{\(name)}" }
        return result
    }
}

// MARK: - Crop to the ink and cut into bands: lines, paragraphs, section titles

/// How new paragraphs are detected. Stored in UserDefaults ("paragraphMode"), chosen in the LaTeX sheet.
nonisolated enum ParagraphMode: String {
    case smart       // bigger gap, OR the previous line ended short, OR the line is indented
    case gaps        // only a clearly bigger vertical gap
    case everyLine   // every new line is a new paragraph

    static var stored: ParagraphMode {
        ParagraphMode(rawValue: UserDefaults.standard.string(forKey: "paragraphMode") ?? "") ?? .smart
    }
}

nonisolated struct InkBand {
    let image: UIImage
    let newParagraph: Bool     // this band starts a new paragraph
    let headingScore: Int      // ink evidence that this single line is a section title (0 = none)
    let level: Int             // 1 = section, 2 = subsection (a hint; numbering in the text overrides it)
    var lineCount = 1          // lines of writing in the band
    var ratio: Double = 1      // height of the writing compared with the page's usual line
    var underlined = false
}

nonisolated enum InkSlicer {
    private struct Line {
        var a: Int
        var b: Int
        var textB: Int
        var left: Int
        var right: Int
        var underlined = false
        var width: Int { right - left + 1 }
        var textH: Int { textB - a + 1 }
    }

    /// A trait a line can show. Multiple can apply.
    private struct Traits: OptionSet {
        let rawValue: Int
        static let underlined     = Traits(rawValue: 1 << 2)
        static let bigger         = Traits(rawValue: 1 << 3)
        static let centred        = Traits(rawValue: 1 << 4)
        static let isolated       = Traits(rawValue: 1 << 5)
        static let shortThenBig   = Traits(rawValue: 1 << 6)
        static let short          = Traits(rawValue: 1 << 7)
    }

    private struct Group {
        var a: Int, b: Int, left: Int, right: Int
        var para: Bool
        var score: Int
        var level: Int
        var count: Int
        var ratio: Double
        var underlined: Bool
    }

    static func bands(from image: UIImage, maxRatio: Double = 1.4, mode: ParagraphMode = .smart) -> [InkBand] {
        guard let cg = image.cgImage else {
            return [InkBand(image: image, newParagraph: false, headingScore: 0, level: 2)]
        }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return [] }

        var px = [UInt8](repeating: 255, count: w * h)
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return [InkBand(image: image, newParagraph: false, headingScore: 0, level: 2)] }

        // Rows of ink, and how much ink each row holds (a long horizontal stroke = an underline).
        var rowMin = [Int](repeating: w, count: h)
        var rowMax = [Int](repeating: -1, count: h)
        var rowInk = [Int](repeating: 0, count: h)
        var minX = w, maxX = -1
        for y in 0..<h {
            let base = y * w
            for x in 0..<w where px[base + x] < 200 {
                if x < rowMin[y] { rowMin[y] = x }
                if x > rowMax[y] { rowMax[y] = x }
                rowInk[y] += 1
            }
            if rowMax[y] >= 0 { minX = min(minX, rowMin[y]); maxX = max(maxX, rowMax[y]) }
        }
        guard maxX >= 0 else { return [] }

        // Runs of ink
        let mergeGap = max(8, h / 150)
        var runs: [Line] = []
        var y = 0
        while y < h {
            if rowMax[y] >= 0 {
                var end = y, gap = 0, j = y + 1
                while j < h && gap <= mergeGap {
                    if rowMax[j] >= 0 { end = j; gap = 0 } else { gap += 1 }
                    j += 1
                }
                var l = rowMin[y], r = rowMax[y]
                for k in y...end where rowMax[k] >= 0 { l = min(l, rowMin[k]); r = max(r, rowMax[k]) }
                runs.append(Line(a: y, b: end, textB: end, left: l, right: r))
                y = j
            } else { y += 1 }
        }

        func median(_ a: [Int]) -> Double {
            guard !a.isEmpty else { return 0 }
            let s = a.sorted()
            return Double(s[s.count / 2])
        }

        // An underline drawn touching the letters is in the same run: a near-solid row across
        // the bottom third of the run. The text height then stops above it.
        for i in runs.indices {
            let r = runs[i]
            let height = r.b - r.a + 1
            guard height >= 12, r.width >= 40 else { continue }
            let from = r.b - max(2, height / 3)
            for yy in stride(from: r.b, through: max(r.a + height / 2, from), by: -1)
            where Double(rowInk[yy]) >= 0.7 * Double(r.width) {
                runs[i].underlined = true
                var top = yy
                while top > r.a, Double(rowInk[top - 1]) >= 0.5 * Double(r.width) { top -= 1 }
                runs[i].textB = max(r.a, top - 1)
                break
            }
        }

        // Attach underlines: a thin wide run right below a text line
        let medH0 = max(1, median(runs.map { $0.textH }))
        var merged: [Line] = []
        for r in runs {
            if let p = merged.last, !p.underlined,
               Double(r.b - r.a + 1) < 0.5 * medH0,
               Double(r.a - p.b - 1) < 1.0 * medH0,
               r.left < p.right, r.right > p.left,
               Double(r.width) >= 0.4 * Double(p.width) {
                merged[merged.count - 1].b = r.b
                merged[merged.count - 1].underlined = true
                merged[merged.count - 1].left = min(p.left, r.left)
                merged[merged.count - 1].right = max(p.right, r.right)
            } else {
                merged.append(r)
            }
        }
        let lines = merged
        let n = lines.count
        guard n > 0 else { return [] }

        // Page stats. The usual line height ignores the underlined lines, which are mostly titles.
        let plainH = lines.filter { !$0.underlined }.map { $0.textH }
        let medH = max(1, median(plainH.isEmpty ? lines.map { $0.textH } : plainH))
        let gapList = (1..<max(1, n)).map { lines[$0].a - lines[$0 - 1].b - 1 }
        let medGap = gapList.isEmpty ? 0.4 * medH : max(1, median(gapList))
        let widths = lines.map { $0.width }.sorted()
        let bodyW = Double(widths[min(widths.count - 1, Int(Double(widths.count) * 0.85))])
        let inkW = Double(maxX - minX + 1)
        let leftMargin = lines.map { $0.left }.min() ?? minX
        let centerX = Double(minX + maxX) / 2

        func ratio(_ i: Int) -> Double { Double(lines[i].textH) / medH }
        func gapBefore(_ i: Int) -> Double { i == 0 ? .infinity : Double(lines[i].a - lines[i - 1].b - 1) }
        func gapAfter(_ i: Int) -> Double { i == n - 1 ? .infinity : gapBefore(i + 1) }
        func bigGap(_ g: Double) -> Bool { (g > 1.6 * medGap && g > 0.5 * medH) || g > 1.5 * medH }
        func divisionGap(_ g: Double) -> Bool { g > 2.4 * medGap || g > 1.8 * medH }
        let isoGap = max(1.5 * medGap, 0.6 * medH)

        // Traits of every line
        var traits: [Traits] = Array(repeating: [], count: n)
        for i in 0..<n {
            let l = lines[i]
            var t: Traits = []
            if l.underlined { t.insert(.underlined) }
            if ratio(i) >= 1.15 { t.insert(.bigger) }
            if Double(l.width) < 0.6 * bodyW { t.insert(.short) }
            if Double(l.width) < 0.8 * inkW, abs(Double(l.left + l.right) / 2 - centerX) < 0.08 * inkW { t.insert(.centred) }
            if gapBefore(i) >= isoGap, gapAfter(i) >= isoGap { t.insert(.isolated) }
            if Double(l.width) < 0.55 * bodyW, ratio(i) >= 1.15, divisionGap(gapAfter(i)) { t.insert(.shortThenBig) }
            traits[i] = t
        }

        // A trait that runs for 3+ consecutive lines is the style of the body, not of headings.
        for bit in [Traits.underlined, .bigger, .centred] {
            var runStart = 0
            for i in 0...n {
                if i < n, traits[i].contains(bit) { continue }
                if i - runStart >= 3 { for k in runStart..<i { traits[k].remove(bit); traits[k].remove(.shortThenBig) } }
                runStart = i + 1
            }
        }

        // Title score and whether the line is a title candidate (it then gets its own band).
        // Underline 3, much bigger 3, bigger 2/1, short-and-big before a division gap 2, alone 1, alone and short 1, centred 1.
        func titleInfo(_ i: Int) -> (score: Int, level: Int, candidate: Bool) {
            let l = lines[i], t = traits[i], r = ratio(i)
            let underlined = t.contains(.underlined)
            if Double(l.width) >= 0.85 * bodyW, !t.contains(.bigger), !underlined { return (0, 2, false) }
            var s = 0
            if underlined { s += 3 }
            if t.contains(.bigger) { s += r >= 1.35 ? 3 : (r >= 1.22 ? 2 : 1) }
            if t.contains(.shortThenBig) { s += 2 }
            if t.contains(.isolated) { s += 1 }
            if t.contains(.isolated), t.contains(.short) { s += 1 }
            if t.contains(.centred), t.contains(.short) { s += 1 }
            let cand = underlined
                || (t.contains(.bigger) && r >= 1.22)
                || (t.contains(.isolated) && (t.contains(.bigger) || t.contains(.short) || t.contains(.centred)))
                || (i == 0 && t.contains(.short) && t.contains(.bigger))
            return (s, (t.contains(.bigger) || underlined) ? 1 : 2, cand)
        }

        // Paragraph starts
        func paragraphStart(_ i: Int) -> Bool {
            guard i > 0 else { return false }
            switch mode {
            case .everyLine: return true
            case .gaps: return bigGap(gapBefore(i))
            case .smart:
                if bigGap(gapBefore(i)) { return true }
                let p = lines[i - 1], l = lines[i]
                let indentStep = max(0.8 * medH, 0.03 * inkW)
                let prevEndedShort = Double(p.width) < 0.7 * bodyW && Double(p.left - leftMargin) < 0.08 * inkW
                let indented = Double(l.left - leftMargin) > indentStep && Double(p.left - leftMargin) <= indentStep
                return prevEndedShort || indented
            }
        }

        // Group lines into bands. A title candidate is always a band of its own.
        let maxBandH = max(240, Int(inkW * maxRatio))
        var groups: [Group] = []
        var lastWasCandidate = false
        for i in 0..<n {
            let l = lines[i]
            let info = titleInfo(i)
            let ps = paragraphStart(i)
            if let g = groups.last, i > 0, !info.candidate, !lastWasCandidate, !ps, l.b - g.a <= maxBandH {
                groups[groups.count - 1].b = l.b
                groups[groups.count - 1].left = min(g.left, l.left)
                groups[groups.count - 1].right = max(g.right, l.right)
                groups[groups.count - 1].count += 1
                groups[groups.count - 1].ratio = max(g.ratio, ratio(i))
            } else {
                groups.append(Group(a: l.a, b: l.b, left: l.left, right: l.right, para: ps,
                                    score: info.candidate ? info.score : 0, level: info.level,
                                    count: 1, ratio: ratio(i), underlined: traits[i].contains(.underlined)))
            }
            lastWasCandidate = info.candidate
        }

        let pad = 20
        return groups.compactMap { g in
            let x0 = max(0, g.left - pad), x1 = min(w, g.right + 1 + pad)
            let y0 = max(0, g.a - pad), y1 = min(h, g.b + 1 + pad)
            guard let c = cg.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { return nil }
            return InkBand(image: UIImage(cgImage: c, scale: 1, orientation: .up),
                           newParagraph: g.para, headingScore: g.score, level: g.level,
                           lineCount: g.count, ratio: g.ratio, underlined: g.underlined)
        }
    }
}
// MARK: - llama.cpp runner (all the C calls live here; runs off the main thread)

nonisolated struct GlmError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

nonisolated final class GlmRunner: @unchecked Sendable {
    private let model: OpaquePointer
    private let mtmd: OpaquePointer
    private let vocab: OpaquePointer

    init(modelPath: String, mmprojPath: String) throws {
        llama_backend_init()
        var mp = llama_model_default_params()
        mp.n_gpu_layers = 99                          // Metal
        guard let m = llama_model_load_from_file(modelPath, mp) else {
            throw GlmError(message: "Could not load the GLM-OCR model file. Re-import it.")
        }
        var tp = mtmd_context_params_default()
        tp.use_gpu = true
        tp.n_threads = 4
        guard let t = mtmd_init_from_file(mmprojPath, m, tp) else {
            llama_model_free(m)
            throw GlmError(message: "Could not load the mmproj file. Re-import it.")
        }
        model = m
        mtmd = t
        vocab = llama_model_get_vocab(m)
    }

    deinit {
        mtmd_free(mtmd)
        llama_model_free(model)
    }

    func run(image: CGImage, onPartial: @escaping (String) -> Void) throws -> String {
        // 1) picture -> RGB bytes on white
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        let drawn: Bool = rgba.withUnsafeMutableBytes { buf in
            guard let c = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            c.setFillColor(UIColor.white.cgColor)
            c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { throw GlmError(message: "Could not prepare the image.") }
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            rgb[i * 3] = rgba[i * 4]; rgb[i * 3 + 1] = rgba[i * 4 + 1]; rgb[i * 3 + 2] = rgba[i * 4 + 2]
        }
        guard let bitmap = rgb.withUnsafeBufferPointer({ mtmd_bitmap_init(UInt32(w), UInt32(h), $0.baseAddress) }) else {
            throw GlmError(message: "Could not create the image for the model.")
        }
        defer { mtmd_bitmap_free(bitmap) }

        // 2) fresh context for this run (freed at the end, so nothing is left over)
        var cp = llama_context_default_params()
        cp.n_ctx = 8192                               // the picture alone is ~1500 tokens
        cp.n_batch = 2048
        cp.n_ubatch = 2048
        guard let lctx = llama_init_from_model(model, cp) else {
            throw GlmError(message: "Not enough memory to start the model.")
        }
        defer { llama_free(lctx) }

        // 3) text + picture -> tokens
        guard let chunks = mtmd_input_chunks_init() else { throw GlmError(message: "Internal error (chunks).") }
        defer { mtmd_input_chunks_free(chunks) }
        var bitmaps: [OpaquePointer?] = [bitmap]
        let prompt = glmPrompt()
        let tok: Int32 = prompt.withCString { cstr in
            var text = mtmd_input_text(text: cstr, text_len: prompt.utf8.count, add_special: false, parse_special: true)
            return bitmaps.withUnsafeMutableBufferPointer { bp in
                mtmd_tokenize(mtmd, chunks, &text, bp.baseAddress, 1)
            }
        }
        guard tok == 0 else { throw GlmError(message: "Could not read the image (code \(tok)).") }

        // 4) feed everything to the model
        var nPast: llama_pos = 0
        let ev = mtmd_helper_eval_chunks(mtmd, lctx, chunks, 0, 0, 2048, true, &nPast)
        guard ev == 0 else { throw GlmError(message: "The model could not process the image (code \(ev)).") }

        // 5) greedy generation (temperature 0, no repBeat penalty, as the model was benchmarked)
        let smpl = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(smpl, llama_sampler_init_greedy())
        defer { llama_sampler_free(smpl) }

        var out = Data()
        var piece = [CChar](repeating: 0, count: 256)
        var n = 0
        while n < 2048 && nPast < 8190 {
            var token = llama_sampler_sample(smpl, lctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            let len = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if len > 0 { out.append(contentsOf: piece[0..<Int(len)].map { UInt8(bitPattern: $0) }) }
            let r = withUnsafeMutablePointer(to: &token) { llama_decode(lctx, llama_batch_get_one($0, 1)) }
            if r != 0 { break }
            nPast += 1; n += 1
            if n % 8 == 0 { onPartial(String(decoding: out, as: UTF8.self)) }
        }
        return String(decoding: out, as: UTF8.self)
    }
}

// MARK: - Engine used by the UI (same name and interface as before)

@MainActor
final class LatexEngine: ObservableObject {
    enum State: Equatable { case needsModel, notLoaded, copying, loading, ready, failed(String) }
    @Published var state: State
    @Published var partial = ""
    @Published var progress = ""
    // Where conversion runs: "cloud" is the built-in managed model (Gemini vision plus a
    // verify-and-fix loop on the MathNotes conversion service) — zero setup, on by default.
    // "device" is the on-device GLM-OCR runner, kept for offline use.
    enum Backend: String { case cloud, device }

    struct Quality: Equatable {
        var status: String      // "verified" | "best_effort" | "empty"
        var issues: [String]
        var model: String
        var attempts: Int
    }

    @Published var backend: Backend
    @Published var lastQuality: Quality?
    private var runner: GlmRunner?
    private var converting = false
    private var observers: [NSObjectProtocol] = []

    init() {
        // Local first: `self.backend` can't be read until every stored property (incl. `state`) is set.
        let chosen = Backend(rawValue: UserDefaults.standard.string(forKey: "latexBackend") ?? "") ?? .cloud
        backend = chosen
        state = chosen == .cloud ? .ready : (GlmPaths.filesExist ? .notLoaded : .needsModel)
        for name in [UIApplication.didReceiveMemoryWarningNotification,
                     UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.unload() }
            })
        }
    }

    /// Switches conversion between the built-in service (default, zero setup) and the on-device model.
    func setBackend(_ b: Backend) {
        backend = b
        UserDefaults.standard.set(b.rawValue, forKey: "latexBackend")
        lastQuality = nil
        if b == .cloud {
            state = .ready
        } else {
            state = GlmPaths.filesExist ? .notLoaded : .needsModel
        }
    }

    func unload() {
        guard !converting, state == .ready else { return }
        runner = nil
        state = .notLoaded
    }

    /// Pick BOTH files at once (the .gguf model and the mmproj .gguf). They are told apart by name.
    func importModels(from urls: [URL]) async {
        runner = nil
        state = .copying
        do {
            try await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                try fm.createDirectory(at: GlmPaths.dir, withIntermediateDirectories: true)
                for src in urls {
                    let access = src.startAccessingSecurityScopedResource()
                    defer { if access { src.stopAccessingSecurityScopedResource() } }
                    let isProjector = src.lastPathComponent.lowercased().contains("mmproj")
                    let dest = isProjector ? GlmPaths.mmproj : GlmPaths.model
                    try? fm.removeItem(at: dest)
                    try fm.copyItem(at: src, to: dest)
                }
            }.value
        } catch {
            state = .failed("Could not copy the files: \(error.localizedDescription)")
            return
        }
        if GlmPaths.filesExist { await load() }
        else { state = .failed("One file is still missing. Import both: the model file and the file starting with mmproj.") }
    }

    func removeModel() {
        runner = nil
        try? FileManager.default.removeItem(at: GlmPaths.model)
        try? FileManager.default.removeItem(at: GlmPaths.mmproj)
        state = .needsModel
    }

    func load() async {
        guard GlmPaths.filesExist else { state = .needsModel; return }
        guard ProcessInfo.processInfo.physicalMemory >= 3_500_000_000 else {
            state = .failed("This device has too little memory for the model.")
            return
        }
        state = .loading
        do {
            let r = try await Task.detached(priority: .userInitiated) {
                try GlmRunner(modelPath: GlmPaths.model.path, mmprojPath: GlmPaths.mmproj.path)
            }.value
            runner = r
            state = .ready
        } catch { state = .failed(error.localizedDescription) }
    }

    /// Reads what is in `image` band by band. Returns the title and a cleaned LaTeX body.
    /// Real gaps in the ink become paragraphs; no \vspace; lists are detected.
    /// Headings: a one-line band is a heading when ink and text together say so (see `LatexTidy.headingInfo`).
    /// Their level comes from numbering or the model's own command first, then from how big they are written
    /// compared with the other headings on the page; with no size difference the first is a section and the rest subsections.
    /// Reads what is in `image`. With the built-in backend (default) the whole page goes to
    /// the conversion service, which verifies and auto-fixes the LaTeX; `context` is the
    /// previous page's body, so notation and numbering stay consistent across pages.
    func convert(_ image: UIImage, context: String? = nil) async throws -> LatexTidy.Result {
        if backend == .cloud {
            return try await convertCloud(image, context: context)
        }
        switch state {
        case .notLoaded, .failed: await load()
        default: break
        }
        if case .failed(let m) = state {
            throw NSError(domain: "latex", code: 2, userInfo: [NSLocalizedDescriptionKey: m])
        }
        guard let runner else {
            throw NSError(domain: "latex", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not ready"])
        }

        let mode = ParagraphMode.stored
        let bands = await Task.detached(priority: .userInitiated) {
            InkSlicer.bands(from: image, maxRatio: 1.4, mode: mode)
        }.value
        if bands.isEmpty { return LatexTidy.Result(title: "", body: "") }

        converting = true
        defer { converting = false; progress = "" }

        struct Part {
            var text: String
            var para: Bool
            var heading: LatexTidy.HeadingInfo?
            var ratio: Double
            var strong: Bool
        }
        var title = ""
        var parts: [Part] = []

        // 1. One part per band.
        for (i, band) in bands.enumerated() {
            progress = bands.count > 1 ? "Reading part \(i + 1) of \(bands.count)…" : ""
            partial = ""
            guard let cg = Self.prepared(band.image) else { continue }
            let raw = try await Task.detached(priority: .userInitiated) { [weak self] () -> String in
                try runner.run(image: cg) { snap in
                    Task { @MainActor in self?.partial = snap }
                }
            }.value
            let r = LatexTidy.parse(raw)
            if title.isEmpty { title = r.title }
            guard !r.body.isEmpty else { continue }
            let text = LatexTidy.collapse(r.body)
            // A one-line band may be a heading; the model sometimes reads one line as two, so allow two short ones.
            let lines = r.body.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let info = band.lineCount == 1 && lines.count <= 2 ? LatexTidy.headingInfo(r.body, geometry: band.headingScore) : nil
            let strong = info.map { $0.level != nil || band.underlined || band.headingScore >= 5 } ?? false
            parts.append(Part(text: text, para: band.newParagraph || info != nil, heading: info, ratio: band.ratio, strong: strong))
        }

        // 2. 3+ headings in a row with nothing between and nothing that clearly marks them: a stylistic body, not headings.
        var k = 0
        while k < parts.count {
            guard parts[k].heading != nil else { k += 1; continue }
            var j = k
            while j < parts.count, parts[j].heading != nil { j += 1 }
            if j - k >= 3, !parts[k..<j].contains(where: \.strong) {
                for m in k..<j { parts[m].heading = nil }
            }
            k = j
        }

        // 3. Levels.
        let heads = parts.indices.filter { parts[$0].heading != nil }
        let sizes = heads.map { parts[$0].ratio }
        let biggest = sizes.max() ?? 1, smallest = sizes.min() ?? 1
        let sized = biggest - smallest >= 0.15
        var hasTop = false
        for index in heads {
            guard let h = parts[index].heading else { continue }
            let level: Int
            if let l = h.level {
                level = l
            } else if sized {
                let r = parts[index].ratio
                level = r >= biggest - 0.1 ? 1 : (r >= biggest - 0.3 ? 2 : 3)
            } else if h.caps {
                level = 1
            } else {
                level = hasTop ? 2 : 1
            }
            if level == 1 { hasTop = true }
            parts[index].text = LatexTidy.command(h.title, level: level)
        }

        // 4. Join: headings always stand in their own paragraph.
        var joined = ""
        for (i, p) in parts.enumerated() {
            let sep = i == 0 ? "" : ((p.para || p.heading != nil || parts[i - 1].heading != nil) ? "\n\n" : "\n")
            joined += sep + p.text
        }
        return LatexTidy.Result(title: title, body: LatexTidy.layout(LatexTidy.structure(LatexTidy.promoteHeadings(joined))))
    }
    /// Built-in path: one call per page. The service transcribes with the managed Gemini
    /// vision model, validates the result (structure + every formula), and feeds any problem
    /// back for an automatic fix — up to 3 model passes. Falls back to the on-device model
    /// when it is installed and the service cannot be reached.
    private func convertCloud(_ image: UIImage, context: String?) async throws -> LatexTidy.Result {
        converting = true
        progress = "Reading the page…"
        defer { converting = false; progress = "" }
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "latex", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not prepare the page image."])
        }
        do {
            let r = try await CloudConverter.shared.convert(imageData: jpeg, mime: "image/jpeg", context: context)
            lastQuality = Quality(status: r.status, issues: r.issues, model: r.model, attempts: r.attempts)
            if r.status == "empty" { return LatexTidy.Result(title: "", body: "") }
            return LatexTidy.Result(title: r.title, body: LatexTidy.layout(r.latex_body))
        } catch {
            if GlmPaths.filesExist {
                backend = .device
                state = .notLoaded
                return try await convert(image, context: context)
            }
            throw error
        }
    }

    // The model was trained at about 1.2 megapixels per picture; much larger pictures make it loop.
    nonisolated private static func prepared(_ img: UIImage) -> CGImage? {
        let w = img.size.width * img.scale, h = img.size.height * img.scale
        guard w > 0, h > 0 else { return nil }
        let s = min(1, (1_200_000 / (w * h)).squareRoot())
        let size = CGSize(width: max(56, (w * s).rounded()), height: max(56, (h * s).rounded()))
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(origin: .zero, size: size))
            img.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

// MARK: - Preview (MathJax, needs internet; the .tex itself does not; theorem boxes show as plain text here)

struct MathView: UIViewRepresentable {
    let latex: String
    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ w: WKWebView, context: Context) {
        let safe = latex.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        w.loadHTMLString("""
        <meta name=viewport content="width=device-width,initial-scale=1">
        <script>window.MathJax={tex:{inlineMath:[['$','$'],['\\\\(','\\\\)']],displayMath:[['$$','$$'],['\\\\[','\\\\]']]}}</script>
        <script src="https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-svg.js"></script>
        <body style="font-size:20px;margin:12px;white-space:pre-wrap">\(safe)</body>
        """, baseURL: nil)
    }
}

// MARK: - Setup screen (replaces the old ModelSetupView in your main file)

struct ModelSetupView: View {
    @ObservedObject var engine: LatexEngine
    @State private var picking = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Free on-device LaTeX (GLM-OCR)").font(.title2.bold())
            switch engine.state {
            case .copying: ProgressView("Copying the model files…")
            case .loading: ProgressView("Loading the model…")
            case .ready: Label("Ready. Close this and tap LaTeX again.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let m): Text(m).foregroundStyle(.red)
            case .needsModel, .notLoaded: EmptyView()
            }
            Text("One-time setup: from Hugging Face (ctogaurav/GLM_OCR-GGUF, folder v4.1) download the two files GLM-OCR-v4.1-Q8_0.gguf and mmproj-GLM-OCR-v4.1-Q8_0.gguf (about 1.2 GB together, free). Put them in the Files app, then tap Import and select BOTH files at once. After that, conversion works offline.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Import the two model files…") { picking = true }.buttonStyle(.borderedProminent)
                if engine.state != .needsModel { Button("Remove model", role: .destructive) { engine.removeModel() } }
            }
            Spacer()
        }
        .padding(24)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await engine.importModels(from: urls) } }
        }
    }
}
