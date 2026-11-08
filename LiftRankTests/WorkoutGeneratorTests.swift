import XCTest
@testable import LiftRank

final class WorkoutGeneratorTests: XCTestCase {
    func testBodyweightFourDayBeginnerReturnsAvailableLowerBodyExercises() {
        let plan = WorkoutGenerator.generate(
            goal: .hypertrophy, daysPerWeek: 4, equipment: .bodyweight,
            experience: .beginner, weeks: 4, exercises: ExerciseSeed.all
        )

        XCTAssertEqual(plan.count, 4)
        let lowerBody = plan.first { $0.dayIndex == 1 }
        XCTAssertEqual(lowerBody?.items.map(\.exerciseKey), [
            "bodyweight_squat", "nordic_curl", "glute_bridge"
        ])
    }

    func testEmptyCatalogReturnsEmptyTemplates() {
        let plan = WorkoutGenerator.generate(
            goal: .strength, daysPerWeek: 3, equipment: .fullGym,
            experience: .advanced, weeks: 1, exercises: []
        )

        XCTAssertEqual(plan.count, 3)
        XCTAssertTrue(plan.allSatisfy { $0.items.isEmpty })
    }

    func testUnrelatedExercisesDoNotFillASplit() {
        let unrelated = Exercise(
            key: "forearms_only", name: "Forearms", nameEn: "Forearms",
            muscle: .forearms, equipment: .bodyweight
        )
        let plan = WorkoutGenerator.generate(
            goal: .general, daysPerWeek: 1, equipment: .bodyweight,
            experience: .beginner, weeks: 1, exercises: [unrelated]
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertTrue(plan.allSatisfy { $0.items.isEmpty })
    }

    func testGenerationPreservesSplitOrderAndExercisePreferences() {
        let plan = WorkoutGenerator.generate(
            goal: .strength, daysPerWeek: 4, equipment: .fullGym,
            experience: .beginner, weeks: 4, exercises: ExerciseSeed.all
        )

        XCTAssertEqual(plan.first?.items.map(\.exerciseKey), [
            "bench_press", "deadlift", "ohp", "close_grip_bench"
        ])
    }

    func testAllSupportedConfigurationsRespectAvailableExercisesAndGoal() {
        let exercises = ExerciseSeed.all
        for goal in WorkoutGoal.allCases {
            for days in 1...6 {
                let splits = WorkoutGenerator.splits(daysPerWeek: days)
                for equipment in EquipmentAccess.allCases {
                    for experience in ExperienceLevel.allCases {
                        let configuration = "\(goal.rawValue), \(days) days, \(equipment.rawValue), \(experience.rawValue)"
                        let plan = WorkoutGenerator.generate(
                            goal: goal, daysPerWeek: days, equipment: equipment,
                            experience: experience, weeks: 4, exercises: exercises
                        )

                        XCTAssertEqual(plan.count, days, configuration)
                        for (index, template) in plan.enumerated() {
                            let eligibleKeys = Set(exercises.filter {
                                !$0.isCardio && equipment.allows($0.equipment)
                                    && splits[index].groups.contains($0.muscleGroup)
                            }.map(\.key))
                            let chosenKeys = template.items.map(\.exerciseKey)
                            XCTAssertEqual(chosenKeys.count, min(experience.exercisesPerDay, eligibleKeys.count), configuration)
                            XCTAssertEqual(Set(chosenKeys).count, chosenKeys.count, configuration)
                            XCTAssertTrue(Set(chosenKeys).isSubset(of: eligibleKeys), configuration)
                            for item in template.items {
                                XCTAssertEqual(item.sets, goal.scheme.sets, configuration)
                                XCTAssertEqual(item.repsLow, goal.scheme.low, configuration)
                                XCTAssertEqual(item.repsHigh, goal.scheme.high, configuration)
                                XCTAssertEqual(item.restSeconds, goal.scheme.rest, configuration)
                            }
                        }
                    }
                }
            }
        }
    }
}

final class AIProgramTests: XCTestCase {
    func testNutritionGuidancePersistsWithoutCreatingWorkouts() throws {
        let plan = try AIProgram.validated(nutritionProposal(), exercises: ExerciseSeed.all, equipment: .bodyweight, scope: .nutrition)
        let restored = try XCTUnwrap(AIProgram.load(plan.encoded()))
        XCTAssertEqual(restored.scope, .nutrition)
        XCTAssertEqual(restored.weeks.count, 4)
        XCTAssertTrue(restored.weeks.allSatisfy { $0.strength.isEmpty && $0.cardio.isEmpty && $0.nutrition != nil })
        XCTAssertNotEqual(AIProgram.nutritionKey, AIProgram.combinedKey, "Generating nutrition must not replace stored workout programs")
    }

