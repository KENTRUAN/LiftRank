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
