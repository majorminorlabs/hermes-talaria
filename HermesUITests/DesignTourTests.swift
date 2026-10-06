import XCTest

/// Captures the product states the main tour can't reach: a failed run with
/// its raw reason under Details, bot creation and editing, a composer with an
/// attachment, dictation, reconnecting, and large Dynamic Type. Runs against
/// the mock backend; `TEST_RUNNER_TOUR_APPEARANCE=dark` captures dark mode.
final class DesignTourTests: XCTestCase {
    private var directory: URL?

    override func setUpWithError() throws {
        continueAfterFailure = true
        if let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            directory = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(at: directory!, withIntermediateDirectories: true)
        }
    }

    func testDesignStates() throws {
        let app = XCUIApplication(); app.launchArguments = ["-uiTesting", "-resetState", "-pref.appearance", ProcessInfo.processInfo.environment["TOUR_APPEARANCE"] ?? "light"]; app.launch()
        XCTAssertTrue(app.buttons["ask-toolbar"].waitForExistence(timeout:10)); shot("design-now", app)
        app.tabBars.buttons["Threads"].tap(); shot("design-threads", app)
        app.tabBars.buttons["Agents"].tap(); shot("design-agents", app)
        app.buttons["Create Agent"].tap(); XCTAssertTrue(app.textFields["bot-name"].waitForExistence(timeout:5)); shot("design-agent-editor", app); app.buttons["Cancel"].firstMatch.tap()
        app.tabBars.buttons["Now"].tap(); app.buttons["ask-toolbar"].tap(); app.buttons["capture-button"].tap(); XCTAssertTrue(app.navigationBars["Capture"].waitForExistence(timeout:5)); shot("design-capture", app); app.buttons["Close"].firstMatch.tap(); XCTAssertTrue(app.navigationBars["Capture"].waitForNonExistence(timeout:5))
        app.tabBars.buttons["Now"].tap(); app.buttons["ask-toolbar"].tap(); XCTAssertTrue(app.navigationBars["Ask"].waitForExistence(timeout:5)); shot("design-ask", app)
    }

    func testLargeDynamicType() throws {
        let app = launch(["-resetState", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["ask-toolbar"].waitForExistence(timeout:10)); shot("large-now",app)
        app.tabBars.buttons["Threads"].tap(); shot("large-threads",app)
        app.tabBars.buttons["Agents"].tap(); shot("large-agents",app)
        app.tabBars.buttons["Now"].tap()
        XCTAssertTrue(app.buttons["ask-toolbar"].exists)
        app.tabBars.buttons["Now"].tap(); app.buttons["ask-toolbar"].tap(); XCTAssertTrue(app.buttons["ask-send"].waitForExistence(timeout:5)); shot("large-ask",app)
    }
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        if let appearance = ProcessInfo.processInfo.environment["TOUR_APPEARANCE"] {
            app.launchArguments += ["-pref.appearance", appearance]
        }
        app.launch()
        return app
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory {
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    private func segment(_ label: String, _ app: XCUIApplication) {
        let button = app.segmentedControls.buttons[label].firstMatch
        if button.waitForExistence(timeout: 3) { button.tap() }
        settle()
    }

    @discardableResult
    private func tapText(_ label: String, _ app: XCUIApplication) -> Bool {
        let element = app.staticTexts[label].firstMatch
        var attempts = 0
        while !(element.exists && element.isHittable) && attempts < 5 {
            if attempts == 0 && element.waitForExistence(timeout: 2) && element.isHittable { break }
            app.swipeUp()
            attempts += 1
        }
        guard element.exists else { return false }
        element.tap()
        return true
    }

    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.waitForExistence(timeout: 2) { button.tap() }
        settle(0.5)
    }
}
