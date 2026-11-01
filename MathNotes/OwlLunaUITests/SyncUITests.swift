import XCTest

/// Sync, with a folder standing in for iCloud and two storage roots standing in for two iPads.
@MainActor
final class SyncUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["Settings"].firstMatch
        if !settings.waitForExistence(timeout: 10) || !settings.isHittable { app.buttons["ToggleSidebar"].firstMatch.tap() }
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
    }

    func testALibraryArrivesOnASecondDevice() throws {
        XCUIDevice.shared.orientation = .portrait
        let first = XCUIApplication()
        first.launchArguments = ["-storageRoot", "syncA", "-resetStorage", "-seedLibrary", "3", "-cloudFolder", "ui", "-resetCloud", "-syncsWithICloud", "YES"]
        first.launch()
        XCTAssertTrue(first.buttons["notebook.Physics II 3"].waitForExistence(timeout: 30))
        openSettings(first)
        let status = first.staticTexts["settings.sync.status"]
        for _ in 0..<6 where !status.exists { first.swipeUp() }
        XCTAssertTrue(status.waitForExistence(timeout: 30), "the first sync finishes")
        attach(first, "sync-settings")
        first.terminate()

        let second = XCUIApplication()
        second.launchArguments = ["-storageRoot", "syncB", "-resetStorage", "-cloudFolder", "ui", "-syncsWithICloud", "YES"]
        second.launch()
        XCTAssertTrue(second.buttons["notebook.Physics II 3"].waitForExistence(timeout: 60), "an empty library fills from the synced copy")
        XCTAssertTrue(second.buttons["notebook.Cell Biology 1"].exists)
        XCTAssertTrue(second.buttons["notebook.Studio Notes 2"].exists)
        sleep(1)
        attach(second, "sync-arrived")
        openSettings(second)
        let received = second.staticTexts["settings.sync.status"]
        for _ in 0..<6 where !received.exists { second.swipeUp() }
        XCTAssertTrue(received.waitForExistence(timeout: 30), "the sync finished without an error")
        // By now a later sync may have replaced "3 notebooks received", but none may have had anything else to report.
        for word in ["sent", "waiting", "conflicted", "deletion"] {
            XCTAssertFalse(received.label.contains(word), "an empty device only receives: \(received.label)")
        }
    }

    func testSyncSaysWhyItIsUnavailable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "syncNone", "-resetStorage", "-seedLibrary", "3"]
        app.launch()
        XCTAssertTrue(app.buttons["notebook.Physics II 3"].waitForExistence(timeout: 30))
        openSettings(app)
        let toggle = app.switches["settings.sync.toggle"]
        for _ in 0..<6 where !toggle.exists { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertTrue(toggle.isEnabled, "the switch can be set before iCloud is there")
        XCTAssertTrue(app.staticTexts["settings.sync.unavailable"].waitForExistence(timeout: 5), "and the row beneath says why nothing syncs yet")
        attach(app, "sync-unavailable")
    }

    func testAnotherAppleAccountIsAskedAboutFirst() throws {
        let first = XCUIApplication()
        first.launchArguments = ["-storageRoot", "syncAccount", "-resetStorage", "-seedLibrary", "3", "-cloudFolder", "account1", "-resetCloud",
                                 "-cloudAccount", "one", "-syncsWithICloud", "YES"]
        first.launch()
        XCTAssertTrue(first.buttons["notebook.Physics II 3"].waitForExistence(timeout: 30))
        openSettings(first)
        let status = first.staticTexts["settings.sync.status"]
        for _ in 0..<6 where !status.exists { first.swipeUp() }
        XCTAssertTrue(status.waitForExistence(timeout: 30), "the first account's sync finishes")
        first.terminate()

        let second = XCUIApplication()
        second.launchArguments = ["-storageRoot", "syncAccount", "-cloudFolder", "account2", "-resetCloud", "-cloudAccount", "two", "-syncsWithICloud", "YES"]
        second.launch()
        let allow = second.buttons["sync.question.allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 30), "sync stops and asks")
        XCTAssertTrue(second.staticTexts["A different Apple Account is signed in"].exists)
        attach(second, "sync-account-question")

        // A link opens a note in front of the library while the question is up, which takes the question down.
        XCUIDevice.shared.system.open(URL(string: "owlluna://quicknote")!)
        let back = second.buttons["editor.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 20))
        XCTAssertFalse(allow.exists)
        back.tap()
        XCTAssertTrue(allow.waitForExistence(timeout: 15), "still unanswered, it is asked again once the library is back")
        allow.tap()
        XCTAssertTrue(allow.waitForNonExistence(timeout: 10))
        openSettings(second)
        let sent = second.staticTexts["settings.sync.status"]
        for _ in 0..<6 where !sent.exists { second.swipeUp() }
        XCTAssertTrue(sent.waitForExistence(timeout: 30), "the sync with the second account finished without an error")
        attach(second, "sync-account-allowed")
        second.terminate()

        // What was sent is what a device new to that account receives.
        let third = XCUIApplication()
        third.launchArguments = ["-storageRoot", "syncAccountNew", "-resetStorage", "-cloudFolder", "account2", "-cloudAccount", "two", "-syncsWithICloud", "YES"]
        third.launch()
        XCTAssertTrue(third.buttons["notebook.Physics II 3"].waitForExistence(timeout: 60), "the notebooks were copied to the second account's iCloud")
        XCTAssertTrue(third.buttons["notebook.Cell Biology 1"].exists)
        XCTAssertTrue(third.buttons["notebook.Studio Notes 2"].exists)
    }
}
