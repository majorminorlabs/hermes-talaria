import XCTest

/// Opt-in, launched only after the hosted RealStackTests provisions this
/// simulator's Keychain. No bearer token is typed or placed in launch arguments.
final class RealStackUITests: XCTestCase {
    func testProductionAppAgainstLocalStudio() throws {
        guard ProcessInfo.processInfo.environment["HERMES_STACK_FIXTURE"] != nil else {
            throw XCTSkip("Start the isolated stack and run hosted RealStackTests first")
        }
        continueAfterFailure = false
        let app=XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["ask-toolbar"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["ask-toolbar"].waitForExistence(timeout:20))
        app.tabBars.buttons["Now"].tap(); app.buttons["ask-toolbar"].tap()
        let composer = app.textFields["ask-text"]
        XCTAssertTrue(composer.waitForExistence(timeout:5)); composer.tap(); composer.typeText("Safe local UI hello")
        app.buttons["ask-send"].tap()
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout:5)); app.buttons["Open"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'Local Studio stream complete'")).firstMatch.waitForExistence(timeout:20))
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.tabBars.buttons["Agents"].tap()
        let worker = app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Research Worker' ")).firstMatch
        XCTAssertTrue(worker.waitForExistence(timeout:10)); worker.tap()
        app.buttons["agent-ask"].tap()
        let agentComposer = app.textFields["ask-text"]
        XCTAssertTrue(agentComposer.waitForExistence(timeout:5)); agentComposer.tap(); agentComposer.typeText("Safe independent Agent UI hello")
        app.buttons["ask-send"].tap()
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout:5)); app.buttons["Open"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'Local Studio stream complete'")).firstMatch.waitForExistence(timeout:20))
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.tabBars.buttons["Now"].tap(); app.buttons["ask-toolbar"].tap(); app.buttons["capture-button"].tap()
        let capture = app.textFields["capture-text"]
        XCTAssertTrue(capture.waitForExistence(timeout:5)); capture.tap(); capture.typeText("  Production UI *capture*\nKeep exact text  ")
        app.buttons["capture-save"].tap()
        XCTAssertTrue(app.staticTexts["Saved to Hermes"].waitForExistence(timeout:10))
        app.tabBars.buttons["Now"].tap()
        app.buttons["talaria-settings"].tap()
        XCTAssertTrue(app.navigationBars["Studio"].waitForExistence(timeout:5))

    }
}

/// Opt-in read-only smoke on the already-paired physical phone. Never provisions credentials.
final class StudioBotUITests: XCTestCase {
    private func studioApp() throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["HERMES_STUDIO_BOTS_UI"] == "1" else {
            throw XCTSkip("Requires an already-paired physical iPhone and explicit Studio validation")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Agents"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Agents"].tap()
        return app
    }

    private func row(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    func testStudioBotListSkillsAndChat() throws {
        let app = try studioApp()
        for name in ["Research Orchestrator", "Hermes", "Research Worker"] {
            XCTAssertTrue(row(name, in: app).waitForExistence(timeout: 30), name)
        }
        XCTAssertFalse(app.staticTexts["Default Profile"].exists)
        let roster = XCTAttachment(screenshot: app.screenshot()); roster.name = "Studio Bots"; roster.lifetime = .keepAlways; add(roster)
        row("Research Orchestrator", in: app).tap()
        var found = app.staticTexts["research-terminal"].exists
        for _ in 0..<30 where !found {
            app.swipeUp()
            showAllSkills(in: app)
            found = app.staticTexts["research-terminal"].waitForExistence(timeout: 2)
        }
        XCTAssertTrue(found, "Research Orchestrator attached skill")
        let skills = XCTAttachment(screenshot: app.screenshot()); skills.name = "Research Orchestrator skills"; skills.lifetime = .keepAlways; add(skills)
        let chatButton = app.buttons["agent-ask"].firstMatch
        for _ in 0..<30 where !chatButton.isHittable { app.swipeDown() }
        XCTAssertTrue(chatButton.exists)
        if chatButton.isEnabled {
            chatButton.tap()
            XCTAssertTrue(app.staticTexts["Studio Bot Chat · Read only"].waitForExistence(timeout: 20))
            let chat = XCTAttachment(screenshot: app.screenshot()); chat.name = "Canonical Studio Bot Chat"; chat.lifetime = .keepAlways; add(chat)
        }
    }

    func testNewStudioBotAppearsWithoutRebuild() throws {
        let app = try studioApp()
        XCTAssertTrue(row("Mobile Refresh Probe", in: app).waitForExistence(timeout: 60))
        let evidence = XCTAttachment(screenshot: app.screenshot()); evidence.name = "New Studio bot after refresh"; evidence.lifetime = .keepAlways; add(evidence)
    }

    func testRemovedStudioBotDisappears() throws {
        let app = try studioApp()
        XCTAssertTrue(row("Research Orchestrator", in: app).waitForExistence(timeout: 30))
        XCTAssertFalse(row("Mobile Refresh Probe", in: app).exists)
    }
}

