import XCTest
import SwiftData
import HealthKit
@testable import LiftRank

final class TrainerInteractionTests: XCTestCase {
    @MainActor private func fixture() throws -> (ModelContainer, UserProfile, Exercise, Workout) {
        let schema = Schema([UserProfile.self, Exercise.self, Workout.self, WorkoutExercise.self, WorkoutSet.self, DailyPlan.self, TrainerMessage.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let profile = UserProfile(), bench = try XCTUnwrap(ExerciseSeed.all.first { $0.key == "bench_press" })
        container.mainContext.insert(profile); container.mainContext.insert(bench)
        let workout = try WorkoutSession.startOrResume(profile: profile, context: container.mainContext)
        return (container, profile, bench, workout)
    }
    private func todo(_ exercise: Exercise, sets: Int = 2) -> TrainerPlanItem {
        TrainerPlanItem(exerciseKey: exercise.key, sets: sets, repsLow: 8, repsHigh: 12, restSeconds: 90)
    }
    @MainActor func testBlankChecklistAppearsOnlyAfterExplicitPreset() throws {
        let (container, _, bench, workout) = try fixture()
        XCTAssertFalse(workout.hasChecklist)
        try WorkoutSession.applyPreset(to: workout, title: "My choice", items: [TemplateExercise(exerciseKey: bench.key, exerciseName: bench.nameEn, sets: 2, repsLow: 8, repsHigh: 10, restSeconds: 90)], exercises: [bench], context: container.mainContext)
        XCTAssertTrue(workout.hasChecklist)
        XCTAssertEqual(workout.exercises.first?.sets.count, 2)
    }
    @MainActor func testTrainerCanCreateReplaceAndDeleteTodosWithoutChangingRecordedSets() throws {
        let (container, _, bench, workout) = try fixture(), context = container.mainContext
        let completed = try WorkoutSession.log(exercise: bench, workout: workout, weight: 72.5, reps: 9, unit: .kg, restSeconds: 90, context: context)
        XCTAssertFalse(workout.hasChecklist, "Free-form logging does not create a plan")
        XCTAssertTrue(TrainerPlanEditor.remainingTodos(workout).isEmpty, "Completed-only exercises must never be sent as zero-set todos")
        let recordedAt = completed.completedAt
        for count in [3, 1, 0] {
            let reply = TrainerReply(reply: "Updated", todos: count == 0 ? [] : [todo(bench, sets: count)], schedule: [])
            _ = try TrainerPlanEditor.apply(reply, workout: workout, expectedRevision: TrainerPlanEditor.revision(workout), exercises: [bench], plans: [], context: context, today: Date())
            XCTAssertEqual(workout.completedSets.count, 1)
            XCTAssertTrue(workout.completedSets.first === completed)
            XCTAssertEqual(completed.weightKg, 72.5); XCTAssertEqual(completed.reps, 9)
            XCTAssertEqual(completed.completedAt, recordedAt)
            XCTAssertEqual(workout.exercises.flatMap(\.sets).filter { !$0.isCompleted }.count, count)
            XCTAssertEqual(workout.hasChecklist, count != 0)
            XCTAssertEqual(TrainerPlanEditor.remainingTodos(workout).reduce(0) { $0 + $1.sets }, count)
        }
    }
    @MainActor func testStaleOrInvalidTrainerChangesAreAtomic() throws {
        let (container, _, bench, workout) = try fixture(), context = container.mainContext
        let revision = TrainerPlanEditor.revision(workout)
        try WorkoutSession.beginSet(workout, exerciseKey: bench.key, context: context)
        let day = TrainerScheduleDay(dayOffset: 0, title: "Today", remove: false, items: [todo(bench)])
        XCTAssertThrowsError(try TrainerPlanEditor.apply(TrainerReply(reply: "", todos: [], schedule: [day]), workout: workout, expectedRevision: revision, exercises: [bench], plans: [], context: context, today: Date()))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyPlan>()), 0)
        XCTAssertTrue(workout.hasPendingSet)
        try WorkoutSession.discardSet(workout, context: context)
        var invalid = todo(bench); invalid.exerciseKey = "invented"
        XCTAssertThrowsError(try TrainerPlanEditor.apply(TrainerReply(reply: "", todos: [todo(bench)], schedule: [TrainerScheduleDay(dayOffset: 0, title: "Bad", remove: false, items: [invalid])]), workout: workout, expectedRevision: TrainerPlanEditor.revision(workout), exercises: [bench], plans: [], context: context, today: Date()))
        XCTAssertTrue(workout.exercises.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyPlan>()), 0)
    }
    @MainActor func testRequestedWeekIncludesRestDaysAndSupportsScheduleDeletion() throws {
        let (container, _, bench, workout) = try fixture(), context = container.mainContext
        let days = (0..<7).map { TrainerScheduleDay(dayOffset: $0, title: $0 % 2 == 0 ? "Strength" : "Rest", remove: false, items: $0 % 2 == 0 ? [todo(bench)] : []) }
        _ = try TrainerPlanEditor.apply(TrainerReply(reply: "Week", todos: nil, schedule: days), workout: workout, expectedRevision: TrainerPlanEditor.revision(workout), exercises: [bench], plans: [], context: context, today: Date())
        let plans = try context.fetch(FetchDescriptor<DailyPlan>())
        XCTAssertEqual(plans.count, 7)
        XCTAssertTrue(plans.allSatisfy { $0.requestedByUser && $0.sourceRaw == "ai" })
        XCTAssertEqual(plans.filter { $0.items.isEmpty }.count, 3)
        XCTAssertFalse(workout.hasChecklist, "Planning future days does not modify the current workout")
        _ = try TrainerPlanEditor.apply(TrainerReply(reply: "Deleted", todos: nil, schedule: [TrainerScheduleDay(dayOffset: 0, title: "Remove", remove: true, items: [])]), workout: workout, expectedRevision: TrainerPlanEditor.revision(workout), exercises: [bench], plans: plans, context: context, today: Date())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyPlan>()), 6)
    }
    @MainActor func testFourWeekTrainerScheduleKeepsCurrentSessionAndRejectsDay29() throws {
        let (container, _, bench, workout) = try fixture(), context = container.mainContext
        let today = Date()
        let days = (0..<28).map { TrainerScheduleDay(dayOffset: $0, title: "Day \($0 + 1)", remove: false, items: $0 % 2 == 0 ? [todo(bench)] : []) }
        _ = try TrainerPlanEditor.apply(TrainerReply(reply: "Four weeks", todos: nil, schedule: days), workout: workout,
            expectedRevision: TrainerPlanEditor.revision(workout), exercises: [bench], plans: [], context: context, today: today)
        let saved = try context.fetch(FetchDescriptor<DailyPlan>())
        XCTAssertEqual(saved.count, 28)
        XCTAssertTrue(saved.contains { $0.dayKey == today.adding(days: 27).dayKey })
        XCTAssertTrue(workout.exercises.isEmpty)
        let invalid = TrainerScheduleDay(dayOffset: 28, title: "Too far", remove: false, items: [todo(bench)])
        XCTAssertThrowsError(try TrainerPlanEditor.apply(TrainerReply(reply: "Invalid", todos: nil, schedule: [invalid]), workout: workout,
            expectedRevision: TrainerPlanEditor.revision(workout), exercises: [bench], plans: saved, context: context, today: today))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyPlan>()), 28)
    }
    @MainActor func testOutdoorRouteAndHealthActivityPersistLocally() throws {
        let (container, _, _, workout) = try fixture()
        workout.activity = .running; workout.isOutdoor = true
        workout.routePoints = [WorkoutRoutePoint(latitude: 40, longitude: -74, timestamp: Date()), WorkoutRoutePoint(latitude: 40.001, longitude: -74, timestamp: Date().addingTimeInterval(60))]
        try container.mainContext.save()
        XCTAssertEqual(workout.healthConfiguration.activityType, .running)
        XCTAssertEqual(workout.healthConfiguration.locationType, .outdoor)
        XCTAssertEqual(workout.routeDistanceMeters, 111, accuracy: 2)
        workout.isOutdoor = false
        XCTAssertEqual(workout.healthConfiguration.locationType, .indoor)
        let loaded = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Workout>()).first)
        XCTAssertEqual(loaded.routePoints.count, 2)
    }
    @MainActor func testAnonymousRoomProfileNeverUsesCachedIdentity() throws {
        let store = GymStore()
        let profile = store.roomProfile("anon-random-identity")
        XCTAssertEqual(profile?.name, L("Anonymous lifter"))
        XCTAssertEqual(profile?.avatar.preset, "anonymous")
        XCTAssertEqual(profile?.gsr, 0)
        XCTAssertEqual(profile?.visibility, "anonymous")
        XCTAssertFalse(store.canRequestFriend("anon-random-identity"))
    }
}