    func testNutritionResponseRejectsWorkoutChangesAndMissingWeeks() {
        var value = nutritionProposal()
        var weeks = value["weeks"] as! [[String: Any]]
        weeks[0]["cardio"] = [["day": 1, "type": "walking", "minutes": 20, "effort": "Easy"]]
        value["weeks"] = weeks
        XCTAssertThrowsError(try AIProgram.validated(value, exercises: ExerciseSeed.all, equipment: .bodyweight, scope: .nutrition))
        weeks[0]["cardio"] = []
        weeks[0]["strength"] = [["day": 1, "title": "Strength", "items": [["key": "pushup", "sets": 2, "reps": 10]]]]
        value["weeks"] = weeks
        XCTAssertThrowsError(try AIProgram.validated(value, exercises: ExerciseSeed.all, equipment: .bodyweight, scope: .nutrition))
        value["weeks"] = Array(weeks.dropFirst())
        XCTAssertThrowsError(try AIProgram.validated(value, exercises: ExerciseSeed.all, equipment: .bodyweight, scope: .nutrition))
        XCTAssertThrowsError(try AIProgram.validated(combinedProposal(), exercises: ExerciseSeed.all, equipment: .bodyweight, scope: .nutrition))
    }

    private func nutritionProposal() -> [String: Any] {
        ["title": "Nutrition", "scope": "nutrition", "weeks": (1...4).map { week -> [String: Any] in
            ["week": week, "strength": [], "cardio": [], "nutrition": ["focus": "Log complete meals", "meals": ["Oats and yogurt"]]]
        }]
    }

    func testCombinedPlanPersistsAllThreePartsAndResolvesExercises() throws {
        let plan = try AIProgram.validated(combinedProposal(), exercises: ExerciseSeed.all, equipment: .bodyweight)
        let restored = try XCTUnwrap(AIProgram.load(plan.encoded()))
        XCTAssertEqual(restored.weeks.map(\.week), [1, 2, 3, 4])
        let first = try XCTUnwrap(restored.weeks.first)
        XCTAssertEqual(first.strength.first?.resolved(using: ExerciseSeed.all).first?.exerciseKey, "pushup")
        XCTAssertEqual(first.cardio.first?.type, .walking)
        XCTAssertEqual(first.nutrition?.meals, ["早餐：燕麦和酸奶"])
    }

    func testCombinedPlanRejectsMissingNutritionAndUnavailableEquipment() {
        XCTAssertThrowsError(try AIProgram.validated(combinedProposal(includeNutrition: false),
                                                     exercises: ExerciseSeed.all, equipment: .bodyweight))
        XCTAssertThrowsError(try AIProgram.validated(combinedProposal(exercise: "bench_press"),
                                                     exercises: ExerciseSeed.all, equipment: .bodyweight))
    }

    func testChangingWeekOneCardioKeepsStartDateAndOtherSections() throws {
        let original = try AIProgram.validated(combinedProposal(), exercises: ExerciseSeed.all, equipment: .bodyweight)
        let patch: [String: Any] = [
            "scope": "combined",
            "weeks": [["week": 1, "cardio": [["day": 2, "type": "walking", "minutes": 25, "effort": "轻松"]]]]
        ]
        let edited = try AIProgram.applying(patch, to: original, exercises: ExerciseSeed.all, equipment: .bodyweight)
        XCTAssertEqual(edited.startDate, original.startDate)
        XCTAssertEqual(edited.weeks.map { $0.cardio.first?.minutes }, [25, 20, 20, 20])
        XCTAssertEqual(edited.weeks.first?.strength.first?.items.first?.key, "pushup")
        XCTAssertEqual(edited.weeks.first?.nutrition?.meals, original.weeks.first?.nutrition?.meals)
    }

    private func combinedProposal(exercise: String = "pushup", includeNutrition: Bool = true) -> [String: Any] {
        let weeks: [[String: Any]] = (1...4).map { number in
            [
                "week": number,
                "strength": [["day": 1, "title": "力量", "items": [["key": exercise, "sets": 2, "reps": 10]]]],
                "cardio": [["day": 2, "type": "walking", "minutes": 20, "effort": "轻松"]],
                "nutrition": includeNutrition ? ["focus": "记录完整餐食", "meals": ["早餐：燕麦和酸奶"]] as Any : NSNull()
            ]
        }
        return ["title": "四周综合方案", "scope": "combined", "weeks": weeks]
    }
}