/// Explicit opt-in: uses the phone's existing pairing and safe read-only prompts.
final class WritableStudioBotUITests: XCTestCase {
    private func app() throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["HERMES_WRITABLE_BOTS_UI"] == "1" else {
            throw XCTSkip("Requires explicit writable validation on the paired physical iPhone")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Agents"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Agents"].tap()
        return app
    }
    private func bot(_ name: String, _ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }
    private func evidence(_ name: String, _ app: XCUIApplication) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func open(_ name: String, _ app: XCUIApplication) {
        XCTAssertTrue(bot(name, app).waitForExistence(timeout: 30)); bot(name, app).tap()
        let chat = app.buttons["agent-ask"].firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 15)); XCTAssertTrue(chat.isEnabled); chat.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 30) || app.textViews.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Studio Bot Chat · Read only"].exists)
    }
    private func send(_ prompt: String, completion: String, _ app: XCUIApplication) {
        let input = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        input.tap(); input.typeText(prompt)
        XCTAssertTrue(app.buttons["Send"].firstMatch.isEnabled); app.buttons["Send"].firstMatch.tap()
        let response = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", completion)).firstMatch
        XCTAssertTrue(response.waitForExistence(timeout: 180), "Expected assistant completion")
        evidence(completion, app)
    }
    func testResearchOrchestratorReadOnlyTerminalAndRecovery() throws {
        let app = try app()
        XCTAssertTrue(bot("Research Orchestrator", app).waitForExistence(timeout: 30)); bot("Research Orchestrator", app).tap()
        var found = app.staticTexts["research-terminal"].isHittable
        for _ in 0..<65 where !found {
            // Short overlapping drags keep every skill row observable between snapshots.
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05,
                thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            showAllSkills(in: app)
            found = app.staticTexts["research-terminal"].isHittable
        }
        evidence("Research Orchestrator skill scroll result", app)
        XCTAssertTrue(found); evidence("Attached research-terminal on iPhone", app)
        let chat = app.buttons["agent-ask"].firstMatch
        for _ in 0..<35 where !chat.isHittable { app.swipeDown() }
        XCTAssertTrue(chat.isEnabled); chat.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 30) || app.textViews.firstMatch.exists)
        send("For this phone validation, read the attached research-terminal skill and run only its helper's read-only search for Hermes. Do not create research jobs, change files, publish, send messages, or inspect credentials. In your final response start with MOBILE_RESEARCH_CHECK_DONE and briefly give your configured profile, the helper result or status, and one source title if available.", completion: "MOBILE_RESEARCH_CHECK_DONE", app)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'MOBILE_RESEARCH_CHECK_DONE'")).firstMatch.waitForExistence(timeout: 30))
        app.terminate(); app.launch()
        app.tabBars.buttons["Agents"].tap(); open("Research Orchestrator", app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'MOBILE_RESEARCH_CHECK_DONE'")).firstMatch.waitForExistence(timeout: 30))
        evidence("Research Orchestrator history after relaunch", app)
        app.tabBars.buttons["Threads"].tap()
        let listed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Research Orchestrator'")).firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 30)); listed.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'MOBILE_RESEARCH_CHECK_DONE'")).firstMatch.waitForExistence(timeout: 30))
        evidence("Same Bot Chat opened from Chat tab", app)
    }
    func testHermesWritableChat() throws {
        let app = try app(); open("Hermes", app)
        send("Reply briefly, starting with MOBILE_HERMES_CHECK_DONE, and state your configured bot identity. Do not run tools or change anything.", completion: "MOBILE_HERMES_CHECK_DONE", app)
    }
    func testResearchTerminalAuthenticatedStatus() throws {
        guard let reference = ProcessInfo.processInfo.environment["HERMES_RESEARCH_REFERENCE"],
              UUID(uuidString: reference) != nil else {
            throw XCTSkip("Requires an existing Research Terminal run UUID; never creates research jobs")
        }
        let app = try app(); open("Research Orchestrator", app)
        send("Read the attached research-terminal skill and use only its helper's read-only status command for existing run \(reference). Use the helper normally without exporting environment variables. Do not inspect credentials, create jobs, change files, publish, or contact anyone. If the helper returns ok true, begin your final response MOBILE_RESEARCH_AUTH_OK and give the returned title and status. Otherwise begin MOBILE_RESEARCH_AUTH_FAILED and report the error.", completion: "MOBILE_RESEARCH_AUTH_OK", app)
        let response = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'MOBILE_RESEARCH_AUTH_OK'")).firstMatch
        XCTAssertTrue(response.label.contains("completed"), "Expected the existing completed record")
        app.terminate(); app.launch()
        app.tabBars.buttons["Agents"].tap(); open("Research Orchestrator", app)
        XCTAssertTrue(response.waitForExistence(timeout: 30))
        evidence("Authenticated Research Terminal result after relaunch", app)
    }
    func testResearchWorkerOpen() throws {
        let app = try app(); open("Research Worker", app); evidence("Research Worker writable canonical chat", app)
    }
}

/// Long skill lists show a preview; expand them before searching for a skill.
private func showAllSkills(in app: XCUIApplication) {
    let showAll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show All'")).firstMatch
    if showAll.exists && showAll.isHittable { showAll.tap() }
}
