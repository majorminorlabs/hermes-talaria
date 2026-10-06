import XCTest
import UIKit

/// Native editing behavior; these tests never pair or save a production host.
final class FormInputTests: XCTestCase {
    private func paste(_ value: String, into field: XCUIElement, in app: XCUIApplication) {
        UIPasteboard.general.string = value
        field.press(forDuration: 1.0)
        let paste = app.menuItems["Paste"].exists ? app.menuItems["Paste"] : app.buttons["Paste"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5)); paste.tap()
        let allow = app.buttons["Allow Paste"].firstMatch
        if allow.waitForExistence(timeout: 1) { allow.tap() }
    }
    func testHostURLPortAndTokenAllowTypingAndPasting() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-app.backendSimulation", "NO"]; app.launch()
        XCTAssertTrue(app.buttons["ask-toolbar"].waitForExistence(timeout: 15))
        app.buttons["talaria-settings"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Saved Hosts' ")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5)); saved.tap(); app.buttons["Add Host"].tap()
        let name = app.textFields["host-name"], address = app.textFields["host-address"], port = app.textFields["host-port"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Input fixture")
        address.tap(); address.typeText("https://studio.fixture.ts.net")
        XCTAssertEqual(address.value as? String, "https://studio.fixture.ts.net")
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "https://studio.fixture.ts.net".count))
        paste("https://studio.fixture.ts.net:8443", into: address, in: app)
        XCTAssertEqual(address.value as? String, "https://studio.fixture.ts.net:8443")
        port.tap(); port.typeText("8443"); XCTAssertEqual(port.value as? String, "8443")
        port.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        paste("9443", into: port, in: app); XCTAssertEqual(port.value as? String, "9443")
        let token = app.secureTextFields["bridgeToken"]
        XCTAssertTrue(token.waitForExistence(timeout: 5)); token.tap(); token.typeText("typed-fixture")
        XCTAssertEqual((token.value as? String)?.count, "typed-fixture".count)
        token.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "typed-fixture".count))
        paste("pasted-fixture", into: token, in: app)
        XCTAssertEqual((token.value as? String)?.count, "pasted-fixture".count)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Hosts"].waitForExistence(timeout: 5))
    }
    func testAgentNameAndDescriptionAllowTypingAndPasting() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-uiTesting", "-resetState"]; app.launch()
        app.tabBars.buttons["Agents"].tap(); app.buttons["Create Agent"].tap()
        let name = app.textFields["bot-name"]
        let role = app.descendants(matching: .any).matching(identifier: "bot-description").firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Typed Agent")
        XCTAssertEqual(name.value as? String, "Typed Agent")
        role.tap(); role.typeText("Typed role")
        XCTAssertEqual(role.value as? String, "Typed role")
        role.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Typed role".count))
        paste("Pasted role", into: role, in: app)
        XCTAssertEqual(role.value as? String, "Pasted role")
        XCTAssertTrue(app.buttons["Create"].isEnabled)
        app.buttons["Cancel"].tap()
    }
}
