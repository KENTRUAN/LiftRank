import XCTest

final class TodayTrainingRehearsal: XCTestCase {
    private func launch(_ fixture: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguage", "en"]
        app.launchEnvironment["LIFTRANK_DEMO"] = "1"
        app.launchEnvironment["LIFTRANK_SKIP_HEALTH"] = "1"
        app.launchEnvironment["LIFTRANK_TODAY_PLAN"] = fixture
        app.launch()
        XCTAssertTrue(app.buttons["openSocialGym"].waitForExistence(timeout: 15))
        return app
    }

    func testTodayOpensOnlyTrainingListAndReturningDoesNotPresentSetup() {
        let app = launch("planned")
        let today = app.buttons["todayTraining"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        let startLabel = app.buttons["openSocialGym"].label
        today.tap()
        XCTAssertTrue(app.collectionViews["todayTrainingList"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["3 × 8–12"].exists)
        XCTAssertTrue(app.staticTexts["2 × 6–8"].exists)
        XCTAssertTrue(app.staticTexts["Rest · 90s"].exists)
        XCTAssertFalse(app.textFields["trainerInput"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertTrue(today.isHittable)
        XCTAssertEqual(app.buttons["openSocialGym"].label, startLabel, "Viewing a plan must not start a session")

        // The separate trainer entry remains usable without queuing a setup sheet.
        app.buttons["openHomeTrainer"].tap()
        XCTAssertTrue(app.textFields["trainerInput"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        today.tap()
        XCTAssertTrue(app.collectionViews["todayTrainingList"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["trainerInput"].exists)
    }

    func testTodayIsHiddenWithoutRequestedExercisesForToday() {
        for fixture in ["none", "rest", "other-day", "automatic"] {
            let app = launch(fixture)
            XCTAssertFalse(app.buttons["todayTraining"].exists, fixture)
            XCTAssertFalse(app.staticTexts["Today"].exists, fixture)
            XCTAssertFalse(app.textFields["trainerInput"].exists, fixture)
            app.terminate()
        }
    }
}
