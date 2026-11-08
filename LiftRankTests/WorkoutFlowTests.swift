import XCTest
import SwiftData
@testable import LiftRank

final class WorkoutFlowTests: XCTestCase {
    @MainActor private func fixture() throws -> (ModelContainer, UserProfile, Exercise) {
        let schema = Schema([UserProfile.self, Exercise.self, Workout.self, WorkoutExercise.self, WorkoutSet.self,
                             CardioSession.self, RewardEvent.self, QuestClaim.self, Friend.self, DailyPlan.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let profile = UserProfile(), bench = try XCTUnwrap(ExerciseSeed.all.first { $0.key == "bench_press" })
        container.mainContext.insert(profile); container.mainContext.insert(bench)
        return (container, profile, bench)
    }

    @MainActor func testLeaveSaveRetainsOnlyCompletedWorkAndRewardsOnce() throws {
        let (container, profile, bench) = try fixture(), context = container.mainContext
        let workout = try WorkoutSession.startOrResume(profile: profile, context: context)
        workout.healthState = "off"
        try WorkoutSession.applyPreset(to: workout, title: "Bench", items: [TemplateExercise(exerciseKey: bench.key, exerciseName: bench.nameEn, sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 90)], exercises: [bench], context: context)
        try WorkoutSession.log(exercise: bench, workout: workout, weight: 60, reps: 8, unit: .kg, restSeconds: 90, context: context)
        try WorkoutSession.beginSet(workout, exerciseKey: bench.key, context: context)
        XCTAssertTrue(try WorkoutExit.resolve(.save, workout: workout, profile: profile, context: context))
        XCTAssertTrue(workout.isPublished); XCTAssertFalse(workout.hasPendingSet)
        XCTAssertEqual(workout.exercises.flatMap(\.sets).count, 1)
        XCTAssertEqual(workout.completedSets.first?.weightKg, 60)
        let eggs = profile.eggs, rewards = try context.fetchCount(FetchDescriptor<RewardEvent>())
        XCTAssertTrue(try WorkoutExit.resolve(.save, workout: workout, profile: profile, context: context))
        XCTAssertEqual(profile.eggs, eggs)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RewardEvent>()), rewards)
        XCTAssertNotEqual(try WorkoutSession.startOrResume(profile: profile, context: context).id, workout.id)
    }

    @MainActor func testCancelKeepsActiveSetAndDiscardRemovesOnlyActiveWorkout() throws {
        let (container, profile, bench) = try fixture(), context = container.mainContext
        let history = Workout(title: "Previous", bodyweightKg: 70); history.isPublished = true; context.insert(history)
        let workout = try WorkoutSession.startOrResume(profile: profile, context: context)
        try WorkoutSession.log(exercise: bench, workout: workout, weight: 60, reps: 8, unit: .kg, restSeconds: 90, context: context)
        try WorkoutSession.beginSet(workout, exerciseKey: bench.key, context: context)
        XCTAssertFalse(try WorkoutExit.resolve(.cancel, workout: workout, profile: profile, context: context))
        XCTAssertTrue(workout.hasPendingSet); XCTAssertFalse(workout.isPublished)
        let eggs = profile.eggs
        XCTAssertTrue(try WorkoutExit.resolve(.discard, workout: workout, profile: profile, context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).map(\.id), [history.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RewardEvent>()), 0)
        XCTAssertEqual(profile.eggs, eggs)
    }

