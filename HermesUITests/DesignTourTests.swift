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
        let app = launch(["-resetState", "-simulateDictation"])
        XCTAssertTrue(app.navigationBars["Talaria"].waitForExistence(timeout: 10))
        settle(1.5)

        // Failed run: plain-language failure, raw code under Details.
        app.tabBars.buttons["Tasks"].tap()
        segment("Completed", app)
        if tapText("Evaluate Hermes 4 tool calling", app) {
            XCTAssertTrue(app.buttons["Retry Run"].waitForExistence(timeout: 5))
            settle()
            shot("80-run-failed", app)
            let details = app.buttons["Show details"].firstMatch
            if details.waitForExistence(timeout: 3) {
                details.tap()
                settle(0.5)
                shot("81-run-failed-details", app)
            }
            back(app)
        }

        // Create a bot, look at its capabilities, then edit it.
        app.tabBars.buttons["Bots"].tap()
        settle()
        XCTAssertTrue(app.buttons["Create Bot"].waitForExistence(timeout: 10))
        app.buttons["Create Bot"].tap()
        let name = app.textFields["bot-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        settle(0.5)
        shot("82-create-bot", app)
        let skills = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Skills'")).firstMatch
        if skills.waitForExistence(timeout: 3) {
            skills.tap()
            settle()
            shot("83-create-bot-skills", app)
            back(app)
        }
        name.tap(); name.typeText("Field Notes")
        let role = app.textFields["bot-description"]
        role.tap(); role.typeText("Keeps tidy notes from research sessions")
        app.buttons["Create"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Field Notes'")).firstMatch
        if row.waitForExistence(timeout: 10) {
            settle()
            shot("84-bots-after-create", app)
            row.tap()
            settle()
            shot("85-bot-detail", app)
            if app.buttons["Edit"].waitForExistence(timeout: 5) {
                app.buttons["Edit"].tap()
                settle()
                shot("86-edit-bot", app)
                app.buttons["Cancel"].tap()
                settle(0.5)
            }
            back(app)
        }

        // Composer: attachment preview, then dictation.
        app.tabBars.buttons["Chat"].tap()
        settle()
        app.navigationBars.buttons["New Chat"].firstMatch.tap()
        settle()
        if app.buttons["Add attachment"].waitForExistence(timeout: 5) {
            app.buttons["Add attachment"].tap()
            if app.buttons["Photo Library"].waitForExistence(timeout: 3) {
                app.buttons["Photo Library"].tap()
                let photos = app.images.matching(NSPredicate(format: "identifier == 'PXGGridLayout-Info'"))
                if photos.firstMatch.waitForExistence(timeout: 10) {
                    settle(1)
                    // The out-of-process picker reports its cells as not hittable; tap by position.
                    photos.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    if app.buttons["Add"].waitForExistence(timeout: 3) { app.buttons["Add"].tap() }
                    settle(1.5)
                    shot("87-composer-attachment", app)
                } else {
                    app.swipeDown(velocity: .fast)
                }
            }
        }
        if app.buttons["Voice input"].waitForExistence(timeout: 3) {
            app.buttons["Voice input"].tap()
            settle(0.9)
            shot("88-dictation-listening", app)
            settle(1.6)
            shot("89-dictation-partial", app)
            if app.buttons["Stop dictation"].exists { app.buttons["Stop dictation"].tap() }
            settle(0.5)
            shot("90-dictation-done", app)
        }
        app.terminate()

        let reconnecting = launch(["-simulate", "reconnecting"])
        settle(3)
        shot("91-home-reconnecting", reconnecting)
        reconnecting.terminate()
    }

    func testLargeDynamicType() throws {
        continueAfterFailure = false
        let app = launch(["-resetState", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        XCTAssertTrue(app.navigationBars["Talaria"].waitForExistence(timeout: 10))
        settle(1.5)
        shot("92-home-large-text", app)
        app.tabBars.buttons["Chat"].tap()
        settle()
        shot("93-chat-large-text", app)
        XCTAssertTrue(tapText("Researcher", app))
        let table=app.descendants(matching:.any)["markdown-table-accessible"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 10), "Original Researcher table must render at accessibility size")
        for _ in 0..<12 where !table.isHittable { app.swipeDown() }
        XCTAssertTrue(table.isHittable)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'OpenRouter'")).firstMatch.exists)
        shot("94-conversation-table-large-text", app)
        back(app)
        XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout: 5), "Table must leave navigation responsive")
        app.tabBars.buttons["Bots"].tap()
        settle()
        shot("95-bots-large-text", app)
    }

    func testLargestDynamicTypeTable() throws {
        continueAfterFailure = false
        let app = launch(["-resetState", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.navigationBars["Talaria"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(tapText("Researcher", app))
        let table=app.descendants(matching:.any)["markdown-table-accessible"].firstMatch
        for _ in 0..<16 where !(table.exists && table.isHittable) { app.swipeDown() }
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        XCTAssertTrue(table.isHittable)
        shot("94b-conversation-table-largest-text", app)
        back(app)
        XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout: 5))
    }

    func testNormalTableAndLiveRun() throws {
        continueAfterFailure = false
        let app=launch(["-resetState"])
        XCTAssertTrue(app.navigationBars["Talaria"].waitForExistence(timeout:10))
        app.tabBars.buttons["Chat"].tap();XCTAssertTrue(tapText("Researcher",app))
        XCTAssertTrue(app.buttons["Send Instruction"].firstMatch.waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["Stop"].firstMatch.isHittable)
        shot("97-active-run-controls",app)
        let table=app.descendants(matching:.any)["markdown-table-grid"].firstMatch
        for _ in 0..<12 where !(table.exists && table.isHittable) { app.swipeDown() }
        XCTAssertTrue(table.isHittable);shot("98-normal-markdown-table",app)
        back(app);XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout:5))
    }

    /// The installed app is named Talaria and wears the winged-sandal icon.
    func testHomeScreenIcon() throws {
        let app = launch(["-resetState"])
        XCTAssertTrue(app.navigationBars["Talaria"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["Talaria"]
        XCTAssertTrue(icon.waitForExistence(timeout: 10), "Home Screen shows the Talaria display name")
        for _ in 0..<5 where !icon.isHittable {
            springboard.swipeLeft()
            settle(0.6)
        }
        settle(1)
        shot("96-home-screen-icon", springboard)
    }

    // MARK: Helpers

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
