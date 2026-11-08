import XCTest
import SwiftData
@testable import LiftRank

final class WorkoutLiveActivityTests: XCTestCase {
    @MainActor private func fixture() throws -> (ModelContainer, UserProfile) {
        let schema = Schema([UserProfile.self, Exercise.self, Workout.self, WorkoutExercise.self, WorkoutSet.self,
                             CardioSession.self, RewardEvent.self, QuestClaim.self, Friend.self, DailyPlan.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let profile = UserProfile(); container.mainContext.insert(profile)
        return (container, profile)
    }

    @MainActor func testStrengthActivityUsesCompletedSetsRestAndScopedHeartRate() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let now = Date(), workout = try WorkoutSession.startOrResume(profile: profile, context: context)
        workout.startedAt = now.addingTimeInterval(-120)
        workout.startOptionsChosen = true; workout.healthOwner = "watch"; workout.healthState = "recordingWatch"
        let bench = try XCTUnwrap(ExerciseSeed.all.first { $0.key == "bench_press" }); context.insert(bench)
        try WorkoutSession.log(exercise: bench, workout: workout, weight: 50, reps: 8, unit: .kg, restSeconds: 60, context: context)
        workout.restUntil = now.addingTimeInterval(60)
        let reading = WorkoutHeartRate(workoutID: workout.id, beatsPerMinute: 123, measuredAt: now)
        let snapshot = WorkoutActivitySnapshot(workout: workout, reading: reading, now: now)
        XCTAssertTrue(snapshot.attributes.isStrength)
        XCTAssertEqual(snapshot.state.elapsed, 120)
        XCTAssertEqual(snapshot.state.completedSets, 1)
        XCTAssertEqual(snapshot.state.restUntil, workout.restUntil)
        XCTAssertEqual(snapshot.state.freshHeartRate(at: now), 123)
        XCTAssertEqual(snapshot.state.watchConnected, true)
        XCTAssertNil(snapshot.state.freshHeartRate(at: now.addingTimeInterval(31)))
        let other = WorkoutHeartRate(workoutID: UUID(), beatsPerMinute: 150, measuredAt: now)
        XCTAssertNil(WorkoutActivitySnapshot(workout: workout, reading: other, now: now).state.heartRate)
        workout.endedAt = now
        let finished = WorkoutActivitySnapshot(workout: workout, reading: reading, now: now.addingTimeInterval(90))
        XCTAssertTrue(finished.state.isFinished)
        XCTAssertEqual(finished.state.elapsed, 120)
        XCTAssertNil(finished.state.restUntil)
        XCTAssertNil(finished.state.heartRate)
        XCTAssertEqual(finished.state.watchConnected, false)
    }

    @MainActor func testCardioActivityRestoresSamePausedAndRunningClock() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let start = Date(), workout = try CardioWorkoutSession.start(profile: profile, activity: .running, outdoor: true, context: context, now: start)
        try CardioWorkoutSession.setPaused(true, workout: workout, context: context, now: start.addingTimeInterval(20))
        let paused = WorkoutActivitySnapshot(workout: workout, now: start.addingTimeInterval(100))
        XCTAssertFalse(paused.attributes.isStrength); XCTAssertTrue(paused.attributes.outdoor)
        XCTAssertTrue(paused.state.isPaused); XCTAssertEqual(paused.state.elapsed, 20)
        try CardioWorkoutSession.setPaused(false, workout: workout, context: context, now: start.addingTimeInterval(100))
        let now = start.addingTimeInterval(130), resumed = WorkoutActivitySnapshot(workout: workout, now: now)
        XCTAssertFalse(resumed.state.isPaused); XCTAssertEqual(resumed.state.elapsed, 50)
        XCTAssertEqual(now.timeIntervalSince(resumed.state.timerStart), 50)
    }

