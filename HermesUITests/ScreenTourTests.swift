import XCTest

/// Walks every major screen against the mock backend and saves screenshots.
/// Doubles as a smoke test that navigation works end to end.
///
/// Screenshots go to `$SCREENSHOT_DIR` (pass `TEST_RUNNER_SCREENSHOT_DIR=…`
/// to xcodebuild) and are also attached to the test result.
final class ScreenTourTests: XCTestCase {
    private var app: XCUIApplication!
    private var directory: URL?

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetState"]
        // TEST_RUNNER_TOUR_APPEARANCE=dark|light captures the tour in that appearance.
        if let appearance = ProcessInfo.processInfo.environment["TOUR_APPEARANCE"] {
            app.launchArguments += ["-pref.appearance", appearance]
        }
        if let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            directory = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(at: directory!, withIntermediateDirectories: true)
        }
        app.launch()
    }

    func testTour() throws {
        XCTAssertTrue(app.navigationBars["Now"].waitForExistence(timeout: 10))
        settle(2); shot("01-now"); app.swipeUp(); shot("02-now-working"); app.swipeDown()
        tab("Threads"); settle(); shot("10-threads")
        if tapText("Researcher") { settle(); shot("11-thread-working"); if app.buttons["steps-button"].firstMatch.exists { app.buttons["steps-button"].firstMatch.tap(); settle(); shot("12-steps"); app.buttons["Done"].firstMatch.tap() }; back() }
        if tapText("This week in agent research") { settle(); shot("13-markdown-artifacts"); back() }
        app.buttons["ask-bar"].tap(); settle(); shot("16-ask"); app.buttons["Close"].firstMatch.tap()
        tab("Agents"); settle(); shot("30-agents")
        if tapText("Caddy") { settle(); shot("31-agent"); app.swipeUp(); shot("32-agent-runtime"); back() }
        tab("Now"); app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Studio connection' ")).firstMatch.tap(); settle(); shot("40-studio")
        if tapText("Settings") { settle(); shot("41-settings"); back() }
        if tapText("Skills") { settle(); shot("42-skills"); back() }
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        Thread.sleep(forTimeInterval: seconds)
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

    private func tab(_ label: String) {
        let button = app.tabBars.buttons[label]
        if !button.exists {
            let collapsed = app.tabBars.buttons.matching(NSPredicate(format: "value == 'Collapsed'")).firstMatch
            if collapsed.exists { collapsed.tap() }
        }
        for _ in 0..<3 where !button.exists { app.swipeDown() }
        XCTAssertTrue(button.waitForExistence(timeout:5)); button.tap()
    }

    private func segment(_ label: String) {
        let button = app.segmentedControls.buttons[label].firstMatch
        if button.waitForExistence(timeout: 3) { button.tap() }
        settle()
    }

    @discardableResult
    private func tapText(_ label: String) -> Bool {
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@",label)).firstMatch
        let element = button.exists ? button : app.staticTexts[label].firstMatch
        var attempts = 0
        while !(element.exists && element.isHittable) && attempts < 4 {
            if attempts == 0 && element.waitForExistence(timeout: 2) && element.isHittable { break }
            app.swipeUp()
            attempts += 1
        }
        guard element.exists else { return false }
        element.tap()
        return true
    }

    private func back() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.waitForExistence(timeout: 2) { button.tap() }
        settle(0.5)
    }

    private func scrollToTop() {
        app.statusBars.firstMatch.tap()
        settle(0.4)
    }
}
