import XCTest

/// Opt-in live rehearsal on two dedicated development simulators.
final class SocialGymRehearsal: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchEnvironment["LIFTRANK_DEMO"] = "1"
        app.launchEnvironment["LIFTRANK_SKIP_HEALTH"] = "1"
        app.launchEnvironment["LIFTRANK_GYM"] = "ui-rehearsal"
        app.launch()
    }

    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        if let old = field.value as? String, !old.isEmpty {
            field.press(forDuration: 1.2)
            let selectAll = app.menuItems.matching(NSPredicate(format: "label IN %@", ["Select All", "全选"])).firstMatch
            let selectButton = app.buttons.matching(NSPredicate(format: "label IN %@", ["Select All", "全选"])).firstMatch
            if selectAll.waitForExistence(timeout: 2) { selectAll.tap() }
            else if selectButton.exists { selectButton.tap() }
            else {
                // A trailing-aligned input may place the caret in the middle on a generic tap.
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
            }
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text.trimmingCharacters(in: .newlines))
    }
    private func setNickname(_ name: String) {
        app.tabBars.buttons.element(boundBy: 4).tap()
        let row = app.buttons["昵称"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        if row.value as? String != name {
            row.tap()
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            replace(field, with: name)
            app.alerts.buttons.element(boundBy: 1).tap()
        }
        app.tabBars.buttons.element(boundBy: 2).tap()
    }
    private func enter(as name: String) {
        let enter = app.buttons["enterDemoGym"]
        XCTAssertTrue(enter.waitForExistence(timeout: 40))
        // The community nickname is the player's nickname from 我的; set a distinct QA name there first.
        setNickname(name)
        let consent = app.switches["gymProfileConsent"]
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in consent.exists || enter.label.contains("Enter live Demo Gym") }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 35), .completed)
        if consent.exists {
            consent.tap()
            let create = app.buttons["createGuestProfile"]
            if !create.isHittable { app.swipeUp() }
            create.tap()
        }
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Enter live Demo Gym"), evaluatedWith: enter)
        waitForExpectations(timeout: 45)
        app.buttons["Community settings"].tap()
        let publicMode = app.segmentedControls["gymVisibility"].buttons.firstMatch
        XCTAssertTrue(publicMode.waitForExistence(timeout: 15))
        if !publicMode.isSelected {
            publicMode.tap()
            let save = app.buttons["saveCommunityProfile"]
            if !save.isHittable { app.swipeUp() }
            save.tap()
            XCTAssertTrue(app.staticTexts["communityProfileSaved"].waitForExistence(timeout: 20))
        }
        let activity = app.switches["Share workout highlights & activity"]
        if activity.exists, activity.value as? String == "0" {
            activity.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: activity)
            waitForExpectations(timeout: 3)
            let save = app.buttons["saveCommunityProfile"]
            if !save.isHittable { app.swipeUp() }
            save.tap()
            XCTAssertTrue(app.staticTexts["communityProfileSaved"].waitForExistence(timeout: 20))
        }
        app.buttons["Done"].tap()
        if !enter.isHittable { app.swipeUp() }
        enter.tap()
        if app.buttons["keepWorkoutBlank"].waitForExistence(timeout: 4) { app.buttons["keepWorkoutBlank"].tap() }
        XCTAssertTrue(app.buttons["Leave"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.tabBars.buttons["Community"].exists, "The gym must stay in the main tab navigation")
        XCTAssertTrue(app.staticTexts["gymSessionSets"].waitForExistence(timeout: 10))
    }
    private func openMember(_ name: String) {
        let member = app.buttons["gymMember.\(name)"]
        XCTAssertTrue(member.waitForExistence(timeout: 60))
        app.scrollViews["gymRoomScroll"].swipeUp()
        member.tap()
        XCTAssertTrue(app.buttons["gymMemberDone"].waitForExistence(timeout: 10))
    }
    private func openChat() {
        let chat = app.buttons["Open private chat"]
        XCTAssertTrue(chat.waitForExistence(timeout: 60)); chat.tap()
        XCTAssertTrue(app.textFields["Message"].waitForExistence(timeout: 10))
    }
    private func send(_ message: String) {
        app.textFields["Message"].tap()
        app.textFields["Message"].typeText(message)
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 30))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func returnToRoom(station: String) {
        app.buttons["gymChatDone"].tap()
        if app.buttons["gymMemberDone"].exists { app.buttons["gymMemberDone"].tap() }
        XCTAssertTrue(app.buttons["Leave"].waitForExistence(timeout: 10))
        let picker = app.buttons["gymStation"]
        if !picker.isHittable { app.swipeUp() }
        picker.tap(); app.buttons[station].tap()
        if app.buttons["Close"].waitForExistence(timeout: 10) { app.buttons["Close"].tap() }
    }
    private func requestBenchPartner() {
        let picker = app.buttons["gymStation"]
        if !picker.isHittable { app.swipeUp() }
        picker.tap(); app.buttons["Bench"].tap()
        let request = app.buttons["Ask to work in"]
        XCTAssertTrue(request.waitForExistence(timeout: 10)); request.tap()
        waitForStation("Bench", member: "QA Taylor")
        capture("Owner approval placed both lifters on the bench")
    }
    private func waitForStation(_ station: String, member: String) {
        expectation(for: NSPredicate(format: "label CONTAINS %@", station), evaluatedWith: app.buttons["gymMember.\(member)"])
        waitForExpectations(timeout: 60)
    }
    private func logAndCheckSharedWorkout() {
        let before = app.staticTexts["gymSessionSets"].label
        if app.buttons["workoutLogFinishedSet"].exists {
            app.buttons["workoutLogFinishedSet"].tap()
            app.buttons["Discard this set"].tap()
        }
        if !app.buttons["workoutEndSet"].exists {
            let start = app.buttons["workoutStartSet"]
            if !start.isHittable { app.swipeUp() }
            start.tap()
            XCTAssertTrue(app.buttons["confirmStartSet"].waitForExistence(timeout: 10))
            app.buttons["confirmStartSet"].tap()
        }
        XCTAssertTrue(app.buttons["workoutEndSet"].waitForExistence(timeout: 10))
        capture("Visible End set while training")
        app.buttons["workoutEndSet"].tap()
        XCTAssertTrue(app.textFields["gymSetWeight"].waitForExistence(timeout: 10))
        replace(app.textFields["gymSetWeight"], with: "61.5")
        replace(app.textFields["gymSetReps"], with: "8")
        let save = app.buttons["gymSaveSet"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["gymSetSaved"].waitForExistence(timeout: 10))
        let after = app.staticTexts["gymSessionSets"].label
        XCTAssertNotEqual(before, after)
        capture("Equipment set saved in the shared workout")
        app.tabBars.buttons["训练"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "继续训练")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["openSocialGym"].tap()
        XCTAssertTrue(app.buttons["Leave"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["gymSessionSets"].label, after, "Switching tabs must retain the same session")
        XCTAssertFalse(app.switches["gymProfileConsent"].exists)
    }

    func testJordan() {
        enter(as: "QA Jordan")
        openMember("QA Taylor")
        for _ in 0..<4 where !app.staticTexts["Last 7 days · muscle map"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Last 7 days · muscle map"].waitForExistence(timeout: 20))
        capture("Shared training profile and muscle map")
        for _ in 0..<4 where !app.buttons["Remove friend"].isHittable && !app.buttons["Add friend"].isHittable { app.swipeDown() }
        if app.buttons["Remove friend"].exists { app.buttons["Remove friend"].tap() }
        if app.buttons["Cancel request"].exists { app.buttons["Cancel request"].tap() }
        let add = app.buttons["Add friend"]
        XCTAssertTrue(add.waitForExistence(timeout: 30)); add.tap()
        openChat()
        send("Hey Taylor, want to train together?")
        XCTAssertTrue(app.staticTexts["Hi Jordan, see you at the bench!"].waitForExistence(timeout: 60))
        returnToRoom(station: "Bench")
        logAndCheckSharedWorkout()
        let workIn = app.buttons["acceptWorkIn"]
        XCTAssertTrue(workIn.waitForExistence(timeout: 60))
        capture("Work-in request needs the current lifter’s approval")
        workIn.tap()
        waitForStation("Bench", member: "QA Taylor")
        let banner = app.buttons["gymMessageBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 60)); banner.tap()
        XCTAssertTrue(app.staticTexts["Ready for the next set?"].waitForExistence(timeout: 20))
        capture("Opened a new private message from inside the gym")
        app.buttons["gymChatDone"].tap()
        XCTAssertTrue(app.buttons["Leave"].exists)
        XCUIDevice.shared.press(.home)
        let background = expectation(description: "Allow background cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { background.fulfill() }
        wait(for: [background], timeout: 10)
        app.activate()
        let enter = app.buttons["enterDemoGym"]
        XCTAssertTrue(enter.waitForExistence(timeout: 10))
        XCTAssertFalse(app.switches["gymProfileConsent"].exists)
        if !enter.isHittable { app.swipeUp() }
        enter.tap()
        XCTAssertTrue(app.buttons["Leave"].waitForExistence(timeout: 20))
        capture("Rejoined without setup and resumed the workout")
        app.buttons["Leave"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(enter.waitForExistence(timeout: 40))
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Enter live Demo Gym"), evaluatedWith: enter)
        waitForExpectations(timeout: 30)
        XCTAssertFalse(app.switches["gymProfileConsent"].exists, "Relaunch restores the approved profile")
        capture("Saved community profile restored after relaunch")
    }

    func testTaylor() {
        enter(as: "QA Taylor")
        let accept = app.buttons["gymAcceptAndChat"]
        XCTAssertTrue(accept.waitForExistence(timeout: 90))
        capture("Incoming friend request appears over the live room")
        accept.tap()
        XCTAssertTrue(app.textFields["Message"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Hey Taylor, want to train together?"].waitForExistence(timeout: 60))
        send("Hi Jordan, see you at the bench!")
        returnToRoom(station: "Cardio")
        waitForStation("Bench", member: "QA Jordan")
        requestBenchPartner()
        app.segmentedControls["communitySection"].buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Messages")).firstMatch.tap()
        let friend = app.buttons["gymFriend.QA Jordan"]
        XCTAssertTrue(friend.waitForExistence(timeout: 10)); friend.tap()
        XCTAssertTrue(app.textFields["Message"].waitForExistence(timeout: 10))
        send("Ready for the next set?")
        app.buttons["gymChatDone"].tap()
        app.segmentedControls["communitySection"].buttons["Gym"].tap()
        capture("Messages subtab keeps the gym session alive")
        XCTAssertTrue(app.buttons["gymMember.QA Jordan"].waitForNonExistence(timeout: 90))
        capture("Backgrounding removes the other avatar")
        app.buttons["Leave"].tap()
    }
    func testAnonymousAndTrainerInbox() {
        enter(as: "QA Jordan")
        app.buttons["Leave"].tap()
        app.buttons["Community settings"].tap()
        app.segmentedControls["gymVisibility"].buttons["Anonymous"].tap()
        let save = app.buttons["saveCommunityProfile"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["communityProfileSaved"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        let enter = app.buttons["enterDemoGym"]
        if !enter.isHittable { app.swipeUp() }
        enter.tap()
        let anonymous = app.buttons["gymMember.Anonymous lifter"]
        XCTAssertTrue(anonymous.waitForExistence(timeout: 30))
        app.scrollViews["gymRoomScroll"].swipeUp()
        anonymous.tap()
        XCTAssertFalse(app.buttons["gymMemberDone"].exists)
        capture("Anonymous lifter has a generic avatar and no profile")
        app.segmentedControls["communitySection"].buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Messages")).firstMatch.tap()
        let trainer = app.buttons["trainerRecipient"]
        XCTAssertTrue(trainer.waitForExistence(timeout: 10)); trainer.tap()
        XCTAssertTrue(app.textFields["trainerInput"].waitForExistence(timeout: 10) || app.textViews["trainerInput"].exists)
        capture("AI trainer is a persistent Messages recipient")
        let input = app.textViews["trainerInput"].exists ? app.textViews["trainerInput"] : app.textFields["trainerInput"]
        let previousReply = app.staticTexts["trainerLatestReply"].exists ? app.staticTexts["trainerLatestReply"].label : ""
        input.tap(); input.typeText("Hi! Please just say hello. Do not change my workout.")
        app.buttons["trainerSend"].tap()
        let latest = app.staticTexts["trainerLatestReply"]
        XCTAssertTrue(latest.waitForExistence(timeout: 80))
        expectation(for: NSPredicate(format: "label != %@", previousReply), evaluatedWith: latest)
        waitForExpectations(timeout: 135)
        capture("Trainer answers an ordinary chat without requiring a plan")
        input.tap()
        input.typeText("Add exactly two remaining sets of bench press, 8 reps and 90 seconds rest to my current workout todos. Keep all recorded sets.")
        app.buttons["trainerSend"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Remaining workout todos updated. Recorded sets are locked."), evaluatedWith: latest)
        waitForExpectations(timeout: 135)
        capture("Trainer directly updates remaining todos from Messages")
        app.buttons["Done"].tap()
        app.segmentedControls["communitySection"].buttons["Gym"].tap()
        app.buttons["Leave"].tap()
        app.buttons["Community settings"].tap()
        app.segmentedControls["gymVisibility"].buttons["Public"].tap()
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["communityProfileSaved"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
    }


    private func verifyTimedCardio(outdoor: Bool) {
        let endQuery = app.buttons.matching(identifier: "endCardioTimer")
        XCTAssertTrue(endQuery.firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["添加动作"].exists)
        XCTAssertFalse(app.buttons["Choose an optional preset"].exists)
        XCTAssertFalse(app.textFields["gymSetReps"].exists)
        let timer = app.staticTexts.matching(identifier: "cardioElapsed").firstMatch
        XCTAssertTrue(timer.waitForExistence(timeout: 10))
        let before = timer.label
        expectation(for: NSPredicate(format: "label != %@", before), evaluatedWith: timer)
        waitForExpectations(timeout: 5)
        if outdoor { XCTAssertTrue(app.otherElements["outdoorWorkoutMap"].exists || app.maps.firstMatch.exists) }
        capture(outdoor ? "Outdoor cardio timer and map without exercise controls" : "Gym cardio starts its timer automatically")
        let end = endQuery.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(end); end?.tap()
        XCTAssertTrue(app.staticTexts["cardioSaved"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["cardioSavedDuration"].exists)
        XCTAssertFalse(app.textFields["gymSetReps"].exists)
        capture("End cardio saves measured duration without time entry")
        app.buttons["Done"].tap()
    }
    private func startOutdoorCardio() {
        app.tabBars.buttons["训练"].tap()
        let resume = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "继续训练")).firstMatch
        if resume.waitForExistence(timeout: 3) {
            resume.tap()
            if app.buttons["endCardioTimer"].waitForExistence(timeout: 2) {
                app.buttons["endCardioTimer"].tap(); app.buttons["Done"].tap()
            } else {
                app.buttons["完成"].tap()
                let publish = app.buttons["发布训练"]
                XCTAssertTrue(publish.waitForExistence(timeout: 10)); publish.tap()
                XCTAssertTrue(app.navigationBars["训练已发布"].waitForExistence(timeout: 10))
                let done = app.buttons.matching(identifier: "完成").allElementsBoundByIndex.first { $0.isHittable }
                XCTAssertNotNil(done); done?.tap()
            }
        }
        let cardioTab = app.segmentedControls.buttons["有氧"]
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: cardioTab)
        waitForExpectations(timeout: 10); cardioTab.tap()
        if !app.buttons["Start cardio"].waitForExistence(timeout: 3) { cardioTab.tap() }
        app.segmentedControls.buttons["Outdoor"].tap()
        app.buttons["Start cardio"].tap()
        XCTAssertTrue(app.buttons["startCardioTimer"].waitForExistence(timeout: 10))
        app.buttons["startCardioTimer"].tap()
    }
    func testOutdoorBlankWorkout() {
        startOutdoorCardio()
        verifyTimedCardio(outdoor: true)
    }
    func testCardioPauseBackgroundAndLiveActivity() {
        startOutdoorCardio()
        let timer = app.staticTexts.matching(identifier: "cardioElapsed").firstMatch
        let pause = app.buttons["pauseResumeCardio"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        pause.tap()
        XCTAssertTrue(pause.label.contains("Resume"))
        let frozen = timer.label
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(timer.label, frozen)
        capture("Paused cardio timer holds steady")
        app.terminate(); app.launch()
        app.tabBars.buttons["训练"].tap()
        let resumeWorkout = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "继续训练")).firstMatch
        XCTAssertTrue(resumeWorkout.waitForExistence(timeout: 10)); resumeWorkout.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        XCTAssertTrue(pause.label.contains("Resume"))
        XCTAssertEqual(timer.label, frozen, "Paused state survives process termination")
        pause.tap()
        let before = timer.label
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let background = XCTAttachment(screenshot: springboard.screenshot()); background.name = "Live Activity while app is backgrounded"; background.lifetime = .keepAlways; add(background)
        app.activate()
        XCTAssertTrue(timer.waitForExistence(timeout: 10))
        XCTAssertNotEqual(timer.label, before, "Running time must advance while the app is backgrounded")
        verifyTimedCardio(outdoor: true)
    }
    func testCardioLiveActivityControls() {
        startOutdoorCardio()
        XCTAssertTrue(app.buttons["pauseResumeCardio"].waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.005)).press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.75)))
        let lockPause = springboard.buttons["Pause"]
        XCTAssertTrue(lockPause.waitForExistence(timeout: 10), springboard.debugDescription)
        lockPause.tap()
        XCTAssertTrue(springboard.buttons["Resume"].waitForExistence(timeout: 10))
        let lockScreen = XCTAttachment(screenshot: springboard.screenshot()); lockScreen.name = "Lock Screen Live Activity pause and elapsed time"; lockScreen.lifetime = .keepAlways; add(lockScreen)
        springboard.buttons["Resume"].tap()
        XCTAssertTrue(springboard.buttons["Pause"].waitForExistence(timeout: 10))
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)).press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        Thread.sleep(forTimeInterval: 1)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.035)).press(forDuration: 1.2)
        let pause = springboard.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10), springboard.debugDescription)
        pause.tap()
        XCTAssertTrue(springboard.buttons["Resume"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: springboard.screenshot()); attachment.name = "Dynamic Island pause control updates the shared session"; attachment.lifetime = .keepAlways; add(attachment)
        springboard.buttons["Open"].tap()
        XCTAssertTrue(app.buttons["pauseResumeCardio"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["pauseResumeCardio"].label.contains("Resume"))
        let timer = app.staticTexts.matching(identifier: "cardioElapsed").firstMatch
        let before = timer.label
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(timer.label, before)
        app.buttons["pauseResumeCardio"].tap()
        verifyTimedCardio(outdoor: true)
    }
    func testGymCardioTimer() {
        enter(as: "QA Jordan")
        let picker = app.buttons["gymStation"]
        if !picker.isHittable { app.swipeUp() }
        picker.tap(); app.buttons["Cardio"].tap()
        XCTAssertTrue(app.buttons["startCardioTimer"].waitForExistence(timeout: 10))
        app.buttons["startCardioTimer"].tap()
        if app.buttons["Finish workout & start cardio"].waitForExistence(timeout: 2) { app.buttons["Finish workout & start cardio"].tap() }
        verifyTimedCardio(outdoor: false)
        XCTAssertTrue(app.buttons["Leave"].waitForExistence(timeout: 10)); app.buttons["Leave"].tap()
    }
}
