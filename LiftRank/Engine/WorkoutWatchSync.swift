import Foundation
import SwiftData

@MainActor
enum WorkoutWatchSync {
    /// Phone owns the pause timeline. Delayed or duplicate Watch taps cannot undo newer controls.
    static func applyPauseRequest(_ message: WorkoutBridgeMessage, workout: Workout, context: ModelContext, now: Date = Date()) throws -> Bool {
        guard workout.healthOwner == "watch", !workout.isPublished, workout.endedAt == nil,
              WorkoutBridgeRules.acceptsPauseRequest(message, workoutID: workout.id.uuidString, pauses: workout.cardioPauses) else { return false }
        return try CardioWorkoutSession.setPaused(message.action == "pauseRequest", workout: workout, context: context, now: now)
    }

    /// Watch Finish freezes the same local clock, even if its Health save needs a retry.
    static func applyCompletion(_ message: WorkoutBridgeMessage, workout: Workout, context: ModelContext, now: Date = Date()) throws {
        guard workout.healthOwner == "watch", message.workoutID == workout.id.uuidString,
              ["stopped", "saved"].contains(message.action), let end = message.endedAt,
              end >= workout.startedAt, end <= now.addingTimeInterval(5) else { return }
        guard workout.healthState != "saved" || message.action == "saved" else { return }
        if !workout.isPublished {
            workout.endedAt = min(workout.endedAt ?? end, end)
            // A delayed stop may precede an iPhone pause received after the Watch stopped.
            let stop = workout.endedAt ?? end
            workout.cardioPauses = WorkoutBridgeRules.pauses(workout.cardioPauses, endingAt: stop)
            if workout.hasPendingSet, workout.setEndedAt == nil { workout.setEndedAt = stop }
            workout.restUntil = nil
        }
        workout.healthState = message.action == "saved" ? "saved" : "savingWatch"
        workout.healthError = ""
        if message.action == "saved" {
            workout.healthWorkoutID = message.healthID ?? TrainingHealthManager.syncIdentifier(workout.id)
            if !workout.isPublished, workout.cardioTimerStartedAt != nil,
               let profile = try context.fetch(FetchDescriptor<UserProfile>()).first {
                try WorkoutExit.resolve(.save, workout: workout, profile: profile, context: context, now: end)
            }
        }
        try context.save()
    }
}
