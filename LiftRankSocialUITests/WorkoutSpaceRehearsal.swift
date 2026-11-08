import XCTest

/// Run with the emulator configuration and a dedicated demo app bundle.
final class WorkoutSpaceRehearsal: XCTestCase {
    private func liveApp(_ name: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en"]
        app.launchEnvironment["LIFTRANK_DEMO"] = "1"
        app.launchEnvironment["LIFTRANK_SKIP_HEALTH"] = "1"
        app.launchEnvironment["LIFTRANK_GYM"] = "live"
        app.launchEnvironment["LIFTRANK_GYM_NAME"] = name
        app.launch()
        if app.buttons["keepWorkoutBlank"].waitForExistence(timeout: 10) { app.buttons["keepWorkoutBlank"].tap() }
        XCTAssertTrue(app.buttons["Leave"].waitForExistence(timeout: 30))
        app.leaveGymSavingWorkout()
        return app
    }
    func testPublicSpaceOwner() {
        let app = liveApp("Space owner")
        let create = app.buttons["createWorkoutSpace"]
        XCTAssertTrue(create.waitForExistence(timeout: 30))
        for _ in 0..<3 where !create.isHittable { app.swipeUp() }
        create.tap()
        app.segmentedControls.buttons["Public"].tap()
        app.buttons["confirmCreateSpace"].tap()
        XCTAssertTrue(app.buttons["acceptSpaceRequest"].waitForExistence(timeout: 90), app.debugDescription)
        app.buttons["acceptSpaceRequest"].tap()
        let two = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2 in the room")).firstMatch
        XCTAssertTrue(two.waitForExistence(timeout: 60))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Two users admitted to a nearby public space"; shot.lifetime = .keepAlways; add(shot)
        app.leaveGymSavingWorkout()
    }
    func testPublicSpaceJoiner() {
        let app = liveApp("Space joiner")
        let ask = app.buttons.matching(identifier: "Ask to join").firstMatch
        for _ in 0..<10 {
            if ask.exists { break }
            let refresh = app.buttons["Refresh nearby spaces"]
            if refresh.exists { refresh.tap() }
            _ = ask.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(ask.exists, app.debugDescription)
        for _ in 0..<3 where !ask.isHittable { app.swipeUp() }
        ask.tap()
        let join = app.buttons["joinInvitedSpace"]
        XCTAssertTrue(join.waitForExistence(timeout: 90))
        for _ in 0..<3 where !join.isHittable { app.swipeDown() }
        join.tap()
        XCTAssertTrue(app.buttons["Leave"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["workoutStartSet"].waitForExistence(timeout: 10))
        let one = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 in the room")).firstMatch
        XCTAssertTrue(one.waitForExistence(timeout: 60))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Space remains open after creator leaves"; shot.lifetime = .keepAlways; add(shot)
        app.leaveGymSavingWorkout()
    }
    func testPrivateSpaceZoomAndWorkoutControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LIFTRANK_DEMO"] = "1"
        app.launchEnvironment["LIFTRANK_SKIP_HEALTH"] = "1"
        app.launchArguments = ["-appLanguage", "en"]
        app.launch()
        let start = app.buttons["openSocialGym"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertTrue(app.otherElements["trainerWelcome"].exists || app.staticTexts["AI trainer"].exists)
        XCTAssertFalse(app.buttons["startBlankWorkout"].exists)
        start.tap()
        let solo = app.buttons["startPrivateWorkout"]
        XCTAssertTrue(solo.waitForExistence(timeout: 15)); solo.tap()
        if app.buttons["keepWorkoutBlank"].waitForExistence(timeout: 3) { app.buttons["keepWorkoutBlank"].tap() }
        if app.buttons["endCardioTimer"].exists {
            app.buttons["endCardioTimer"].tap()
            XCTAssertTrue(solo.waitForExistence(timeout: 10)); solo.tap()
            if app.buttons["keepWorkoutBlank"].waitForExistence(timeout: 3) { app.buttons["keepWorkoutBlank"].tap() }
        }
        XCTAssertTrue(app.buttons["Leave"].waitForExistence(timeout: 10))
        // The dedicated rehearsal app retains history between runs. Clear only an
        // unfinished test set so a previous interrupted run can be repeated.
        if app.buttons["workoutEndSet"].exists { app.buttons["workoutEndSet"].tap() }
        if app.buttons["workoutLogFinishedSet"].exists { app.buttons["workoutLogFinishedSet"].tap() }
        if app.buttons["Discard this set"].exists { app.buttons["Discard this set"].tap() }
        XCTAssertFalse(app.buttons["gymStation"].exists, "Open spaces have no machine picker")
        app.buttons["Zoom in"].tap(); app.buttons["Zoom out"].tap()
        let scene = app.otherElements["walkableGymScene"]
        if scene.exists { scene.pinch(withScale: 1.6, velocity: 1); scene.pinch(withScale: 0.8, velocity: -1) }
        app.buttons["Reset gym view"].tap()
        app.buttons["workoutStartSet"].tap()
        XCTAssertTrue(app.buttons["confirmStartSet"].waitForExistence(timeout: 10))
        app.buttons["confirmStartSet"].tap()
        XCTAssertTrue(app.buttons["workoutEndSet"].waitForExistence(timeout: 10))
        app.buttons["workoutEndSet"].tap()
        XCTAssertTrue(app.textFields["gymSetWeight"].waitForExistence(timeout: 10))
        let reps = app.textFields["gymSetReps"]
        reps.tap()
        if let previous = reps.value as? String, Int(previous) != nil {
            // SwiftUI exposes the whole labeled row. Place the caret at the
            // value's trailing edge, inside the row's 20-point content inset.
            reps.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -22, dy: 0)).tap()
            reps.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        reps.typeText("8")
        XCTAssertEqual(reps.value as? String, "8")
        let save = app.buttons["gymSaveSet"]
        XCTAssertTrue(save.isEnabled)
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["gymSetSaved"].waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Private open floor with zoom and set controls"; shot.lifetime = .keepAlways; add(shot)
        let cardio = app.buttons["spaceChooseCardio"]
        if !cardio.isHittable { app.swipeUp() }
        cardio.tap()
        app.segmentedControls.buttons["Outdoor"].tap()
        app.buttons["startCardioTimer"].tap()
        if app.buttons["Finish workout & start cardio"].waitForExistence(timeout: 2) { app.buttons["Finish workout & start cardio"].tap() }
        let pause = app.buttons["pauseResumeCardio"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15)); pause.tap()
        let elapsed = app.staticTexts.matching(identifier: "cardioElapsed").firstMatch
        let stopped = elapsed.label
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(pause.waitForExistence(timeout: 10)); XCTAssertEqual(stopped, elapsed.label)
        pause.tap()
        expectation(for: NSPredicate(format: "label != %@", stopped), evaluatedWith: elapsed)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(app.buttons["gymStation"].exists)
        let cardioShot = XCTAttachment(screenshot: app.screenshot()); cardioShot.name = "Cardio inside the private workout space"; cardioShot.lifetime = .keepAlways; add(cardioShot)
        app.buttons["endCardioTimer"].tap()
        XCTAssertTrue(solo.waitForExistence(timeout: 15), "Ending cardio closes the solo space")
    }
}
