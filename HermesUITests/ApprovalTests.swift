import XCTest

final class ApprovalTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(stale: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetState", "-runSpeed", "0.2", "-approvalFixture", "YES", "-staleNextApproval", stale ? "YES" : "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["ask-toolbar"].waitForExistence(timeout: 15))
        return app
    }
    func testApproveOnce() {
        let app = launch()
        let approve = app.buttons["approval-a-rm-once"]
        XCTAssertTrue(approve.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["approval-a-rm-session"].exists)
        XCTAssertTrue(app.buttons["approval-a-rm-deny"].exists)
        XCTAssertFalse(app.buttons["approval-a-rm-always"].exists)
        XCTAssertFalse(app.staticTexts["Moderate risk"].exists)
        let card = app.descendants(matching: .any)["needs-you-card-a-rm"].firstMatch
        XCTAssertFalse(card.buttons["Later"].exists)
        approve.tap()
        XCTAssertTrue(app.staticTexts["Approved"].waitForExistence(timeout: 5))
        XCTAssertFalse(approve.exists)
    }
    func testStaleTapRefreshes() {
        let app = launch(stale: true)
        let approve = app.buttons["approval-a-rm-once"]
        XCTAssertTrue(approve.waitForExistence(timeout: 10))
        approve.tap()
        XCTAssertTrue(app.staticTexts["No longer pending. Refreshed."].waitForExistence(timeout: 5))
        XCTAssertFalse(approve.exists)
    }
    private func waitingRow(_ app: XCUIApplication) -> XCUIElement {
        let row = app.cells.containing(.any, identifier: "work-item-c-caddy").firstMatch
        // Now's Needs You cards precede Working, so the lazy list may not
        // create the run row until it has been scrolled into view.
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.exists)
        XCTAssertTrue(row.isHittable)
        return row
    }
    func testWaitingRunSwipeApprovesOnce() {
        let app = launch()
        waitingRow(app).swipeLeft()
        let approve = app.buttons["now-approval-a-rm-once"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        XCTAssertEqual(approve.label, "Approve")
        XCTAssertTrue(app.buttons["now-approval-a-rm-deny"].exists)
        XCTAssertFalse(app.buttons["now-approval-a-rm-session"].exists)
        approve.tap()
        XCTAssertTrue(app.staticTexts["Approved"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["approval-a-rm-once"].exists)
    }
    func testWaitingRunSwipeDenies() {
        let app = launch()
        waitingRow(app).swipeLeft()
        let deny = app.buttons["now-approval-a-rm-deny"]
        XCTAssertTrue(deny.waitForExistence(timeout: 5))
        deny.tap()
        XCTAssertTrue(app.staticTexts["Denied"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["approval-a-rm-once"].exists)
    }
    func testWaitingRunKeepsStopOnLeadingSwipe() {
        let app = launch()
        let row = waitingRow(app)
        row.swipeRight()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        row.swipeLeft()
        row.swipeLeft()
        XCTAssertTrue(app.buttons["now-approval-a-rm-once"].waitForExistence(timeout: 5))
    }
}
