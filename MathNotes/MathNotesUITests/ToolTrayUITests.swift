import XCTest

/// The editor uses PencilKit's native tool picker instead of the former custom drawing tray.
@MainActor
final class ToolTrayUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNativeToolsCanBeShownAndHiddenWhileTheCanvasRemainsEditable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "native-tools", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "anyInput"]
        app.launch()

        let notebook = app.buttons["notebook.Studio Notes 2"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()

        let canvas = app.element("page.canvas.1")
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        let hide = app.buttons["Hide Tools"]
        XCTAssertTrue(hide.waitForExistence(timeout: 10))
        hide.tap()
        let show = app.buttons["Show Tools"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.tap()
        XCTAssertTrue(hide.waitForExistence(timeout: 5))

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.35)),
                   withVelocity: 600, thenHoldForDuration: 0.05)
        let strokes = Int(((canvas.value as? String) ?? "").split(separator: " ").first ?? "") ?? 0
        XCTAssertGreaterThan(strokes, 0, "native PencilKit selection still draws into the page")
    }
}
