import XCTest

/// UI form/re-read behavior in Simulation; native persistence is checked separately.
final class BotManagementTests: XCTestCase {
    func testCreateEditAndHideBotWithoutChangingIdentity() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiTesting", "-resetState"]; app.launch()
        app.tabBars.buttons["Agents"].tap()
        XCTAssertTrue(app.buttons["Create Agent"].waitForExistence(timeout:10)); app.buttons["Create Agent"].tap()
        let name = app.textFields["bot-name"], role = app.textFields["bot-description"]
        XCTAssertTrue(name.waitForExistence(timeout:10)); name.tap(); name.typeText("Phone form fixture")
        role.tap(); role.typeText("Safe test helper")
        app.buttons["Create"].tap()
        let row = app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Phone form fixture'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:10)); row.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout:10)); app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["bot-name"].waitForExistence(timeout:10))
        let field = app.textFields["bot-name"]; field.tap()
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:"Phone form fixture".count) + "Edited phone fixture")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Edited phone fixture"].waitForExistence(timeout:10))
        let duplicate=app.buttons["Duplicate"]
        for _ in 0..<8 where !duplicate.isHittable { app.swipeUp() }
        XCTAssertTrue(duplicate.isHittable);duplicate.tap()
        XCTAssertTrue(app.staticTexts["Agent duplicated"].waitForExistence(timeout:10))
        app.navigationBars.buttons.element(boundBy:0).tap()
        let copy=app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Edited phone fixture (copy)' ")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout:10))
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Edited phone fixture' AND NOT label BEGINSWITH 'Edited phone fixture (copy)' ")).firstMatch.tap()
        // Hide lives in the Management section at the end of the bot's page.
        let hide = app.buttons["Hide"]
        for _ in 0..<6 where !(hide.exists && hide.isHittable) { app.swipeUp() }
        XCTAssertTrue(hide.waitForExistence(timeout:10)); hide.tap(); app.buttons["Hide Agent"].tap()
        XCTAssertTrue(app.buttons["talaria-settings"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Edited phone fixture' AND NOT label BEGINSWITH 'Edited phone fixture (copy)'")).firstMatch.exists)
    }
}
