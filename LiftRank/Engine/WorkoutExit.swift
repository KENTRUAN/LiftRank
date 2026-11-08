import Foundation
import SwiftData

/// Explicit user decisions only. Backgrounding and switching tabs never end a workout.
@MainActor
enum WorkoutExit {
    enum Decision { case save, discard, cancel }

    /// A successful local save is required before the caller may leave the room.
    @discardableResult
    static func resolve(_ decision: Decision, workout: Workout, profile: UserProfile, context: ModelContext, now: Date = Date()) throws -> Bool {
        guard decision != .cancel else { return false }
        guard !workout.isPublished, !workout.isDeleted else { return true }
        // Preserve the draft as the rollback point before making destructive changes.
        try context.save()
        let workoutID = workout.id, healthOwner = workout.healthOwner
        do {
            if decision == .discard {
                context.delete(workout)
            } else {
                let workouts = try context.fetch(FetchDescriptor<Workout>())
                let exercises = try context.fetch(FetchDescriptor<Exercise>())
                let cardio = try context.fetch(FetchDescriptor<CardioSession>())
                let claims = try context.fetch(FetchDescriptor<QuestClaim>())
                if workout.cardioTimerStartedAt != nil, workout.activity != .strength {
                    let record = try CardioWorkoutSession.finish(workout, context: context, now: now, persist: false)
                    let allCardio = cardio.contains { $0.id == record.id } ? cardio : cardio + [record]
                    let gsr = RankAggregator.overall(muscleScores: RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)))
                    _ = DailyTrainingEngine.claimIfEarned(profile: profile, workouts: workouts, cardio: allCardio, claims: claims, gsr: gsr, context: context, today: now, save: false)
                } else {
                    workout.setStartedAt = nil; workout.setEndedAt = nil; workout.currentExerciseKey = ""; workout.restUntil = nil
                    workout.endedAt = workout.endedAt ?? now
                    _ = try WorkoutPublisher.publish(workout, profile: profile, exercises: exercises, workouts: workouts, cardio: cardio, claims: claims, context: context, persist: false)
                }
            }
            try context.save()
        } catch { context.rollback(); throw error }
        OutdoorWorkoutTracker.shared.follow(nil, foreground: false)
        CardioLiveActivityManager.shared.refresh()
        if decision == .discard {
            TrainingHealthManager.shared.discard(workoutID: workoutID, healthOwner: healthOwner)
        } else if workout.startOptionsChosen, workout.healthState != "off" {
            Task { [container = context.container] in
                defer { withExtendedLifetime(container) {} }
                await TrainingHealthManager.shared.finish(workout, context: context)
            }
        }
        return true
    }
}
