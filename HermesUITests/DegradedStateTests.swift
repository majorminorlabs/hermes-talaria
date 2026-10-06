import XCTest

/// Connection and data states: last-known data while offline, Hermes down
/// behind a reachable bridge, sign-in required, and an empty account.
final class DegradedStateTests: XCTestCase {
    private var directory: URL?

    override func setUpWithError() throws {
        continueAfterFailure = true
        if let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            directory = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(at: directory!, withIntermediateDirectories: true)
        }
    }

    func testDegradedStates() throws {
        // Populate the snapshot cache with a normal session first.
        let warmup = launch(["-resetState"])
        XCTAssertTrue(warmup.buttons["ask-toolbar"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        warmup.terminate()

        let offline = launch(["-simulate", "bridgeOffline"])
        Thread.sleep(forTimeInterval: 3)
        shot("60-home-bridge-offline-cached", offline)
        offline.tabBars.buttons["Threads"].tap()
        Thread.sleep(forTimeInterval: 1)
        shot("61-chat-bridge-offline-cached", offline)
        offline.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Researcher' ")).firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("62-conversation-offline", offline)
        offline.terminate()

        let hermesDown = launch(["-simulate", "hermesOffline"])
        Thread.sleep(forTimeInterval: 3)
        shot("63-home-hermes-offline", hermesDown)
        hermesDown.terminate()

        let auth = launch(["-simulate", "authRequired"])
        Thread.sleep(forTimeInterval: 3)
        shot("64-home-auth-required", auth)
        auth.terminate()

        let empty = launch(["-resetState", "-emptyData", "YES"])
        Thread.sleep(forTimeInterval: 3)
        shot("65-home-empty", empty)
        empty.tabBars.buttons["Threads"].tap()
        Thread.sleep(forTimeInterval: 1)
        shot("66-chat-empty", empty)
        empty.tabBars.buttons["Now"].tap()
        Thread.sleep(forTimeInterval: 1)
        shot("67-tasks-empty", empty)
        empty.terminate()

        let coldOffline = launch(["-resetState", "-simulate", "bridgeOffline"])
        Thread.sleep(forTimeInterval: 3)
        shot("68-home-offline-no-cache", coldOffline)
        coldOffline.tabBars.buttons["Threads"].tap()
        Thread.sleep(forTimeInterval: 1)
        shot("69-chat-offline-no-cache", coldOffline)
        coldOffline.terminate()
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        return app
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
}
