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
        XCTAssertTrue(app.navigationBars["Talaria"].waitForExistence(timeout: 10))
        settle(2)
        shot("01-home")
        app.swipeUp()
        settle()
        shot("02-home-scrolled")
        app.swipeDown()
        app.swipeDown()

        // Run detail from Home.
        if tapText("Analyzing provider benchmark") {
            settle()
            shot("03-run-detail")
            app.swipeUp()
            settle()
            shot("04-run-detail-timeline")
            back()
        }

        // Non-actionable approval detail.
        if tapText("Dex needs approval") {
            settle()
            shot("05-approval-unavailable")
            back()
        }

        // Chat.
        tab("Chat")
        settle()
        shot("10-chat-list")
        if tapText("Researcher") {
            settle(1.5)
            shot("11-conversation-live-run")
            back()
        }
        if tapText("Caddy") {
            settle(1.5)
            shot("12-conversation-approval")
            back()
        }
        if tapText("This week in agent research") {
            settle(1.5)
            shot("13-conversation-markdown-image")
            app.swipeDown()
            settle()
            shot("14-conversation-markdown-top")
            back()
        }
        if tapText("Explain KV cache quantization") {
            settle(1.5)
            shot("15-conversation-code-table")
            back()
        }
        app.navigationBars.buttons["New Chat"].firstMatch.tap()
        settle()
        shot("16-new-chat")
        back()

        // Tasks.
        tab("Tasks")
        settle()
        shot("20-tasks-running")
        segment("Scheduled")
        shot("21-tasks-scheduled")
        if tapText("Nightly research sweep") {
            settle()
            shot("22-routine-detail")
            back()
        }
        segment("Kanban")
        shot("23-tasks-kanban")
        if tapText("Blocked") {
            settle()
            shot("24-kanban-blocked")
            if tapText("Deploy docs site to Fly.io") {
                settle()
                shot("25-task-detail-blocked")
                back()
            }
        }
        if app.buttons["Show board"].exists {
            app.buttons["Show board"].tap()
            settle()
            shot("26-kanban-board")
            app.buttons["Show list"].tap()
        }
        segment("Completed")
        shot("27-tasks-completed")

        // Bots.
        tab("Bots")
        settle()
        shot("30-bots")
        if tapText("Caddy") {
            settle()
            shot("31-profile-caddy")
            app.swipeUp()
            settle()
            shot("32-profile-caddy-scrolled")
            back()
        }

        // More.
        tab("More")
        settle()
        shot("40-more")
        for (label, name) in [("Usage", "41-usage"), ("Memory", "42-memory"), ("Skills", "43-skills"), ("Tools", "44-tools"),
                              ("MCP Servers", "45-mcp"), ("Integrations", "46-integrations"), ("Logs", "47-logs"),
                              ("Mac Studio", "48-host-detail"), ("Settings", "49-settings")] {
            if tapText(label) {
                settle(1.2)
                shot(name)
                if label == "Settings" {
                    app.swipeUp()
                    settle()
                    shot("50-settings-scrolled")
                }
                back()
            }
        }
    }

    // MARK: Helpers

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
        app.tabBars.buttons[label].tap()
    }

    private func segment(_ label: String) {
        let button = app.segmentedControls.buttons[label].firstMatch
        if button.waitForExistence(timeout: 3) { button.tap() }
        settle()
    }

    @discardableResult
    private func tapText(_ label: String) -> Bool {
        let element = app.staticTexts[label].firstMatch
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
