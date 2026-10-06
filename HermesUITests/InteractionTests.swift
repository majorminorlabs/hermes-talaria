import XCTest

/// Phase 1 flows against the same stores/event loop as the real bridge.
final class InteractionTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ arguments: [String] = []) {
        app = XCUIApplication(); app.launchArguments = ["-uiTesting", "-resetState", "-runSpeed", "0.2"] + arguments; app.launch()
        XCTAssertTrue(app.buttons["ask-toolbar"].waitForExistence(timeout:15))
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func text(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func tab(_ title: String) {
        let button = app.tabBars.buttons[title]
        for _ in 0..<3 where !button.exists { app.swipeDown() }
        XCTAssertTrue(button.waitForExistence(timeout:5)); button.tap()
    }
    private func row(_ title: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@",title)).firstMatch }
    private func reveal(_ element: XCUIElement) { for _ in 0..<6 where !element.exists || !element.isHittable { app.swipeUp() }; XCTAssertTrue(element.waitForExistence(timeout:5)) }
    private func openAsk(_ words: String) {
        app.buttons["ask-toolbar"].tap(); let field = text("ask-text"); XCTAssertTrue(field.waitForExistence(timeout:5)); if !words.isEmpty { field.tap(); field.typeText(words) }
    }
    func testNowEmptyStateAndThreeTabs() {
        launch(["-emptyData", "YES"])
        XCTAssertTrue(app.staticTexts["Nothing needs you. Hermes is idle."].waitForExistence(timeout:10))
        XCTAssertEqual(app.tabBars.buttons.count,3)
        XCTAssertTrue(app.buttons["ask-toolbar"].exists)
    }
    func testClarificationAnswerAndMacOnlyApproval() {
        launch()
        let card = element("needs-you-card-q-expiring")
        XCTAssertTrue(card.waitForExistence(timeout:10)); card.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Answer sent"].waitForExistence(timeout:5) || !card.exists)
        XCTAssertFalse(app.buttons["Approve"].exists); XCTAssertFalse(app.buttons["Deny"].exists)
        tab("Threads"); row("Caddy").tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'Approve on your Mac'")).firstMatch.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["Approve Once"].exists)
    }
    func testAskHermesAndExplicitAgentCreateSeparateThreads() {
        launch(); openAsk("Hello Hermes"); app.buttons["ask-send"].tap()
        XCTAssertTrue(app.buttons["ask-toolbar"].waitForExistence(timeout:10))
        tab("Agents")
        let agent = app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Research Worker' ")).firstMatch
        XCTAssertTrue(agent.waitForExistence(timeout:10)); agent.tap()
        for words in ["First independent request", "Second independent request"] {
            app.buttons["agent-ask"].tap(); let field = text("ask-text"); XCTAssertTrue(field.waitForExistence(timeout:5)); if !words.isEmpty { field.tap(); field.typeText(words) }; app.buttons["ask-send"].tap()
            XCTAssertTrue(app.buttons["agent-ask"].waitForExistence(timeout:10))
        }
        app.navigationBars.buttons.element(boundBy:0).tap(); tab("Threads")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout:5)); search.tap(); search.typeText("independent request")
        if app.keyboards.buttons["Search"].exists { app.keyboards.buttons["Search"].tap() }
        XCTAssertTrue(row("First independent request").waitForExistence(timeout:5))
        XCTAssertTrue(row("Second independent request").waitForExistence(timeout:5))
    }
    func testAmbiguousRoutingRequiresExplicitAgent() {
        launch(); openAsk("Research, find suppliers")
        XCTAssertFalse(app.buttons["ask-send"].isEnabled)
        app.buttons["ask-route-chip"].tap()
        let worker = element("ask-agent-research-worker"); reveal(worker); worker.tap()
        XCTAssertTrue(app.buttons["ask-send"].isEnabled)
    }
    func testOfflineAskIsSavedWithoutExecution() {
        launch(["-simulate", "bridgeOffline"]); openAsk("Do not execute automatically")
        app.buttons["ask-send"].tap(); XCTAssertTrue(app.buttons["ask-toolbar"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'asks not sent'")).firstMatch.waitForExistence(timeout:5))
        app.terminate(); app.launchArguments = ["-uiTesting", "-runSpeed", "0.2"]; app.launch()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'asks not sent'")).firstMatch.waitForExistence(timeout:10))
    }
    func testOfflineCaptureSyncsAfterRelaunchReconnect() {
        launch(["-simulate", "bridgeOffline"]); app.buttons["ask-toolbar"].tap(); app.buttons["capture-button"].tap()
        let field = text("capture-text"); XCTAssertTrue(field.waitForExistence(timeout:5)); field.tap(); field.typeText("  Verbatim capture\nSecond line")
        app.buttons["capture-save"].tap(); XCTAssertTrue(app.buttons["ask-toolbar"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'captures waiting'")).firstMatch.exists)
        app.terminate(); app.launchArguments = ["-uiTesting"]; app.launch()
        XCTAssertTrue(app.buttons["ask-toolbar"].waitForExistence(timeout:10))
        let outbox = app.buttons.matching(NSPredicate(format:"label CONTAINS 'captures waiting' ")).firstMatch
        XCTAssertFalse(outbox.waitForExistence(timeout:3))
    }
    func testVoiceCancelSendsNothing() {
        launch(); openAsk(""); app.buttons["Voice input"].tap()
        XCTAssertTrue(app.buttons["Stop dictation"].waitForExistence(timeout:5)); app.buttons["Cancel"].firstMatch.tap()
        XCTAssertFalse(app.buttons["ask-send"].isEnabled)
    }
    func testAgentModelDefaultAndRevert() {
        launch(); tab("Agents")
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Research Worker' ")).firstMatch.tap()
        let modelRow = app.buttons["agent-model-row"]
        for _ in 0..<5 where !modelRow.exists { app.swipeUp() }
        XCTAssertTrue(modelRow.waitForExistence(timeout:5)); modelRow.tap()
        let local = app.buttons.matching(NSPredicate(format:"label CONTAINS 'Qwen3 Coder 30B' ")).firstMatch
        XCTAssertTrue(local.waitForExistence(timeout:5)); local.tap()
        // iOS can report the row hittable while it sits behind the bottom
        // search accessory. Bring it fully inside the visible list before tapping.
        for _ in 0..<6 where !app.buttons["Apply"].exists || app.buttons["Apply"].frame.maxY > app.frame.maxY - 120 { app.swipeUp() }
        XCTAssertTrue(app.buttons["Apply"].waitForExistence(timeout:5)); app.buttons["Apply"].tap()
        XCTAssertTrue(app.buttons["risk-confirm"].waitForExistence(timeout: 5)); app.buttons["risk-confirm"].tap()
        let revert = app.buttons["Revert"]
        XCTAssertTrue(revert.waitForExistence(timeout:10)); revert.tap()
        XCTAssertTrue(app.staticTexts["Default restored"].waitForExistence(timeout:5))
        XCTAssertFalse(revert.exists)
    }
    func testAccessoryPushToTalkCancelSendsNothing() {
        launch()
        let ask = app.buttons["ask-toolbar"]
        let start = app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0)).withOffset(CGVector(dx:ask.frame.midX,dy:ask.frame.midY))
        start.press(forDuration:0.8,thenDragTo:start.withOffset(CGVector(dx:-140,dy:0)))
        XCTAssertTrue(app.buttons["ask-toolbar"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["ask-send"].exists)
        XCTAssertFalse(app.buttons["Stop dictation"].exists)
    }
    func testToolbarPushToTalkReleasesAndSends() {
        launch(["-vnext.reviewVoiceBeforeSending", "YES"])
        app.buttons["ask-toolbar"].press(forDuration:2.0)
        XCTAssertTrue(app.staticTexts["Handed to Hermes"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["ask-send"].exists)
        tab("Threads")
        XCTAssertTrue(row("Summarize the current work").waitForExistence(timeout:10))
    }
    func testUniformSettingsAndNoBottomAsk() {
        launch()
        for title in ["Now", "Threads", "Agents"] {
            tab(title)
            XCTAssertTrue(app.buttons["talaria-settings"].exists)
            XCTAssertFalse(app.buttons["ask-bar"].exists)
            app.buttons["talaria-settings"].tap()
            XCTAssertTrue(app.navigationBars["Studio"].waitForExistence(timeout:5))
            app.navigationBars.buttons.element(boundBy:0).tap()
        }
    }
    func testToolbarSlideDownLocksUntilStopped() {
        launch()
        let ask = app.buttons["ask-toolbar"]
        let start = ask.coordinate(withNormalizedOffset: CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:1.0,thenDragTo:start.withOffset(CGVector(dx:0,dy:100)))
        XCTAssertTrue(app.staticTexts["Locked"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["ask-send"].exists)
        XCTAssertTrue(app.buttons["held-voice-send"].isHittable)
        app.buttons["held-voice-send"].tap()
        XCTAssertTrue(app.staticTexts["Handed to Hermes"].waitForExistence(timeout:10))
    }
    func testPushToTalkSlideLeftCancelSendsNothing() {
        launch(); openAsk("")
        let mic = app.buttons["Voice input"]
        let start = app.coordinate(withNormalizedOffset: CGVector(dx:0,dy:0)).withOffset(CGVector(dx:mic.frame.midX,dy:mic.frame.midY))
        start.press(forDuration:1.2,thenDragTo:start.withOffset(CGVector(dx:-130,dy:0)))
        XCTAssertFalse(app.buttons["ask-send"].isEnabled)
        XCTAssertFalse(app.buttons["Stop dictation"].exists)
    }
    func testPushToTalkSlideDownLocksUntilExplicitCancel() {
        launch(); openAsk("")
        let mic = app.buttons["Voice input"]
        let start = app.coordinate(withNormalizedOffset: CGVector(dx:0,dy:0)).withOffset(CGVector(dx:mic.frame.midX,dy:mic.frame.midY))
        start.press(forDuration:1.2,thenDragTo:start.withOffset(CGVector(dx:0,dy:100)))
        XCTAssertTrue(app.staticTexts["Locked"].waitForExistence(timeout:5))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertFalse(app.buttons["ask-send"].isEnabled)
    }
    func testSteerStopAndSteps() {
        launch(); tab("Threads"); row("Researcher").tap()
        XCTAssertTrue(app.buttons["Stop run"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["work-status-stop"].exists)
        let field = app.textFields["Add an instruction…"].exists ? app.textFields["Add an instruction…"] : app.textFields.firstMatch
        field.tap(); field.typeText("Focus on the latest hour")
        app.buttons["Send instruction"].tap()
        app.buttons["Stop run"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Partial: stopped before finishing"].waitForExistence(timeout:10) || app.staticTexts["Stopped"].firstMatch.waitForExistence(timeout:5))
        app.buttons["steps-button"].firstMatch.tap(); XCTAssertTrue(app.navigationBars["Steps"].waitForExistence(timeout:5))
    }
}

private extension XCUIElementQuery {
    var lastElement: XCUIElement { element(boundBy: max(0,count - 1)) }
}
