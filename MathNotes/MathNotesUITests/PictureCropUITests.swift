import XCTest

/// Cropping a picture placed on a page: Crop in its bar, an edge dragged in, then Done, Cancel and Undo.
@MainActor
final class PictureCropUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAPictureIsCroppedFromAnEdgeAndCanBePutBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "crop", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "anyInput"]
        app.launch()
        let notebook = app.buttons["notebook.Physics II 3"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        XCTAssertTrue(app.descendants(matching: .any)["page.canvas.1"].waitForExistence(timeout: 20))
        app.buttons["Add"].firstMatch.tap()
        app.buttons["Picture on This Page…"].firstMatch.tap()
        let photo = app.scrollViews.images.matching(NSPredicate(format: "label CONTAINS[c] %@", "photo")).firstMatch
        try XCTSkipUnless(photo.waitForExistence(timeout: 15), "this simulator's photo library is empty")
        photo.tap()
        let picture = app.images["Picture"]
        if !picture.waitForExistence(timeout: 20), photo.exists { photo.tap() }
        XCTAssertTrue(picture.waitForExistence(timeout: 30), "the photo is placed on the current page")
        let crop = app.buttons["editor.arrange.crop"]
        XCTAssertTrue(crop.waitForExistence(timeout: 5))
        sleep(1)
        let before = picture.frame

        crop.tap()
        let done = app.buttons["editor.crop.done"], reset = app.buttons["editor.crop.reset"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(reset.isEnabled, "nothing to reset yet")
        let right = app.descendants(matching: .any)["page.crop.right"]
        XCTAssertTrue(right.waitForExistence(timeout: 5))
        XCTAssertEqual(right.value as? String, "0% cut off")
        let grip = right.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.1, thenDragTo: grip.withOffset(CGVector(dx: -before.width * 0.4, dy: 0)), withVelocity: 400, thenHoldForDuration: 0.1)
        XCTAssertNotEqual(right.value as? String, "0% cut off", "the right edge came in")
        XCTAssertTrue(reset.isEnabled)
        attach(app, "cropping")
        done.tap()

        XCTAssertTrue(app.buttons["editor.arrange.done"].waitForExistence(timeout: 5), "still picked up, ready to move")
        let cropped = picture.frame
        XCTAssertLessThan(cropped.width, before.width * 0.75)
        XCTAssertEqual(cropped.minX, before.minX, accuracy: 2, "what is kept stays where it was")
        XCTAssertEqual(cropped.height, before.height, accuracy: 2)
        attach(app, "cropped")

        crop.tap()
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        app.buttons["editor.crop.cancel"].tap()
        XCTAssertTrue(app.buttons["editor.arrange.done"].waitForExistence(timeout: 5))
        XCTAssertEqual(picture.frame.width, cropped.width, accuracy: 1, "Cancel keeps the crop there was")

        app.buttons["editor.undo"].tap()
        XCTAssertEqual(picture.frame.width, before.width, accuracy: 2, "Undo gives the whole picture back")
    }
}
