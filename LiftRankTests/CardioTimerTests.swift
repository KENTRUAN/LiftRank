import XCTest
import SwiftData
@testable import LiftRank

final class CardioTimerTests: XCTestCase {
    @MainActor private func fixture() throws -> (ModelContainer, UserProfile) {
        let schema = Schema([UserProfile.self, Workout.self, WorkoutExercise.self, WorkoutSet.self, Exercise.self,
                             CardioSession.self, RewardEvent.self, QuestClaim.self, Friend.self, DailyPlan.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let profile = UserProfile(); container.mainContext.insert(profile)
        return (container, profile)
    }
    @MainActor func testStartImmediatelyTracksAndEndRecordsExactElapsedTimeOnce() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let start = Date()
        let workout = try CardioWorkoutSession.start(profile: profile, activity: .cycling, outdoor: false, context: context, now: start)
        XCTAssertEqual(workout.cardioTimerStartedAt, start)
        XCTAssertTrue(workout.startOptionsChosen)
        XCTAssertEqual(workout.trainingState(at: start), "Training")
        XCTAssertTrue(workout.exercises.isEmpty); XCTAssertFalse(workout.hasChecklist)
        let resume = try CardioWorkoutSession.start(profile: profile, activity: .running, outdoor: true, context: context, now: start.addingTimeInterval(30))
        XCTAssertTrue(resume === workout); XCTAssertEqual(workout.activity, .cycling)
        let end = start.addingTimeInterval(125.25)
        let saved = try CardioWorkoutSession.finish(workout, context: context, now: end)
        XCTAssertEqual(saved.durationMinutes * 60, 125.25, accuracy: 0.001)
        XCTAssertEqual(saved.type, .cycling); XCTAssertEqual(saved.sourceRaw, "timer")
        XCTAssertEqual(workout.endedAt, end); XCTAssertEqual(workout.trainingState(at: end), "Ready")
        let duplicate = try CardioWorkoutSession.finish(workout, context: context, now: end.addingTimeInterval(90))
        XCTAssertTrue(duplicate === saved)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CardioSession>()), 1)
    }
    @MainActor func testCardioCannotReplaceAnUnfinishedStrengthWorkoutOrCreateStrengthSets() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let strength = try WorkoutSession.startOrResume(profile: profile, context: context)
        XCTAssertThrowsError(try CardioWorkoutSession.start(profile: profile, activity: .running, outdoor: true, context: context))
        XCTAssertFalse(strength.isPublished)
        context.delete(strength); try context.save()
        XCTAssertThrowsError(try CardioWorkoutSession.start(profile: profile, activity: .strength, outdoor: false, context: context))
        let cardio = try CardioWorkoutSession.start(profile: profile, activity: .running, outdoor: false, context: context)
        XCTAssertThrowsError(try TrainerPlanEditor.apply(TrainerReply(reply: "", todos: [], schedule: []), workout: cardio, expectedRevision: TrainerPlanEditor.revision(cardio), exercises: [], plans: [], context: context, today: Date()))
        XCTAssertTrue(cardio.exercises.isEmpty)
    }
    @MainActor func testClockRegressionDoesNotPublishAndSubminuteCardioDoesNotEarnStrengthReward() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let start = Date()
        let workout = try CardioWorkoutSession.start(profile: profile, activity: .walking, outdoor: false, context: context, now: start)
        XCTAssertThrowsError(try CardioWorkoutSession.finish(workout, context: context, now: start.addingTimeInterval(-1)))
        XCTAssertFalse(workout.isPublished)
        let record = try CardioWorkoutSession.finish(workout, context: context, now: start.addingTimeInterval(5))
        let status = DailyTrainingEngine.status(profile: profile, workouts: [workout], cardio: [record], claims: [], gsr: 0)
        XCTAssertEqual(status.strengthWorkouts, 0); XCTAssertFalse(status.isComplete)
        XCTAssertEqual(record.durationMinutes, 5.0 / 60, accuracy: 0.0001)
    }
    @MainActor func testOutdoorDistanceAndSharedActivityCountOneCardioSession() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let start = Date()
        let workout = try CardioWorkoutSession.start(profile: profile, activity: .running, outdoor: true, context: context, now: start)
        workout.routePoints = [WorkoutRoutePoint(latitude: 40, longitude: -74, timestamp: start), WorkoutRoutePoint(latitude: 40.001, longitude: -74, timestamp: start.addingTimeInterval(60))]
        let record = try CardioWorkoutSession.finish(workout, context: context, now: start.addingTimeInterval(61))
        XCTAssertEqual(record.distanceKm, 0.111, accuracy: 0.003)
        let highlights = GymProfileSnapshot.highlights(profile: profile, workouts: [workout], exercises: [], cardio: [record])
        XCTAssertEqual(highlights.workoutCount, 1); XCTAssertEqual(highlights.memories.count, 1)
        XCTAssertEqual(highlights.months.reduce(0) { $0 + $1.sessions }, 1)
    }
    @MainActor func testEmptyGymDraftConvertsWithoutDeletingObservedModel() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let draft = try WorkoutSession.startOrResume(profile: profile, context: context)
        let oldID = draft.id
        draft.healthState = "off"; draft.hasChecklist = true
        let timed = try CardioWorkoutSession.start(profile: profile, activity: .rowing, outdoor: false, context: context, convertingEmpty: draft)
        XCTAssertTrue(timed === draft); XCTAssertFalse(draft.isDeleted)
        XCTAssertNotEqual(timed.id, oldID)
        XCTAssertFalse(timed.hasChecklist); XCTAssertEqual(timed.healthState, "notStarted")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 1)
    }

    func testOutdoorChoicesExcludeIndoorMachinesAndKeepIndoorOptions() {
        XCTAssertEqual(TrainingActivity.cardioActivities(outdoor: true), [.running, .walking, .cycling, .swimming, .hiit])
        let indoor = TrainingActivity.cardioActivities(outdoor: false)
        for machine in [TrainingActivity.elliptical, .rowing, .stairs] { XCTAssertTrue(indoor.contains(machine)) }
        XCTAssertFalse(indoor.contains(.strength))
        XCTAssertFalse(TrainingActivity.cardioActivities(outdoor: false, requiresEquipment: true).contains(.swimming))
    }

    @MainActor func testOutdoorMachineStartCannotCreateOrMutateAnEmptyDraft() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        for machine in [TrainingActivity.elliptical, .rowing, .stairs] {
            XCTAssertThrowsError(try CardioWorkoutSession.start(profile: profile, activity: machine, outdoor: true, context: context))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 0)
        let draft = try WorkoutSession.startOrResume(profile: profile, context: context)
        let id = draft.id
        XCTAssertThrowsError(try CardioWorkoutSession.start(profile: profile, activity: .elliptical, outdoor: true, context: context, convertingEmpty: draft))
        XCTAssertEqual(draft.id, id); XCTAssertEqual(draft.activity, .strength)
        XCTAssertNil(draft.cardioTimerStartedAt)
        XCTAssertNoThrow(try CardioWorkoutSession.start(profile: profile, activity: .elliptical, outdoor: false, context: context, convertingEmpty: draft))
    }

    @MainActor func testLegacyOutdoorMachineSessionCanStillResumeAndFinish() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let workout = try CardioWorkoutSession.start(profile: profile, activity: .rowing, outdoor: false, context: context)
        workout.isOutdoor = true; try context.save()
        let resumed = try CardioWorkoutSession.start(profile: profile, activity: .rowing, outdoor: true, context: context)
        XCTAssertTrue(resumed === workout)
        XCTAssertNoThrow(try CardioWorkoutSession.finish(workout, context: context))
    }

    @MainActor func testPauseResumeExcludesPausedTimeAndRejectsStaleClockChanges() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = try CardioWorkoutSession.start(profile: profile, activity: .running, outdoor: false, context: context, now: start)
        XCTAssertEqual(workout.cardioElapsed(at: start.addingTimeInterval(60)), 60)
        XCTAssertTrue(try CardioWorkoutSession.setPaused(true, workout: workout, context: context, now: start.addingTimeInterval(60)))
        XCTAssertFalse(try CardioWorkoutSession.setPaused(true, workout: workout, context: context, now: start.addingTimeInterval(90)))
        XCTAssertEqual(workout.cardioElapsed(at: start.addingTimeInterval(600)), 60)
        XCTAssertEqual(workout.trainingState(), "Resting")
        XCTAssertThrowsError(try CardioWorkoutSession.setPaused(false, workout: workout, context: context, now: start.addingTimeInterval(59)))
        XCTAssertTrue(try CardioWorkoutSession.setPaused(false, workout: workout, context: context, now: start.addingTimeInterval(180)))
        XCTAssertEqual(workout.cardioElapsed(at: start.addingTimeInterval(240)), 120)
        XCTAssertEqual(workout.trainingState(), "Training")
        let saved = try CardioWorkoutSession.finish(workout, context: context, now: start.addingTimeInterval(240))
        XCTAssertEqual(saved.durationMinutes * 60, 120)
        XCTAssertEqual(workout.duration, 120)
        let events = CardioClock.healthEvents(workout.cardioPauses)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].type, .pause); XCTAssertEqual(events[1].type, .resume)
        XCTAssertEqual(events[1].dateInterval.start.timeIntervalSince(events[0].dateInterval.start), 120)
        XCTAssertThrowsError(try CardioWorkoutSession.setPaused(true, workout: workout, context: context))
    }
    @MainActor func testEndingWhilePausedAndMultiplePausesSaveOnlyActiveTime() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = try CardioWorkoutSession.start(profile: profile, activity: .cycling, outdoor: false, context: context, now: start)
        try CardioWorkoutSession.setPaused(true, workout: workout, context: context, now: start.addingTimeInterval(10))
        try CardioWorkoutSession.setPaused(false, workout: workout, context: context, now: start.addingTimeInterval(20))
        try CardioWorkoutSession.setPaused(true, workout: workout, context: context, now: start.addingTimeInterval(35))
        let saved = try CardioWorkoutSession.finish(workout, context: context, now: start.addingTimeInterval(100))
        XCTAssertEqual(saved.durationMinutes * 60, 25)
        XCTAssertEqual(workout.duration, 25)
    }
    @MainActor func testClockPersistsAcrossStoreReopeningWhileRunningAndPaused() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cardio-\(UUID()).store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let schema = Schema([UserProfile.self, Workout.self, WorkoutExercise.self, WorkoutSet.self, Exercise.self, CardioSession.self])
        let config = ModelConfiguration(schema: schema, url: url)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let profile = UserProfile(); container.mainContext.insert(profile)
            _ = try CardioWorkoutSession.start(profile: profile, activity: .walking, outdoor: true, context: container.mainContext, now: start)
        }
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let workout = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Workout>()).first)
            XCTAssertEqual(workout.cardioElapsed(at: start.addingTimeInterval(3600)), 3600, "Suspension or relaunch must not stop time")
            try CardioWorkoutSession.setPaused(true, workout: workout, context: container.mainContext, now: start.addingTimeInterval(3600))
        }
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let workout = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Workout>()).first)
            XCTAssertTrue(workout.cardioIsPaused)
            XCTAssertEqual(workout.cardioElapsed(at: start.addingTimeInterval(7200)), 3600)
            try CardioWorkoutSession.setPaused(false, workout: workout, context: container.mainContext, now: start.addingTimeInterval(7200))
            XCTAssertEqual(workout.cardioElapsed(at: start.addingTimeInterval(7260)), 3660)
        }
    }
    @MainActor func testRouteDoesNotCountMovementWhilePausedAndLiveTimerUsesSameClock() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let start = Date()
        let workout = try CardioWorkoutSession.start(profile: profile, activity: .running, outdoor: true, context: context, now: start)
        workout.routePoints = [WorkoutRoutePoint(latitude: 40, longitude: -74, timestamp: start), WorkoutRoutePoint(latitude: 40.01, longitude: -74, timestamp: start.addingTimeInterval(100))]
        try CardioWorkoutSession.setPaused(true, workout: workout, context: context, now: start.addingTimeInterval(10))
        try CardioWorkoutSession.setPaused(false, workout: workout, context: context, now: start.addingTimeInterval(90))
        XCTAssertEqual(workout.routeDistanceMeters, 0)
        let now = start.addingTimeInterval(100)
        let state = CardioActivityAttributes.ContentState(elapsed: workout.cardioElapsed(at: now), updatedAt: now, isPaused: workout.cardioIsPaused)
        XCTAssertEqual(now.timeIntervalSince(state.timerStart), 20)
        XCTAssertEqual(CardioClock.display(3661), "1:01:01")
    }

}
