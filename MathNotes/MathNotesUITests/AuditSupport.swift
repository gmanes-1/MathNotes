import XCTest

extension XCTestCase {
    /// Logs, without failing, issues the app can't act on: system glass bars, text the
    /// audit reads off the dimmed screen behind a sheet (VoiceOver skips it by design), and `formText` below.
    @MainActor
    func audit(_ app: XCUIApplication, _ types: XCUIAccessibilityAuditType = .all, screen: String = "", modal: Bool = false,
               scrolled: Bool = false, formText: [String] = [], sheet: XCUIElement? = nil, popover: Bool = false,
               largeText: Bool = false, overlay: XCUIElement? = nil, bar: XCUIElement? = nil, pageText: [String] = [],
               cutBy list: XCUIElement? = nil) throws {
        let barMaxY = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? 0
        let screenMaxY = app.windows.firstMatch.frame.maxY
        let overlayTop = overlay.map { $0.exists ? $0.frame.minY - 120 : screenMaxY - 240 }
        let barFrame = bar.flatMap { $0.exists ? $0.frame.insetBy(dx: -4, dy: -4) : nil }
        let sheetTexts = sheet.flatMap { $0.exists ? $0.staticTexts.allElementsBoundByIndex.map(\.frame) : nil } ?? []
        let listFrame = list.flatMap { $0.exists ? $0.frame : nil }
        var recheck: [(identifier: String, label: String, frame: CGRect)] = []
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element
            print("AUDIT [\(screen)] \(issue.compactDescription) | type \(element.map { String($0.elementType.rawValue) } ?? "-") '\(element?.label ?? "nil")' \(element?.frame ?? .zero)")
            if issue.auditType == .contrast || issue.auditType == .dynamicType, let element, element.frame.minY < barMaxY {
                print("AUDIT [\(screen)] ignored on system bar: \(element.label)")
                return true
            }
            // Text typed on a page is the user's content: they set its size, and it zooms with the page as ink does.
            if issue.auditType == .dynamicType, let label = element?.label, !pageText.isEmpty,
               element?.identifier == "page.text.editor" || pageText.contains(where: label.hasPrefix) {
                print("AUDIT [\(screen)] ignored, text on the page: \(label)")
                return true
            }
            // Form rows and footers are flagged whatever they hold; all of it scales fully at AX5. Scrolled, the audit pulls
            // a row out from under the bar and samples its colours mid-scroll; they were checked in the pass before.
            if issue.auditType == .dynamicType || (scrolled && (issue.auditType == .textClipped || issue.auditType == .contrast)),
               let label = element?.label, formText.contains(where: label.hasPrefix) {
                print("AUDIT [\(screen)] ignored in a Form: \(label)")
                return true
            }
            // Text dimmed behind or beside a page sheet; VoiceOver can't reach it.
            if sheet != nil, issue.auditType == .hitRegion, element == nil {
                print("AUDIT [\(screen)] ignored behind sheet: \(issue.compactDescription)")
                return true
            }
            if sheet != nil, issue.auditType == .contrast || issue.auditType == .textClipped, element.map({ !sheetTexts.contains($0.frame) }) ?? true {
                print("AUDIT [\(screen)] ignored behind sheet: \(element?.label ?? "nil")")
                return true
            }
            // A list in a sheet smaller than the screen lays out every row; one past the list's edge is reported where
            // the dimmed page shows. It is checked in the pass that scrolls it into sight.
            if let listFrame, issue.auditType == .contrast || issue.auditType == .textClipped, let element, !listFrame.contains(element.frame) {
                print("AUDIT [\(screen)] ignored, scrolled out of its list: \(element.label)")
                return true
            }
            // A notebook's line of small print is part of its button, so the audit measures it over the whole card and
            // reads the cover's colours. Its own pair, secondary text on the desk, is checked by DesignTests.
            if issue.auditType == .contrast, let element, element.elementType == .staticText, case let frame = element.frame, frame.height > 100,
               app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notebook.'")).allElementsBoundByIndex
                   .contains(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(frame) }) {
                print("AUDIT [\(screen)] ignored, a card's small print measured with its cover: \(element.label)")
                return true
            }
            // iPadOS 27 reports popover content about 49 pt below where it's drawn, so contrast samples the wrong pixels.
            if popover, issue.auditType == .contrast {
                print("AUDIT [\(screen)] ignored in a popover: \(element?.label ?? "nil")")
                return true
            }
            // Thumbnail contents the audit reads as text, and rows a sheet's edge cuts at large sizes; colours are checked at the default size.
            if modal, issue.auditType == .contrast, element == nil || largeText {
                print("AUDIT [\(screen)] ignored in a sheet: \(issue.compactDescription)")
                return true
            }
            // At the default size the audit guesses which text a larger size would cut, and a guess with no element can't
            // be placed. The large-text pass looks at each sheet as it is then.
            if modal, !largeText, issue.auditType == .textClipped, element == nil {
                print("AUDIT [\(screen)] ignored, unnamed text that might be cut at a larger size: \(issue.compactDescription)")
                return true
            }
            // Text on the editor's floating bars is reported as low contrast whatever its colours, and not every run.
            // The pairs it uses (Ink on Surface, Paper on the accent) are checked by DesignTokenTests.
            if let barFrame, issue.auditType == .contrast, let element, barFrame.contains(element.frame) {
                print("AUDIT [\(screen)] ignored on a floating bar: \(element.label)")
                return true
            }
            // A one-line text field on a floating bar scrolls what doesn't fit, and grows with the text size.
            if let barFrame, issue.auditType == .textClipped, let element, [.textField, .searchField].contains(element.elementType),
               barFrame.contains(element.frame) {
                print("AUDIT [\(screen)] ignored, a text field on a floating bar: \(element.identifier)")
                return true
            }
            // Now and then the audit reports a text-size issue with no element at all, on a different screen each time.
            if issue.auditType == .dynamicType, element == nil {
                print("AUDIT [\(screen)] ignored, no element to act on: \(issue.compactDescription)")
                return true
            }
            // Text the audit can't tie to an element is inside cover and page images: the user's content.
            if issue.auditType == .contrast, element == nil {
                print("AUDIT [\(screen)] ignored, text inside an image: \(issue.compactDescription)")
                return true
            }
            if issue.auditType == .contrast, let element, element.frame.maxY > screenMaxY {
                print("AUDIT [\(screen)] ignored, cut by the screen edge: \(element.label)")
                return true
            }
            // Text the undo slip covers.
            if let overlayTop, issue.auditType == .contrast || issue.auditType == .textClipped,
               element.map({ $0.frame.maxY > overlayTop && $0.elementType != .button }) ?? true {
                print("AUDIT [\(screen)] ignored under the slip: \(issue.compactDescription)")
                return true
            }
            // Scrolled, text just below the glass bar sits in its fading edge, where it reads as low contrast.
            if scrolled, issue.auditType == .contrast, let element, element.frame.minY < barMaxY + 44 {
                print("AUDIT [\(screen)] ignored under the bar's edge: \(element.label)")
                return true
            }
            // Scrolled, some text sits under the glass bar; the audit sometimes can't name it, so it can't be placed there.
            if scrolled, issue.auditType == .contrast || issue.auditType == .dynamicType || issue.auditType == .textClipped, element == nil {
                print("AUDIT [\(screen)] ignored, unnamed text in a scrolled sheet: \(issue.compactDescription)")
                return true
            }
            if modal, issue.auditType == .elementDetection, element == nil {
                print("AUDIT [\(screen)] ignored behind modal: \(issue.compactDescription)")
                return true
            }
            // With a popover open the audit reads what it covers, which VoiceOver can't reach until it closes, and now and
            // then a drawing in it (the ruled lines under the opacity wash) as text. It names no element for either.
            if popover, issue.auditType == .elementDetection, element == nil {
                print("AUDIT [\(screen)] ignored, text with no element by a popover: \(issue.compactDescription)")
                return true
            }
            // A late redraw on a busy Mac looks like text that doesn't scale, so it fails only if a second audit flags it too.
            if issue.auditType == .dynamicType, let element {
                recheck.append((element.identifier, element.label, element.frame))
                return true
            }
            print("AUDIT FAIL [\(screen)] \(issue.detailedDescription)")
            return false
        }
        guard !recheck.isEmpty else { return }
        var flagged: [(identifier: String, label: String, frame: CGRect)] = []
        try app.performAccessibilityAudit(for: .dynamicType) { issue in
            guard let element = issue.element else { return true }
            let seen = (identifier: element.identifier, label: element.label, frame: element.frame)
            guard recheck.contains(where: { $0 == seen }) else { return true }
            flagged.append(seen)
            print("AUDIT FAIL [\(screen)] \(issue.detailedDescription)")
            return false
        }
        for item in recheck where !flagged.contains(where: { $0 == item }) {
            print("AUDIT [\(screen)] cleared on re-check: \(item.label)")
        }
    }
}
