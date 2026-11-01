import XCTest

/// The library as a list, and what the selection bar does to several notebooks at once.
@MainActor
final class LibraryListUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The layout is given at launch, so nothing this test does is left saved for the next one.
    func testTheListSelectsEverythingShownAndTagsIt() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "librarylist", "-resetStorage", "-seedLibrary", "12", "-libraryLayout", "list", "-librarySort", "title"]
        app.launch()
        let notebook = app.buttons["notebook.Cell Biology 1"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["library.list.sort.title"].exists, "the list names its columns")
        XCTAssertTrue(app.buttons["library.layout.list"].isSelected, "the bar says which layout is on show")
        let next = app.buttons["notebook.Cell Biology 11"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertLessThan(notebook.frame.minY, next.frame.minY, "A to Z, one row under another")
        XCTAssertEqual(notebook.frame.minX, next.frame.minX, accuracy: 1)
        attach(app, "library-list")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["library.list.sort.modified"].waitForExistence(timeout: 5))
        let wide = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        wide.name = "library-list-landscape"
        wide.lifetime = .keepAlways
        add(wide)
        XCUIDevice.shared.orientation = .portrait

        app.buttons["Select"].tap()
        let selectAll = app.buttons["library.selectAll"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        selectAll.tap()
        XCTAssertTrue(app.staticTexts["12 selected"].waitForExistence(timeout: 5), "Select All takes every notebook shown")
        XCTAssertTrue(notebook.isSelected)
        XCTAssertEqual(selectAll.label, "Deselect All")
        attach(app, "library-list-selected")
        for action in ["favourite", "tags", "move", "lock", "export", "delete"] {
            XCTAssertTrue(app.buttons["library.selection.\(action)"].isEnabled, action)
        }

        app.buttons["library.selection.tags"].tap()
        let field = app.textFields["tags.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("exam\n")
        XCTAssertTrue(app.buttons["tags.chip.exam"].waitForExistence(timeout: 5))
        attach(app, "library-list-tags")
        app.buttons["tags.done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Select"].waitForExistence(timeout: 5), "tagging ends the selection")
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS 'tagged exam'"), evaluatedWith: notebook)], timeout: 10)
        let tag = app.descendants(matching: .any)["tag.exam"]
        if !tag.exists || !tag.isHittable { app.buttons["ToggleSidebar"].firstMatch.tap() }
        XCTAssertTrue(tag.waitForExistence(timeout: 10))
        XCTAssertTrue(tag.label.contains("12 notebooks"), tag.label)
    }

    /// At the accessibility text sizes the columns fold into a line under each title, and the selection bar still works.
    func testTheListAtTheLargestTextInTheDark() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "librarylist", "-resetStorage", "-seedLibrary", "12", "-libraryLayout", "list", "-librarySort", "title",
                               "-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        let notebook = app.buttons["notebook.Cell Biology 1"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["library.list.sort.title"].exists, "no room for columns, so no names over them")
        attach(app, "library-list-large-dark")

        app.buttons["Select"].tap()
        app.buttons["library.selectAll"].tap()
        XCTAssertTrue(notebook.isSelected)
        attach(app, "library-list-large-dark-selected")
        app.buttons["library.selectAll"].tap()
        XCTAssertFalse(notebook.isSelected, "Deselect All")
    }
}
