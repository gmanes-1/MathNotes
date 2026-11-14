import XCTest

/// The library's Apple Notes-style list and its multi-selection actions.
@MainActor
final class LibraryListUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNotesListSelectsEverythingShownAndTagsIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "librarylist", "-resetStorage", "-seedLibrary", "12", "-librarySort", "title"]
        app.launch()

        let first = app.buttons["notebook.Cell Biology 1"]
        let next = app.buttons["notebook.Cell Biology 11"]
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertLessThan(first.frame.minY, next.frame.minY, "notes are listed in title order")
        XCTAssertEqual(first.frame.minX, next.frame.minX, accuracy: 1)

        app.buttons["Select"].tap()
        let selectAll = app.buttons["library.selectAll"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        selectAll.tap()
        XCTAssertTrue(app.staticTexts["12 selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(first.isSelected)
        XCTAssertEqual(selectAll.label, "Deselect All")

        app.buttons["library.selection.tags"].tap()
        let field = app.textFields["tags.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("exam\n")
        XCTAssertTrue(app.buttons["tags.chip.exam"].waitForExistence(timeout: 5))
        app.buttons["tags.done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Select"].waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS 'tagged exam'"), evaluatedWith: first)], timeout: 10)
    }

    func testNotesListRemainsUsableWithLargeTextAndDarkAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "librarylist", "-resetStorage", "-seedLibrary", "12",
                               "-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        let first = app.buttons["notebook.Cell Biology 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        app.buttons["Select"].tap()
        app.buttons["library.selectAll"].tap()
        XCTAssertTrue(first.isSelected)
        app.buttons["library.selectAll"].tap()
        XCTAssertFalse(first.isSelected)
    }
}
