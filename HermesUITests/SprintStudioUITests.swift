import XCTest

/// Explicit physical opt-in. Uses existing Keychain pairing; no fixture credentials.
final class SprintStudioUITests: XCTestCase {
    private var probeName: String { ProcessInfo.processInfo.environment["HERMES_PROBE_BOT_NAME"] ?? "Mobile Acceptance 20261004A" }
    private func studio() throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["HERMES_SPRINT_UI"] == "1" else { throw XCTSkip("Requires unlocked paired iPhone") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Agents"].waitForExistence(timeout:20)); app.tabBars.buttons["Agents"].tap()
        return app
    }
    private func row(_ name:String,_ app:XCUIApplication)->XCUIElement { app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@",name)).firstMatch }
    private func input(_ app:XCUIApplication)->XCUIElement { app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch }
    private func chat(_ app:XCUIApplication) {
        let chat=app.buttons["agent-ask"].firstMatch
        for _ in 0..<20 where !chat.isHittable { app.swipeDown() }
        XCTAssertTrue(chat.waitForExistence(timeout:20)); chat.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout:20) || app.textViews.firstMatch.exists)
    }
    private func evidence(_ name:String,_ app:XCUIApplication) { print("PHYSICAL ACCEPTANCE: \(name)");let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
    private func send(_ text:String,_ prefix:String,_ app:XCUIApplication) {
        let field=input(app);field.tap();field.typeText(text);app.buttons["Send"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@",prefix)).firstMatch.waitForExistence(timeout:180));evidence(prefix,app)
    }
    func testPostgresSearchInCanonicalOrchestrator() throws {
        let app=try studio();XCTAssertTrue(row("Research Orchestrator",app).waitForExistence(timeout:30));row("Research Orchestrator",app).tap();chat(app)
        let marker="SPRINT_PHONE_PG_" + String(Int(Date().timeIntervalSince1970))
        send("Read the attached research-terminal skill and use only its helper read-only search for Hermes, limit 5, normally with the existing environment. Do not create jobs, change files, export environment variables, inspect credentials, or contact anyone. On successful retrieval begin \(marker) and give count, first source title, and its record ID. On failure state the error.",marker,app)
        let result=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@",marker)).firstMatch
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'Memory-Efficient Pipeline'")).firstMatch.waitForExistence(timeout:20))
        app.terminate();app.launch();app.tabBars.buttons["Agents"].tap();row("Research Orchestrator",app).tap();chat(app)
        XCTAssertTrue(result.waitForExistence(timeout:30))
        for _ in 0..<8 where !result.isHittable {
            app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.65)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)))
        }
        XCTAssertTrue(result.isHittable);evidence("Fresh PostgreSQL result visibly rendered after relaunch",app)
        XCUIDevice.shared.press(.home);app.activate();XCTAssertTrue(result.waitForExistence(timeout:20))
    }
    func testCreateEditAndCanonicalChat() throws {
        let app=try studio()
        // Let the live roster refresh before deciding whether this fixture is
        // absent; a retained bot can also be below the List's visible cells.
        _ = row(probeName,app).waitForExistence(timeout:10)
        for _ in 0..<5 where !row(probeName,app).exists { app.swipeUp() }
        if !row(probeName,app).exists {
        XCTAssertTrue(app.buttons["Create Agent"].waitForExistence(timeout:30));app.buttons["Create Agent"].tap()
        let name=app.textFields["bot-name"]
        if !name.waitForExistence(timeout:60), let retry = app.buttons.matching(identifier:"Retry").allElementsBoundByIndex.first(where: { $0.isHittable }) { evidence("Transient inventory failure before explicit Retry",app);retry.tap() }
        XCTAssertTrue(name.waitForExistence(timeout:60));name.tap();name.typeText(probeName);XCTAssertEqual(name.value as? String,probeName)
        app.textFields["bot-description"].tap();app.textFields["bot-description"].typeText("Harmless physical phone validation");XCTAssertTrue((app.textFields["bot-description"].value as? String ?? "").contains("Harmless physical"))
        let soul=app.textViews["bot-soul"];for _ in 0..<5 where !soul.isHittable { app.swipeUp() };soul.tap();soul.typeText("You are a temporary mobile validation bot. Answer briefly. Run no tools unless explicitly requested. Never inspect credentials.")
        evidence("Physical create form before submit",app)
        XCTAssertTrue(app.buttons["Create"].isEnabled,"Valid native bot draft must be enabled")
        app.buttons["Create"].tap()
        let dismissed=expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.navigationBars["New Bot"])
        XCTAssertEqual(XCTWaiter.wait(for:[dismissed],timeout:120),.completed)
        }
        XCTAssertTrue(row(probeName,app).waitForExistence(timeout:30));row(probeName,app).tap();evidence("Created native phone bot",app)
        let readyToEdit=expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:app.buttons["Edit"])
        XCTAssertEqual(XCTWaiter.wait(for:[readyToEdit],timeout:100),.completed)
        app.buttons["Edit"].tap();let role=app.textFields["bot-description"]
        if !role.waitForExistence(timeout:20), let retry = app.buttons.matching(identifier:"Retry").allElementsBoundByIndex.first(where: { $0.isHittable }) { retry.tap() }
        XCTAssertTrue(role.waitForExistence(timeout:100));role.tap();role.typeText(". Edited on iPhone")
        let editedSoul=app.textViews["bot-soul"];for _ in 0..<5 where !editedSoul.isHittable { app.swipeUp() };XCTAssertTrue((editedSoul.value as? String ?? "").contains("temporary mobile validation bot"));editedSoul.tap();editedSoul.typeText(" Edited SOUL on physical iPhone: keep answers brief.")
        app.buttons["Save"].tap()
        let saved=expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.navigationBars["Edit Bot"])
        XCTAssertEqual(XCTWaiter.wait(for:[saved],timeout:120),.completed)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'Edited on iPhone'")).firstMatch.waitForExistence(timeout:20));evidence("Edited native phone bot",app)
        XCUIDevice.shared.press(.home);Thread.sleep(forTimeInterval:3);app.activate()
        chat(app);send("Reply exactly SPRINT_PHONE_NEW_BOT_CHAT_OK. Do not run tools.","SPRINT_PHONE_NEW_BOT_CHAT_OK",app)
        app.terminate();app.launch();app.tabBars.buttons["Agents"].tap();XCTAssertTrue(row(probeName,app).waitForExistence(timeout:30));row(probeName,app).tap();chat(app)
        XCTAssertTrue(app.staticTexts["SPRINT_PHONE_NEW_BOT_CHAT_OK"].waitForExistence(timeout:30));evidence("Native bot canonical history after relaunch",app)
    }
    func testCameraCapturePreviewAndSend() throws {
        let app=try studio();XCTAssertTrue(row(probeName,app).waitForExistence(timeout:30));row(probeName,app).tap();chat(app)
        app.buttons["Add attachment"].tap();app.buttons["Camera"].tap()
        let spring=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        let allow=spring.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout:5) { allow.tap() }
        let shutter=app.buttons["Take Picture"]
        XCTAssertTrue(shutter.waitForExistence(timeout:15));shutter.tap()
        let use=app.buttons["Use Photo"];XCTAssertTrue(use.waitForExistence(timeout:15));use.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Remove Photo-'")).firstMatch.waitForExistence(timeout:20));evidence("New camera preview attached",app)
        send("Reply SPRINT_PHONE_CAMERA_OK and describe the newly attached camera photo briefly. Use no tools or other files.","SPRINT_PHONE_CAMERA_OK",app)
    }
    func testNativePhotoPickerAndSend() throws {
        guard let safePhoto = ProcessInfo.processInfo.environment["HERMES_SAFE_PHOTO_LABEL"], !safePhoto.isEmpty else {
            throw XCTSkip("Supply the accessibility label of an inspected harmless photo")
        }
        let app=try studio();XCTAssertTrue(row(probeName,app).waitForExistence(timeout:30));row(probeName,app).tap();chat(app)
        app.buttons["Add attachment"].tap();app.buttons["Photo Library"].tap()
        let photo=app.images.matching(NSPredicate(format:"identifier == 'PXGGridLayout-Info' AND label BEGINSWITH %@",safePhoto)).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout:15));photo.tap()
        if app.buttons["Add"].exists { app.buttons["Add"].tap() }
        else if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Remove Photo-'")).firstMatch.waitForExistence(timeout:20));evidence("Photo library preview attached",app)
        send("Reply SPRINT_PHONE_LIBRARY_OK and confirm the attached photo is present. Do not inspect credentials, other files or run tools.","SPRINT_PHONE_LIBRARY_OK",app)
    }
    func testVoiceCapturePartialEditAndSend() throws {
        let app=try studio();XCTAssertTrue(row(probeName,app).waitForExistence(timeout:30));row(probeName,app).tap();chat(app)
        app.buttons["Voice input"].tap()
        let spring=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        for _ in 0..<2 {
            if app.buttons["Stop dictation"].exists { break }
            let allow=spring.alerts.buttons["Allow"]
            if allow.waitForExistence(timeout:5) { allow.tap() }
        }
        XCTAssertTrue(app.buttons["Stop dictation"].waitForExistence(timeout:15));app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Voice input"].waitForExistence(timeout:15));evidence("Native voice cancel returned to editable composer",app)
        app.buttons["Voice input"].tap();XCTAssertTrue(app.buttons["Stop dictation"].waitForExistence(timeout:15));evidence("Native voice recording active",app)
        // A real spoken sentence is needed on the physical microphone. No audio fixtures enter Hermes.
        let field=input(app)
        let hasWords=NSPredicate(format:"value CONTAINS[c] 'physical iPhone voice input test'")
        let partial=expectation(for:hasWords,evaluatedWith:field)
        XCTAssertEqual(XCTWaiter.wait(for:[partial],timeout:180),.completed)
        evidence("Real microphone partial words",app)
        if app.buttons["Stop dictation"].exists { app.buttons["Stop dictation"].tap() };field.tap();field.typeText(" Edited before sending. Reply SPRINT_PHONE_VOICE_OK.")
        let edited=XCTAttachment(string:field.value as? String ?? "");edited.name="Exact edited composer text before send";edited.lifetime = .keepAlways;add(edited)
        app.buttons["Send"].tap();XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH 'SPRINT_PHONE_VOICE_OK'")).firstMatch.waitForExistence(timeout:120));evidence("Edited voice text received",app)
        XCUIDevice.shared.press(.home);app.activate();XCTAssertTrue(app.buttons["Voice input"].waitForExistence(timeout:15))
    }

    func testFilesPickerAndBackgroundRecovery() throws {
        let app=try studio();XCTAssertTrue(row(probeName,app).waitForExistence(timeout:30));row(probeName,app).tap();chat(app)
        app.buttons["Add attachment"].tap();app.buttons["Files"].tap()
        evidence("Native Files picker",app)
        let search=app.searchFields.firstMatch
        if search.waitForExistence(timeout:10) { search.tap();search.typeText("Hermes-Physical-Acceptance") }
        let file=app.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH 'Hermes-Physical-Acceptance'")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout:30));file.tap()
        if app.buttons["Open"].exists { app.buttons["Open"].tap() }
        XCTAssertTrue(app.buttons["Remove Hermes-Physical-Acceptance.txt"].waitForExistence(timeout:20));evidence("Physical Files preview",app)
        let field=input(app);field.tap();field.typeText("Read only the attached harmless test file. Reply SPRINT_PHONE_FILE_OK and repeat its marker. No other files or tools.");app.buttons["Send"].tap()
        XCTAssertTrue(app.buttons["Stop run"].waitForExistence(timeout:20))
        XCUIDevice.shared.press(.home);Thread.sleep(forTimeInterval:4);app.activate()
        let reply=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH 'SPRINT_PHONE_FILE_OK'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout:180))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'PHONE_FILE_MARKER_9017'")).firstMatch.exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH 'SPRINT_PHONE_FILE_OK'")).count,1)
        evidence("Physical file response after background replay",app)
    }
    func testHideWithHistoryPreservationConfirmation() throws {
        let app=try studio();XCTAssertTrue(row(probeName,app).waitForExistence(timeout:30));row(probeName,app).tap()
        let hide=app.buttons["Hide"];XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout:20))
        for _ in 0..<40 where !(hide.exists && hide.isHittable) { app.swipeUp() }  // Management section is last
        XCTAssertTrue(hide.waitForExistence(timeout:20));hide.tap()
        XCTAssertTrue(app.buttons["Hide Agent"].waitForExistence(timeout:15));evidence("Physical hide confirmation retains history",app);app.buttons["Hide Agent"].tap()
        XCTAssertTrue(app.buttons["talaria-settings"].waitForExistence(timeout:120))
        let hidden=expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:row(probeName,app))
        XCTAssertEqual(XCTWaiter.wait(for:[hidden],timeout:120),.completed);evidence("Phone bot hidden",app)
    }

    func testRestorePhoneTailscaleConnection() throws {
        guard ProcessInfo.processInfo.environment["HERMES_SPRINT_UI"] == "1" else { throw XCTSkip("Physical opt-in") }
        continueAfterFailure=false
        let vpn=XCUIApplication(bundleIdentifier:"io.tailscale.ipn.ios");vpn.launch()
        if vpn.buttons["Connect"].waitForExistence(timeout:5) { vpn.buttons["Connect"].tap() }
        XCTAssertTrue(vpn.staticTexts["Connected"].waitForExistence(timeout:30))
        let shot=XCTAttachment(screenshot:vpn.screenshot());shot.name="Physical Tailscale connection state";shot.lifetime = .keepAlways;add(shot)
        let state=XCTAttachment(string:vpn.debugDescription);state.name="Physical Tailscale accessibility";state.lifetime = .keepAlways;add(state)
        assertTalariaIdentity()
    }

    func testTalariaTableSkillsAndIdentity() throws {
        let app=try studio()
        XCTAssertTrue(row("Research Orchestrator",app).waitForExistence(timeout:30));row("Research Orchestrator",app).tap()
        let showAll=app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Show All'")).firstMatch
        for _ in 0..<35 where !showAll.isHittable {
            app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.72)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.43)))
        }
        XCTAssertTrue(showAll.isHittable);showAll.tap()
        XCTAssertTrue(app.buttons["Show Fewer"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["research-terminal"].exists);evidence("Talaria expanded native skills",app)
        app.navigationBars.buttons.element(boundBy:0).tap()
        XCTAssertTrue(row(probeName,app).waitForExistence(timeout:30));row(probeName,app).tap();chat(app)
        let marker="TALARIA_PHONE_TABLE_"+String(Int(Date().timeIntervalSince1970))
        send("Reply with \(marker) on its own line, then exactly this Markdown table, and nothing else. No tools.\n\n| Check | Result |\n| --- | --- |\n| Talaria table acceptance | Passed |\n| Editable text | Preserved |",marker,app)
        XCTAssertTrue(app.descendants(matching:.any)["markdown-table-grid"].firstMatch.waitForExistence(timeout:15));evidence("Talaria physical normal table",app)
        app.terminate();app.launchArguments=["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityL"];app.launch()
        XCTAssertTrue(app.tabBars.buttons["Agents"].waitForExistence(timeout:20));app.tabBars.buttons["Agents"].tap();row(probeName,app).tap();chat(app)
        let table=app.descendants(matching:.any)["markdown-table-accessible"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout:15))
        for _ in 0..<10 where !table.isHittable { app.swipeDown() }
        XCTAssertTrue(table.isHittable);evidence("Talaria physical accessibility table",app)
        app.navigationBars.buttons.element(boundBy:0).tap();XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout:15))
        app.terminate();app.launchArguments=[];app.launch();XCUIDevice.shared.press(.home)
        assertTalariaIdentity();app.activate()
    }

    private func assertTalariaIdentity() {
        XCUIDevice.shared.press(.home)
        let spring=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        let icon=spring.icons["Talaria"].firstMatch
        // Springboard virtualizes icons on other Home pages.
        for _ in 0..<5 where !(icon.exists && icon.isHittable) { spring.swipeLeft() }
        XCTAssertTrue(icon.waitForExistence(timeout:10));XCTAssertTrue(icon.isHittable)
        evidence("Physical Talaria icon and display name",spring)
    }

    func testInspectPhotoLibraryPicker() throws {
        let app=try studio();XCTAssertTrue(row(probeName,app).waitForExistence(timeout:30));row(probeName,app).tap();chat(app)
        app.buttons["Add attachment"].tap();app.buttons["Photo Library"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout:20))
        evidence("Physical photo library picker before selection",app)
        let tree=XCTAttachment(string:app.debugDescription);tree.name="Photo picker accessibility";tree.lifetime = .keepAlways;add(tree)
    }

}
