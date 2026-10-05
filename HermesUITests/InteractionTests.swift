import XCTest

/// Core interactions against the simulator: approve, send, deny, steer, stop.
final class InteractionTests: XCTestCase {
    private var app: XCUIApplication!
    private var directory: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetState", "-runSpeed", "4"]
        if let appearance = ProcessInfo.processInfo.environment["TOUR_APPEARANCE"] {
            app.launchArguments += ["-pref.appearance", appearance]
        }
        if let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            directory = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(at: directory!, withIntermediateDirectories: true)
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["Talaria"].waitForExistence(timeout: 10))
    }

    func testApproveFromConversationCompletesRun() throws {
        app.tabBars.buttons["Chat"].tap()
        app.staticTexts["Caddy"].firstMatch.tap()
        let approve = app.buttons["Approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        approve.tap()
        XCTAssertTrue(app.staticTexts["Ran rm generated-cache.json"].waitForExistence(timeout: 10))
        shot("70-approved-continuing")
        XCTAssertTrue(app.staticTexts["Nothing is committed yet. Want me to open a PR?"].waitForExistence(timeout: 20)
                      || app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'open a PR'")).firstMatch.waitForExistence(timeout: 5))
        shot("71-approved-completed")
    }

    func testNewChatApprovalThenDeny() throws {
        app.navigationBars["Talaria"].buttons["New Chat"].tap()
        let field = composer()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Clean up the build cache")
        app.buttons["Send"].tap()
        let deny = app.buttons["Deny"].firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 15))
        shot("72-new-chat-approval")
        deny.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'left'")).firstMatch.waitForExistence(timeout: 15))
        shot("73-new-chat-denied")
    }

    func testSteerAndStopRunningResearch() throws {
        app.tabBars.buttons["Chat"].tap()
        app.staticTexts["Researcher"].firstMatch.tap()
        let steer = app.buttons["Send Instruction"].firstMatch
        XCTAssertTrue(steer.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Stop"].firstMatch.isHittable, "Live run controls must survive grouped tool history")
        steer.tap()
        let sheetField = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(sheetField.waitForExistence(timeout: 3))
        sheetField.typeText("Focus on the 18:00-22:00 window")
        app.navigationBars["Send Instruction"].buttons["Send"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Focus on the 18:00'")).firstMatch.waitForExistence(timeout: 5))
        shot("74-steered")
        app.buttons["Stop"].firstMatch.tap()
        let confirm = app.buttons["Stop Run"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Stopped by you"].waitForExistence(timeout: 8))
        shot("75-stopped")
    }

    func testRetryCompletedRunWhenHostAllowsIt() throws {
        app.tabBars.buttons["Tasks"].tap()
        app.segmentedControls.buttons["Completed"].tap()
        let completed=app.staticTexts["Clean up stale build scripts"].firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout:10));completed.tap()
        let retry=app.buttons["Retry"].firstMatch
        for _ in 0..<8 where !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.waitForExistence(timeout:5));XCTAssertTrue(retry.isEnabled)
        shot("76-completed-run-retry-available")
        retry.tap();XCTAssertTrue(app.staticTexts["Retrying"].waitForExistence(timeout:5))
    }

    private func composer() -> XCUIElement {
        let textView = app.textViews["Message Hermes"]
        return textView.exists ? textView : app.textFields["Message Hermes"]
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory {
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }
}
