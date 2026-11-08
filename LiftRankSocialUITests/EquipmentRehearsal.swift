import XCTest

final class EquipmentRehearsal: XCTestCase {
    func testSceneSelectionReleaseAndReviewUseCompatibleExercises() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en"]
        app.launchEnvironment["LIFTRANK_DEMO"] = "1"
        app.launchEnvironment["LIFTRANK_SKIP_HEALTH"] = "1"
        app.launchEnvironment["LIFTRANK_GYM"] = "live"
        app.launchEnvironment["LIFTRANK_GYM_NAME"] = "Equipment rehearsal"
        app.launch()
        if app.buttons["keepWorkoutBlank"].waitForExistence(timeout: 10) { app.buttons["keepWorkoutBlank"].tap() }
        XCTAssertTrue(app.buttons["Leave"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["gymStation"].exists)
        app.buttons["workoutStartSet"].tap()
        XCTAssertTrue(app.staticTexts["gymError"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["confirmStartSet"].exists, "Start must not silently claim a bench")

        tapEquipment("bench", in: app)
        XCTAssertTrue(app.buttons["confirmStartSet"].waitForExistence(timeout: 10))
        checkBenchChoices(in: app)
        app.buttons["Close"].tap()
        let review = app.buttons["gymReviewWorkout"]
        app.scrollViews["gymRoomScroll"].swipeUp()
        review.tap()
        XCTAssertTrue(app.buttons["collapseWorkout"].waitForExistence(timeout: 10))
        let reviewStart = app.buttons.matching(identifier: "workoutStartSet").allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(reviewStart); reviewStart?.tap()
        XCTAssertTrue(app.buttons["confirmStartSet"].waitForExistence(timeout: 10))
        checkBenchChoices(in: app)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["collapseWorkout"].waitForExistence(timeout: 10))
        app.buttons["collapseWorkout"].tap()
        let release = app.buttons["releaseEquipment"]
        for _ in 0..<3 where !release.isHittable { app.swipeUp() }
        XCTAssertTrue(release.exists); release.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Tap equipment"), evaluatedWith: app.staticTexts["gymCurrentStation"])
        waitForExpectations(timeout: 10)

        tapEquipment("rack", in: app)
        XCTAssertTrue(app.buttons["confirmStartSet"].waitForExistence(timeout: 10))
        app.buttons["gymExercise"].tap()
        XCTAssertTrue(app.buttons["Pull-Up"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Barbell Bench Press"].exists)
        app.buttons["Pull-Up"].tap()
        app.buttons["confirmStartSet"].tap()
        XCTAssertTrue(app.buttons["workoutEndSet"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["releaseEquipment"].isEnabled)
        app.buttons["workoutEndSet"].tap()
        app.buttons["Discard this set"].tap()
        app.leaveGymSavingWorkout()
    }
    private func tapEquipment(_ station: String, in app: XCUIApplication) {
        let machine = app.buttons["gymEquipment.\(station)"]
        for _ in 0..<3 where !machine.isHittable { app.swipeDown() }
        XCTAssertTrue(machine.waitForExistence(timeout: 10)); machine.tap()
    }
    private func checkBenchChoices(in app: XCUIApplication) {
        app.buttons["gymExercise"].tap()
        XCTAssertTrue(app.buttons["Barbell Bench Press"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Pull-Up"].exists)
        XCTAssertFalse(app.buttons["Back Squat"].exists)
        app.buttons["Barbell Bench Press"].tap()
    }
}
