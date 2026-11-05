import XCTest

/// A text box styled from its bar and its Text Style card, made a checklist, and ticked with a tap.
@MainActor
final class TextStyleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testATextBoxBecomesAChecklistThatATapTicks() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "textstyle", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "pencilOnly"]
        app.launch()
        let notebook = app.buttons["notebook.Physics II 3"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        XCTAssertTrue(app.descendants(matching: .any)["page.canvas.1"].waitForExistence(timeout: 20))

        app.buttons["Add"].firstMatch.tap()
        app.buttons["Text Box"].firstMatch.tap()
        let editor = app.textViews["page.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.typeText("Oats\nFlour\nEggs")
        let italic = app.buttons["editor.arrange.italic"]
        XCTAssertTrue(italic.waitForExistence(timeout: 5), "bold, italic and underline stand in the bar where there is room")
        XCTAssertFalse(italic.isSelected)
        italic.tap()
        XCTAssertTrue(editor.exists, "styling from the bar keeps the box open for typing")
        XCTAssertTrue(italic.isSelected)

        app.buttons["editor.arrange.style"].tap()
        let lists = app.element("editor.text.list")
        XCTAssertTrue(lists.waitForExistence(timeout: 5), "the card shows every option at once")
        XCTAssertTrue(app.element("editor.text.face").exists && app.element("editor.text.size").exists && app.element("editor.text.alignment").exists)
        lists.children(matching: .button)["Checklist"].tap()
        app.element("editor.text.face").children(matching: .button)["Serif"].tap()
        app.buttons["editor.text.highlight.yellow"].tap()
        XCTAssertTrue(app.buttons["editor.text.highlight.yellow"].isSelected)
        XCTAssertTrue(app.buttons["editor.text.italic"].isSelected, "the card and the bar agree")
        attach(app, "text-style-card")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.95)).tap()
        XCTAssertTrue(lists.waitForNonExistence(timeout: 5))
        app.buttons["editor.arrange.done"].tap()

        let box = app.staticTexts["Oats\nFlour\nEggs"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        attach(app, "checklist")
        let lineHeight = box.frame.height / 3
        box.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: lineHeight * 0.6, dy: lineHeight * 1.5)).tap()
        let ticked = app.staticTexts["Oats\nFlour, ticked\nEggs"]
        XCTAssertTrue(ticked.waitForExistence(timeout: 5), "a tap on a line's box ticks it")
        attach(app, "checklist-ticked")
        app.buttons["editor.undo"].tap()
        XCTAssertTrue(box.waitForExistence(timeout: 5), "a tick is undone like any other change")
    }
}
