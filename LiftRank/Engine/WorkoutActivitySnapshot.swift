import Foundation

/// One persisted workout drives the app, Lock Screen and Dynamic Island clocks.
struct WorkoutActivitySnapshot {
    let attributes: CardioActivityAttributes
    let state: CardioActivityAttributes.ContentState

    init(workout: Workout, reading: WorkoutHeartRate? = nil, now: Date = Date()) {
        attributes = CardioActivityAttributes(workoutID: workout.id.uuidString, activityName: workout.activity.name,
                                             outdoor: workout.isOutdoor, activityRaw: workout.activityRaw)
        let finished = workout.isPublished || workout.endedAt != nil
        state = CardioActivityAttributes.ContentState(
            elapsed: workout.cardioTimerStartedAt != nil ? workout.cardioElapsed(at: now) : max(0, (workout.endedAt ?? now).timeIntervalSince(workout.startedAt)),
            updatedAt: now, isPaused: workout.cardioIsPaused, isFinished: finished,
            heartRate: finished ? nil : reading?.value(for: workout.id, now: now),
            heartRateAt: reading?.workoutID == workout.id ? reading?.measuredAt : nil,
            completedSets: workout.activity == .strength ? workout.completedSets.count : nil,
            restUntil: workout.activity == .strength && !finished ? workout.restUntil : nil,
            watchConnected: !finished && workout.healthState == "recordingWatch")
    }
}
