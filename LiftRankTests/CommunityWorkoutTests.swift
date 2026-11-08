import XCTest
import SwiftData
@testable import LiftRank

final class CommunityWorkoutTests: XCTestCase {
    @MainActor private func container() throws -> ModelContainer {
        let schema = Schema([UserProfile.self, Exercise.self, Workout.self, WorkoutExercise.self, WorkoutSet.self,
                             DailyPlan.self, RewardEvent.self, QuestClaim.self, CardioSession.self, Friend.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @MainActor
    func testHomeAndGymResumeOneWorkoutAndFillPlannedSets() throws {
        let container = try container(), context = container.mainContext
        let profile = UserProfile()
        let bench = try XCTUnwrap(ExerciseSeed.all.first { $0.key == "bench_press" })
        context.insert(profile); context.insert(bench)
        let plan = DailyPlan(dayKey: Date().dayKey, title: "Push day", items: [
            TemplateExercise(exerciseKey: bench.key, exerciseName: bench.name, sets: 2, repsLow: 8, repsHigh: 12, restSeconds: 120)
        ])
        context.insert(plan)
        let home = try WorkoutSession.startOrResume(profile: profile, context: context)
        let gym = try WorkoutSession.startOrResume(profile: profile, context: context)
        XCTAssertTrue(home === gym)
        XCTAssertNil(plan.workoutID, "Starting a workout must not choose a preset")
        XCTAssertTrue(home.exercises.isEmpty)
        XCTAssertFalse(home.startOptionsChosen)
        try WorkoutSession.applyPreset(to: home, title: plan.title, items: plan.items, exercises: [bench], context: context)
        XCTAssertEqual(home.title, "Push day")
        XCTAssertThrowsError(try WorkoutSession.applyPreset(to: home, title: "Duplicate", items: plan.items, exercises: [bench], context: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 1)
        let set = try WorkoutSession.log(exercise: bench, workout: gym, weight: 132.2772, reps: 8, unit: .lb, restSeconds: 90, context: context)
        XCTAssertEqual(set.weightKg, 60, accuracy: 0.001)
        XCTAssertEqual(home.completedSets.count, 1)
        XCTAssertEqual(home.exercises[0].sets.count, 2, "Use the planned slot rather than duplicate it")
        XCTAssertEqual(home.exercises[0].restSeconds, 120)
        XCTAssertNotNil(set.completedAt)
        for _ in 0..<2 { try WorkoutSession.log(exercise: bench, workout: gym, weight: 65, reps: 7, unit: .kg, restSeconds: 90, context: context) }
        XCTAssertEqual(home.exercises.count, 1)
        XCTAssertEqual(home.exercises[0].sortedSets.map(\.order), [0, 1, 2])
        XCTAssertEqual(home.completedSets.count, 3)
    }

    @MainActor
    func testGymResumesExistingManualSessionWithoutReplacingPlanOrRecords() throws {
        let container = try container(), context = container.mainContext
        let profile = UserProfile()
        let existing = Workout(title: "Custom manual workout", bodyweightKg: 75)
        existing.notes = "Keep my notes"
        let friend = Friend(code: "LR1-snapshot", name: "Offline friend", gsr: 480, muscleScoresJSON: "{}", cosmetics: [], streakDays: 5, updatedAt: Date())
        let plan = DailyPlan(dayKey: Date().dayKey, title: "New plan", items: [])
        context.insert(profile); context.insert(existing); context.insert(friend); context.insert(plan)
        try context.save()
        let resumed = try WorkoutSession.startOrResume(profile: profile, context: context)
        XCTAssertEqual(resumed.id, existing.id)
        XCTAssertEqual(resumed.notes, "Keep my notes")
        XCTAssertEqual(resumed.bodyweightKg, 75)
        XCTAssertNil(plan.workoutID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Friend>()).first?.code, "LR1-snapshot")
    }

    @MainActor
    func testCardioUnitsAndRejectedInputsDoNotCorruptSession() throws {
        let container = try container(), context = container.mainContext
        let profile = UserProfile()
        let cardio = try XCTUnwrap(ExerciseSeed.all.first { $0.key == "running" })
        let bench = try XCTUnwrap(ExerciseSeed.all.first { $0.key == "bench_press" })
        context.insert(profile); context.insert(cardio); context.insert(bench)
        let workout = try WorkoutSession.startOrResume(profile: profile, context: context)
        let effort = try WorkoutSession.log(exercise: cardio, workout: workout, weight: 5, reps: 30, unit: .lb, restSeconds: 90, context: context)
        XCTAssertEqual(effort.weightKg, 5, "Cardio distance stays in km even with pounds selected")
        XCTAssertEqual(effort.reps, 30)
        for (weight, reps) in [(Double.nan, 8), (Double.infinity, 8), (-5, 8), (50, 0), (50, -1), (50, 1001)] {
            XCTAssertThrowsError(try WorkoutSession.log(exercise: bench, workout: workout, weight: weight, reps: reps, unit: .kg, restSeconds: 90, context: context))
        }
        XCTAssertEqual(workout.exercises.count, 1)
        XCTAssertEqual(workout.completedSets.count, 1)
        workout.isPublished = true
        XCTAssertThrowsError(try WorkoutSession.log(exercise: cardio, workout: workout, weight: 2, reps: 10, unit: .kg, restSeconds: 90, context: context))
        let next = try WorkoutSession.startOrResume(profile: profile, context: context)
        XCTAssertNotEqual(next.id, workout.id)
        XCTAssertEqual(workout.completedSets.count, 1)
    }

    @MainActor
    func testGymSetUsesExistingPublishScoringAndHistory() throws {
        let container = try container(), context = container.mainContext
        let profile = UserProfile()
        let bench = try XCTUnwrap(ExerciseSeed.all.first { $0.key == "bench_press" })
        context.insert(profile); context.insert(bench)
        let workout = try WorkoutSession.startOrResume(profile: profile, context: context)
        try WorkoutSession.log(exercise: bench, workout: workout, weight: 60, reps: 8, unit: .kg, restSeconds: 90, context: context)
        let result = WorkoutPublisher.publish(workout, profile: profile, exercises: [bench], workouts: [workout], context: context)
        XCTAssertTrue(workout.isPublished)
        XCTAssertGreaterThan(result.bestScore, 0)
        XCTAssertNotNil(workout.endedAt)
        XCTAssertEqual(WorkoutPublisher.lastSets(for: bench.key, workouts: [workout], excluding: nil).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RewardEvent>()).filter { $0.kind == .workout }.count, 1)
        XCTAssertGreaterThan(result.eggs, 0, "Gym sets qualify for the existing daily training reward")
    }

    @MainActor
    func testSetLifecycleStartsTrainingEndsRestingAndSavesExactlyOnce() throws {
        let container = try container(), context = container.mainContext
        let profile = UserProfile()
        let bench = try XCTUnwrap(ExerciseSeed.all.first { $0.key == "bench_press" })
        context.insert(profile); context.insert(bench)
        let workout = try WorkoutSession.startOrResume(profile: profile, context: context)
        let start = Date(), end = start.addingTimeInterval(30)
        try WorkoutSession.beginSet(workout, exerciseKey: bench.key, context: context, now: start)
        XCTAssertEqual(workout.trainingState(at: start), "Training")
        XCTAssertEqual(workout.completedSets.count, 0)
        XCTAssertThrowsError(try WorkoutSession.beginSet(workout, exerciseKey: bench.key, context: context))
        try WorkoutSession.endSet(workout, restSeconds: 90, context: context, now: end)
        XCTAssertEqual(workout.trainingState(at: end), "Resting", "Rest begins before the input form is saved")
        XCTAssertEqual(workout.trainingState(at: end.addingTimeInterval(91)), "Ready")
        XCTAssertThrowsError(try WorkoutSession.saveEndedSet(workout, exercise: bench, weight: -1, reps: 8, unit: .kg, restSeconds: 90, context: context))
        XCTAssertTrue(workout.hasPendingSet, "A failed log must keep the finished set for correction")
        try WorkoutSession.saveEndedSet(workout, exercise: bench, weight: 60, reps: 8, unit: .kg, restSeconds: 90, context: context)
        XCTAssertEqual(workout.completedSets.count, 1)
        XCTAssertEqual(workout.completedSets.first?.completedAt, end)
        XCTAssertFalse(workout.hasPendingSet)
        XCTAssertEqual(workout.trainingState(at: end), "Resting")
        XCTAssertThrowsError(try WorkoutSession.saveEndedSet(workout, exercise: bench, weight: 60, reps: 8, unit: .kg, restSeconds: 90, context: context))
        workout.endedAt = end
        XCTAssertThrowsError(try WorkoutSession.beginSet(workout, exerciseKey: bench.key, context: context))
    }

    @MainActor
    func testPublicHighlightsUseCompletedLocalRecordsAndExplicitRoutineSelection() throws {
        let container = try container(), context = container.mainContext
        let profile = UserProfile()
        let bench = try XCTUnwrap(ExerciseSeed.all.first { $0.key == "bench_press" })
        context.insert(profile); context.insert(bench)
        let workout = try WorkoutSession.startOrResume(profile: profile, context: context)
        workout.startedAt = Date().addingTimeInterval(-1800); workout.endedAt = Date()
        try WorkoutSession.log(exercise: bench, workout: workout, weight: 60, reps: 8, unit: .kg, restSeconds: 90, context: context)
        let empty = GymProfileSnapshot.highlights(profile: profile, workouts: [workout], exercises: [bench], cardio: [])
        XCTAssertEqual(empty.workoutCount, 0)
        workout.isPublished = true; workout.publishedAt = Date(); workout.notes = "Private health note"
        let snapshot = GymProfileSnapshot.highlights(profile: profile, workouts: [workout], exercises: [bench], cardio: [])
        XCTAssertEqual(snapshot.workoutCount, 1)
        XCTAssertEqual(snapshot.memories.count, 1)
        XCTAssertEqual(snapshot.months.count, 6)
        XCTAssertEqual(snapshot.months.reduce(0) { $0 + $1.sessions }, 1)
        XCTAssertGreaterThan(snapshot.weekMuscles["chest"] ?? 0, 0)
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        for secret in ["bodyweightKg", "Private health note", "weightKg", "reps"] { XCTAssertFalse(json.contains(secret)) }
        let routine = WorkoutTemplate(name: "Bench day", items: [.init(exerciseKey: bench.key, exerciseName: bench.name, sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 90)])
        XCTAssertTrue(GymProfileSnapshot.routines([routine], exercises: [bench]).isEmpty)
        routine.isPublic = true
        XCTAssertEqual(GymProfileSnapshot.routines([routine], exercises: [bench]).first?.exercises.first?.sets, 3)
    }

    func testWorkoutBridgePreservesOneSessionIdentityAndAppleActivity() throws {
        let id = UUID()
        let message = WorkoutBridgeMessage(action: "start", workoutID: id.uuidString, activity: TrainingActivity.strength.rawValue, startedAt: Date())
        let restored = try JSONDecoder().decode(WorkoutBridgeMessage.self, from: XCTUnwrap(message.data))
        XCTAssertEqual(restored.workoutID, id.uuidString)
        XCTAssertEqual(TrainingActivity(rawValue: restored.activity!)?.healthType, .traditionalStrengthTraining)
        XCTAssertEqual(TrainingActivity.running.healthType, .running)
    }

    func testPresetEquipmentMapsToRealExerciseCatalogue() {
        let catalog = Set(ExerciseSeed.all.map(\.key))
        for station in GymLayout.stations where station != "lounge" {
            XCTAssertFalse(GymEquipment.exerciseKeys(at: station).isEmpty)
            XCTAssertTrue(Set(GymEquipment.exerciseKeys(at: station)).isSubset(of: catalog))
        }
        XCTAssertTrue(GymEquipment.exerciseKeys(at: "lounge").isEmpty)
    }

    @MainActor
    func testLegacyRewardsNavigationAndCommunityHaveDistinctRoutes() {
        let app = AppState()
        app.perform(.openTab(2))
        XCTAssertEqual(app.tab, 4)
        XCTAssertTrue(app.showRewards)
        app.perform(.openTab(AppState.communityTab))
        XCTAssertEqual(app.tab, 5)
    }
    @MainActor
    func testPublicationDetachesUnfinishedTodosBeforeDeletingModels() throws {
        let container = try container(), context = container.mainContext
        let profile = UserProfile(), bench = try XCTUnwrap(ExerciseSeed.all.first { $0.key == "bench_press" })
        context.insert(profile); context.insert(bench)
        for completedCount in [0, 1] {
            let workout = try WorkoutSession.startOrResume(profile: profile, context: context)
            try WorkoutSession.applyPreset(to: workout, title: "Planned", items: [TemplateExercise(exerciseKey: bench.key, exerciseName: bench.nameEn, sets: 2, repsLow: 8, repsHigh: 12, restSeconds: 90)], exercises: [bench], context: context)
            let entry = try XCTUnwrap(workout.exercises.first)
            if completedCount == 1 { try WorkoutSession.log(exercise: bench, workout: workout, weight: 60, reps: 8, unit: .kg, restSeconds: 90, context: context) }
            _ = WorkoutPublisher.publish(workout, profile: profile, exercises: [bench], workouts: [workout], context: context)
            XCTAssertEqual(workout.completedSets.count, completedCount)
            XCTAssertEqual(workout.exercises.count, completedCount)
            if completedCount == 1 { XCTAssertEqual(entry.sets.count, 1); XCTAssertTrue(entry.sets.allSatisfy(\.isCompleted)) }
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSet>()), 1)
    }

}