    func testExistingActivityAndBridgePayloadsRemainDecodable() throws {
        let state = try JSONDecoder().decode(CardioActivityAttributes.ContentState.self,
            from: Data(#"{"elapsed":60,"updatedAt":0,"isPaused":true,"isFinished":false}"#.utf8))
        XCTAssertEqual(state.elapsed, 60); XCTAssertTrue(state.isPaused)
        XCTAssertNil(state.heartRate); XCTAssertNil(state.completedSets)
        let attributes = try JSONDecoder().decode(CardioActivityAttributes.self,
            from: Data(#"{"workoutID":"old","activityName":"Running","outdoor":true}"#.utf8))
        XCTAssertFalse(attributes.isStrength)
        let oldMessage = try JSONDecoder().decode(WorkoutBridgeMessage.self, from: Data(#"{"action":"recording","workoutID":"old"}"#.utf8))
        XCTAssertNil(oldMessage.requestID)
    }

    @MainActor func testWatchControlsAreIdempotentAndRejectOlderPhoneState() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let start = Date(), workout = try CardioWorkoutSession.start(profile: profile, activity: .walking, outdoor: false, context: context, now: start)
        workout.healthOwner = "watch"
        let pause = WorkoutBridgeMessage(action: "pauseRequest", workoutID: workout.id.uuidString, controlVersion: 0, requestID: "pause-1")
        XCTAssertTrue(try WorkoutWatchSync.applyPauseRequest(pause, workout: workout, context: context, now: start.addingTimeInterval(10)))
        XCTAssertFalse(try WorkoutWatchSync.applyPauseRequest(pause, workout: workout, context: context, now: start.addingTimeInterval(20)))
        let resume = WorkoutBridgeMessage(action: "resumeRequest", workoutID: workout.id.uuidString, controlVersion: 1, requestID: "resume-1")
        XCTAssertTrue(try WorkoutWatchSync.applyPauseRequest(resume, workout: workout, context: context, now: start.addingTimeInterval(30)))
        XCTAssertFalse(try WorkoutWatchSync.applyPauseRequest(pause, workout: workout, context: context, now: start.addingTimeInterval(40)))
        XCTAssertFalse(workout.cardioIsPaused)
        XCTAssertEqual(workout.cardioElapsed(at: start.addingTimeInterval(60)), 40)
        let latest = WorkoutBridgeMessage(action: "state", workoutID: workout.id.uuidString, controlVersion: 2)
        XCTAssertFalse(WorkoutBridgeRules.acceptsSnapshot(pause, current: latest))
        XCTAssertTrue(WorkoutBridgeRules.acceptsSnapshot(latest, current: latest))
    }

    @MainActor func testWatchControlsRejectWrongOwnerSessionAndFinishedWorkout() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let workout = try CardioWorkoutSession.start(profile: profile, activity: .cycling, outdoor: false, context: context)
        var pause = WorkoutBridgeMessage(action: "pauseRequest", workoutID: workout.id.uuidString, controlVersion: 0, requestID: "pause")
        workout.healthOwner = "phone"
        XCTAssertFalse(try WorkoutWatchSync.applyPauseRequest(pause, workout: workout, context: context))
        workout.healthOwner = "watch"; pause.workoutID = UUID().uuidString
        XCTAssertFalse(try WorkoutWatchSync.applyPauseRequest(pause, workout: workout, context: context))
        pause.workoutID = workout.id.uuidString; workout.endedAt = Date()
        XCTAssertFalse(try WorkoutWatchSync.applyPauseRequest(pause, workout: workout, context: context))
        XCTAssertFalse(workout.cardioIsPaused)
    }

    @MainActor func testWatchFinishFreezesClockThenSavesCardioExactlyOnce() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let start = Date(), workout = try CardioWorkoutSession.start(profile: profile, activity: .walking, outdoor: true, context: context, now: start)
        workout.healthOwner = "watch"; workout.healthState = "recordingWatch"
        try CardioWorkoutSession.setPaused(true, workout: workout, context: context, now: start.addingTimeInterval(20))
        try CardioWorkoutSession.setPaused(false, workout: workout, context: context, now: start.addingTimeInterval(40))
        var message = WorkoutBridgeMessage(action: "stopped", workoutID: workout.id.uuidString, endedAt: start.addingTimeInterval(80))
        let now = start.addingTimeInterval(100)
        try WorkoutWatchSync.applyCompletion(message, workout: workout, context: context, now: now)
        XCTAssertFalse(workout.isPublished); XCTAssertEqual(workout.healthState, "savingWatch")
        XCTAssertEqual(WorkoutActivitySnapshot(workout: workout, now: now).state.elapsed, 60)
        message.action = "saved"; message.healthID = "health-workout"
        try WorkoutWatchSync.applyCompletion(message, workout: workout, context: context, now: now)
        let eggs = profile.eggs
        try WorkoutWatchSync.applyCompletion(message, workout: workout, context: context, now: now)
        message.action = "stopped"
        try WorkoutWatchSync.applyCompletion(message, workout: workout, context: context, now: now)
        let records = try context.fetch(FetchDescriptor<CardioSession>())
        XCTAssertEqual(records.count, 1); XCTAssertEqual(records.first?.durationMinutes, 1)
        XCTAssertTrue(workout.isPublished); XCTAssertEqual(workout.healthState, "saved")
        XCTAssertEqual(workout.healthWorkoutID, "health-workout"); XCTAssertEqual(profile.eggs, eggs)
    }

    @MainActor func testDelayedWatchStopClipsPausesAfterEndAndRejectsInvalidEnd() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let start = Date(), workout = try CardioWorkoutSession.start(profile: profile, activity: .running, outdoor: false, context: context, now: start)
        workout.healthOwner = "watch"; workout.healthState = "recordingWatch"
        try CardioWorkoutSession.setPaused(true, workout: workout, context: context, now: start.addingTimeInterval(20))
        try CardioWorkoutSession.setPaused(false, workout: workout, context: context, now: start.addingTimeInterval(80))
        try CardioWorkoutSession.setPaused(true, workout: workout, context: context, now: start.addingTimeInterval(90))
        var message = WorkoutBridgeMessage(action: "saved", workoutID: workout.id.uuidString, endedAt: start.addingTimeInterval(-1))
        let now = start.addingTimeInterval(100)
        try WorkoutWatchSync.applyCompletion(message, workout: workout, context: context, now: now)
        XCTAssertNil(workout.endedAt)
        message.endedAt = now.addingTimeInterval(60)
        try WorkoutWatchSync.applyCompletion(message, workout: workout, context: context, now: now)
        XCTAssertNil(workout.endedAt)
        message.endedAt = start.addingTimeInterval(50)
        try WorkoutWatchSync.applyCompletion(message, workout: workout, context: context, now: now)
        XCTAssertTrue(workout.isPublished)
        XCTAssertEqual(workout.cardioPauses.count, 1); XCTAssertNil(workout.cardioPauses.first?.endedAt)
        XCTAssertEqual(workout.duration, 20)
    }

    @MainActor func testWatchStrengthFinishKeepsPendingSetForPhoneReview() throws {
        let (container, profile) = try fixture(), context = container.mainContext
        let start = Date(), workout = try WorkoutSession.startOrResume(profile: profile, context: context)
        workout.startedAt = start; workout.startOptionsChosen = true
        workout.healthOwner = "watch"; workout.healthState = "recordingWatch"
        try WorkoutSession.beginSet(workout, exerciseKey: "bench_press", context: context, now: start)
        let end = start.addingTimeInterval(60)
        let message = WorkoutBridgeMessage(action: "saved", workoutID: workout.id.uuidString, endedAt: end, healthID: "strength-health")
        try WorkoutWatchSync.applyCompletion(message, workout: workout, context: context, now: end)
        XCTAssertFalse(workout.isPublished); XCTAssertTrue(workout.hasPendingSet)
        XCTAssertEqual(workout.setEndedAt, end); XCTAssertEqual(workout.healthState, "saved")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CardioSession>()), 0)
        XCTAssertThrowsError(try WorkoutSession.beginSet(workout, exerciseKey: "squat", context: context))
    }
}
