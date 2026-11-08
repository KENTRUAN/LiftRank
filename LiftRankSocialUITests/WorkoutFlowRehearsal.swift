import XCTest

extension XCUIApplication {
    func leaveGymSavingWorkout() {
        buttons["Leave"].tap()
        let save = buttons["Save workout & leave"]
        if save.waitForExistence(timeout: 2) { save.tap() }
    }
}

/// Offline session/navigation checks; no community backend or Watch is required.
final class WorkoutFlowRehearsal: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en"]
        app.launchEnvironment["LIFTRANK_DEMO"] = "1"
        app.launchEnvironment["LIFTRANK_SKIP_HEALTH"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["openSocialGym"].waitForExistence(timeout: 15))
        return app
    }

    func testLeaveRequiresDecisionAndCancelKeepsWorkout() {
        let app = launch()
        app.buttons["openSocialGym"].tap()
        let start = app.buttons["startPrivateWorkout"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        if app.buttons["keepWorkoutBlank"].waitForExistence(timeout: 3) { app.buttons["keepWorkoutBlank"].tap() }
        let leave = app.buttons["leaveGym"]
        XCTAssertTrue(leave.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["gymInbox"].exists)
        leave.tap()
        XCTAssertTrue(app.buttons["Save workout & leave"].waitForExistence(timeout: 5))
        app.buttons["Keep training"].tap()
        XCTAssertTrue(leave.waitForExistence(timeout: 5))
        leave.tap(); app.buttons["Discard workout & leave"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        if app.buttons["keepWorkoutBlank"].waitForExistence(timeout: 3) { app.buttons["keepWorkoutBlank"].tap() }
        XCTAssertTrue(leave.waitForExistence(timeout: 10)); leave.tap()
        app.buttons["Save workout & leave"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
    }

    func testHomeCardioStartsIndoorsAndOutdoorsWithoutEnteringGym() {
        let app = launch()
        app.segmentedControls.buttons["Cardio"].tap()
        let start = app.buttons["openCardioStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        for location in ["Indoor", "Outdoor"] {
            start.tap()
            XCTAssertTrue(app.buttons["startCardioTimer"].waitForExistence(timeout: 5))
            app.segmentedControls.buttons[location].tap()
            app.buttons["startCardioTimer"].tap()
            if app.buttons["Finish workout & start cardio"].waitForExistence(timeout: 2) {
                app.buttons["Finish workout & start cardio"].tap()
            }
            XCTAssertTrue(app.buttons["endCardioTimer"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.buttons["leaveGym"].exists)
            if location == "Outdoor" { XCTAssertTrue(app.otherElements["outdoorWorkoutMap"].waitForExistence(timeout: 5)) }
            else { XCTAssertFalse(app.otherElements["outdoorWorkoutMap"].exists) }
            app.buttons["endCardioTimer"].tap()
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10)); app.buttons["Done"].tap()
            XCTAssertTrue(start.waitForExistence(timeout: 10))
        }
    }

    func testOutdoorSelectionRemovesMachinesAndReplacesIndoorOnlySelection() {
        let app = launch()
        app.segmentedControls.buttons["Cardio"].tap()
        app.buttons["openCardioStart"].tap()
        let picker = app.buttons["cardioActivity"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); picker.tap()
        app.buttons["Elliptical"].tap()
        XCTAssertTrue(picker.label.contains("Elliptical"))
        app.segmentedControls.buttons["Outdoor"].tap()
        XCTAssertTrue(picker.label.contains("Running"))
        picker.tap()
        for name in ["Elliptical", "Rowing", "Stair climbing"] { XCTAssertFalse(app.buttons[name].exists, name) }
        app.buttons["Walking"].tap()
        app.segmentedControls.buttons["Indoor"].tap()
        XCTAssertTrue(picker.label.contains("Walking"))
        picker.tap()
        for name in ["Elliptical", "Rowing", "Stair climbing"] { XCTAssertTrue(app.buttons[name].exists, name) }
        app.buttons["Running"].tap()
        app.buttons["Close"].tap()
    }

    func testMemberProfileShowsTheirTrainingMascot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en", "-trainingAvatar.mascotStyle", "nailong"]
        app.launchEnvironment["LIFTRANK_DEMO"] = "1"
        app.launchEnvironment["LIFTRANK_SKIP_HEALTH"] = "1"
        app.launchEnvironment["LIFTRANK_GYM"] = "sample"
        app.launch()
        let member = app.buttons["gymMember.Alex · sample"]
        XCTAssertTrue(member.waitForExistence(timeout: 15))
        for _ in 0..<3 where !member.isHittable { app.swipeUp() }
        member.tap()
        let mascot = app.images["sharedTrainingAvatar"]
        XCTAssertTrue(mascot.waitForExistence(timeout: 10))
        XCTAssertTrue(mascot.label.contains("Doubao"), mascot.label)
        XCTAssertTrue(mascot.label.contains("Platinum"), mascot.label)
        XCTAssertFalse(app.buttons["旋转配饰"].exists)
        app.buttons["gymMemberDone"].tap()
    }

    func testCardioLockScreenAndDynamicIslandControlsShareWorkout() {
        let app = launch()
        app.segmentedControls.buttons["Cardio"].tap()
        app.buttons["openCardioStart"].tap()
        XCTAssertTrue(app.buttons["startCardioTimer"].waitForExistence(timeout: 10))
        app.buttons["startCardioTimer"].tap()
        if app.buttons["Finish workout & start cardio"].waitForExistence(timeout: 2) { app.buttons["Finish workout & start cardio"].tap() }
        XCTAssertTrue(app.buttons["pauseResumeCardio"].waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openNotificationCenter(springboard)
        XCTAssertTrue(springboard.buttons["Pause"].waitForExistence(timeout: 10), springboard.debugDescription)
        springboard.buttons["Pause"].tap()
        XCTAssertTrue(springboard.buttons["Resume"].waitForExistence(timeout: 10))
        capture(springboard, "Cardio Lock Screen Live Activity paused")
        springboard.buttons["Resume"].tap()
        XCTAssertTrue(springboard.buttons["Pause"].waitForExistence(timeout: 10))
        closeNotificationCenter(springboard)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.035)).press(forDuration: 1.2)
        XCTAssertTrue(springboard.buttons["Pause"].waitForExistence(timeout: 10), springboard.debugDescription)
        springboard.buttons["Pause"].tap()
        XCTAssertTrue(springboard.buttons["Resume"].waitForExistence(timeout: 10))
        capture(springboard, "Dynamic Island updates the same cardio workout")
        springboard.buttons["Open"].tap()
        XCTAssertTrue(app.buttons["pauseResumeCardio"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["pauseResumeCardio"].label.contains("Resume"))
        app.buttons["endCardioTimer"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10)); app.buttons["Done"].tap()
        XCUIDevice.shared.press(.home)
        openNotificationCenter(springboard)
        XCTAssertTrue(springboard.buttons["Resume"].waitForNonExistence(timeout: 10))
        closeNotificationCenter(springboard)
    }

    func testLiveActivityControlsRecoverAfterPhoneProcessTerminates() {
        let app = launch()
        app.segmentedControls.buttons["Cardio"].tap()
        app.buttons["openCardioStart"].tap()
        XCTAssertTrue(app.buttons["startCardioTimer"].waitForExistence(timeout: 10))
        app.buttons["startCardioTimer"].tap()
        if app.buttons["Finish workout & start cardio"].waitForExistence(timeout: 2) { app.buttons["Finish workout & start cardio"].tap() }
        XCTAssertTrue(app.buttons["pauseResumeCardio"].waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openNotificationCenter(springboard)
        XCTAssertTrue(springboard.buttons["Pause"].waitForExistence(timeout: 10))
        app.terminate()
        springboard.buttons["Pause"].tap()
        XCTAssertTrue(springboard.buttons["Resume"].waitForExistence(timeout: 15))
        closeNotificationCenter(springboard)
        // The intent launch has no XCTest environment. Relaunch with the offline
        // fixture before inspecting the persisted pause without a Health prompt.
        app.launch()
        XCTAssertTrue(app.segmentedControls.buttons["Cardio"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["Cardio"].tap()
        app.buttons["openCardioStart"].tap()
        XCTAssertTrue(app.buttons["startCardioTimer"].waitForExistence(timeout: 10))
        app.buttons["startCardioTimer"].tap()
        let resume = app.buttons["pauseResumeCardio"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10)); XCTAssertTrue(resume.label.contains("Resume"))
        app.buttons["endCardioTimer"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10)); app.buttons["Done"].tap()
    }

    func testStrengthLiveActivityOpensWorkoutAndEndsOnDiscard() {
        let app = launch()
        app.buttons["openSocialGym"].tap()
        XCTAssertTrue(app.buttons["startPrivateWorkout"].waitForExistence(timeout: 15)); app.buttons["startPrivateWorkout"].tap()
        if app.buttons["keepWorkoutBlank"].waitForExistence(timeout: 3) { app.buttons["keepWorkoutBlank"].tap() }
        XCTAssertTrue(app.buttons["leaveGym"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openNotificationCenter(springboard)
        XCTAssertTrue(springboard.staticTexts["Strength"].waitForExistence(timeout: 10), springboard.debugDescription)
        XCTAssertTrue(springboard.staticTexts["0 sets"].exists)
        XCTAssertFalse(springboard.buttons["Pause"].exists)
        capture(springboard, "Strength Live Activity with completed sets")
        closeNotificationCenter(springboard)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.035)).press(forDuration: 1.2)
        XCTAssertTrue(springboard.buttons["Open"].waitForExistence(timeout: 10))
        springboard.buttons["Open"].tap()
        XCTAssertTrue(app.buttons["collapseWorkout"].waitForExistence(timeout: 15))
        app.buttons["collapseWorkout"].tap()
        XCTAssertTrue(app.buttons["openSocialGym"].waitForExistence(timeout: 10)); app.buttons["openSocialGym"].tap()
        XCTAssertTrue(app.buttons["leaveGym"].waitForExistence(timeout: 15))
        app.buttons["leaveGym"].tap(); app.buttons["Discard workout & leave"].tap()
        XCTAssertTrue(app.buttons["startPrivateWorkout"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        openNotificationCenter(springboard)
        XCTAssertTrue(springboard.staticTexts["Strength"].waitForNonExistence(timeout: 10))
        closeNotificationCenter(springboard)
    }

    private func openNotificationCenter(_ springboard: XCUIApplication) {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.005)).press(forDuration: 0.1,
            thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.75)))
    }
    private func closeNotificationCenter(_ springboard: XCUIApplication) {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)).press(forDuration: 0.1,
            thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