    @MainActor func testLeaveSavesPausedOutdoorCardioWithoutDoubleCounting() throws {
        let (container, profile, _) = try fixture(), context = container.mainContext
        let start = Date()
        let workout = try CardioWorkoutSession.start(profile: profile, activity: .running, outdoor: true, context: context, now: start)
        workout.healthState = "off"
        workout.routePoints = [.init(latitude: 40, longitude: -74, timestamp: start), .init(latitude: 40.001, longitude: -74, timestamp: start.addingTimeInterval(60))]
        try CardioWorkoutSession.setPaused(true, workout: workout, context: context, now: start.addingTimeInterval(90))
        try WorkoutExit.resolve(.save, workout: workout, profile: profile, context: context, now: start.addingTimeInterval(180))
        try WorkoutExit.resolve(.save, workout: workout, profile: profile, context: context)
        let records = try context.fetch(FetchDescriptor<CardioSession>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].durationMinutes, 1.5, accuracy: 0.0001)
        XCTAssertEqual(records[0].distanceKm, 0.111, accuracy: 0.003)
        XCTAssertTrue(workout.isPublished)
    }

    @MainActor func testDiscardCardioCreatesNoHistoryRecord() throws {
        let (container, profile, _) = try fixture(), context = container.mainContext
        let workout = try CardioWorkoutSession.start(profile: profile, activity: .cycling, outdoor: false, context: context)
        try WorkoutExit.resolve(.discard, workout: workout, profile: profile, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CardioSession>()), 0)
    }

    @MainActor func testFailedCardioSaveLeavesSessionAvailableToRetry() throws {
        let (container, profile, _) = try fixture(), context = container.mainContext
        let start = Date()
        let workout = try CardioWorkoutSession.start(profile: profile, activity: .walking, outdoor: true, context: context, now: start)
        workout.healthState = "off"
        XCTAssertThrowsError(try WorkoutExit.resolve(.save, workout: workout, profile: profile, context: context, now: start.addingTimeInterval(-1)))
        XCTAssertFalse(workout.isPublished); XCTAssertNil(workout.endedAt)
        XCTAssertEqual(workout.cardioTimerStartedAt, start)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CardioSession>()), 0)
        XCTAssertTrue(try WorkoutExit.resolve(.save, workout: workout, profile: profile, context: context, now: start.addingTimeInterval(60)))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CardioSession>()), 1)
    }

    @MainActor func testStrengthAndCardioStartHaveSeparateDestinations() {
        let app = AppState()
        app.perform(TrainingHomeMode.cardio.startAction)
        XCTAssertEqual(app.tab, 0); XCTAssertEqual(app.pending, .openCardio)
        XCTAssertTrue(app.showCardioStart); XCTAssertEqual(app.startTodayRequest, 0)
        app.prefersCardioStart = true
        app.perform(TrainingHomeMode.strength.startAction)
        XCTAssertEqual(app.tab, AppState.communityTab); XCTAssertEqual(app.communitySection, 0)
        XCTAssertEqual(app.startTodayRequest, 1); XCTAssertFalse(app.prefersCardioStart)
        XCTAssertFalse(app.showCardioStart); XCTAssertNil(app.pending)
    }

    @MainActor func testTrainerIdentityFollowsSettingsEdits() {
        let profile = UserProfile()
        profile.coachName = "  Nova  "; profile.coachIntro = "Calm running coach"; profile.coachAvatarIDs = ["hair.spiky"]
        let first = TrainerIdentity(profile: profile)
        XCTAssertEqual(first.name, "Nova"); XCTAssertEqual(first.requestContext["intro"], profile.coachIntro)
        profile.coachName = "River"; profile.coachIntro = "Strength coach"; profile.coachAvatarIDs = []
        let changed = TrainerIdentity(profile: profile)
        XCTAssertNotEqual(first, changed); XCTAssertEqual(changed.requestContext["name"], "River")
        profile.coachName = " \n "
        XCTAssertEqual(TrainerIdentity(profile: profile).name, "小段")
    }

    func testHeartRateRejectsOldSessionsStaleAndInvalidSamples() {
        let id = UUID(), now = Date()
        let reading = WorkoutHeartRate(workoutID: id, beatsPerMinute: 125, measuredAt: now)
        XCTAssertEqual(reading.value(for: id, now: now), 125)
        XCTAssertNil(reading.value(for: UUID(), now: now))
        XCTAssertNil(reading.value(for: id, now: now.addingTimeInterval(31)))
        XCTAssertNil(reading.value(for: id, now: now.addingTimeInterval(-6)))
        for value in [0, -1, Double.nan, Double.infinity, 400] {
            XCTAssertNil(WorkoutHeartRate(workoutID: id, beatsPerMinute: value, measuredAt: now).value(for: id, now: now))
        }
    }
}
