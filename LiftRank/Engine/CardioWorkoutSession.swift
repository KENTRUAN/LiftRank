import Foundation
import SwiftData

@MainActor
enum CardioWorkoutSession {
    static func start(profile: UserProfile, activity: TrainingActivity, outdoor: Bool, context: ModelContext, convertingEmpty: Workout? = nil, now: Date = Date()) throws -> Workout {
        guard activity != .strength else { throw GymFailure.message(L("Choose a cardio activity.")) }
        let active = try context.fetch(FetchDescriptor<Workout>()).first { !$0.isPublished }
        if let active {
            if active.activity != .strength, active.cardioTimerStartedAt != nil, active.endedAt == nil { return active }
            guard active === convertingEmpty, active.exercises.isEmpty, active.notes.isEmpty, active.routePoints.isEmpty, !active.hasPendingSet else {
                throw GymFailure.message(L("Finish your current workout before starting cardio."))
            }
        }
        // Keep the observed SwiftData object alive when converting the empty gym draft.
        // A fresh session ID separates cancelled Apple tracking from the new cardio session.
        let workout = active ?? Workout(title: activity.name, bodyweightKg: profile.bodyweightKg)
        if active != nil { workout.id = UUID(); workout.healthState = "notStarted"; workout.healthOwner = ""; workout.healthWorkoutID = ""; workout.healthError = "" }
        workout.title = activity.name; workout.hasChecklist = false; workout.restUntil = nil
        workout.activity = activity; workout.isOutdoor = outdoor
        workout.cardioPauses = []; workout.startedAt = now; workout.cardioTimerStartedAt = now; workout.startOptionsChosen = true
        if active == nil { context.insert(workout) }
        do { try context.save() } catch { context.rollback(); throw error }
        return workout
    }

    /// Idempotent desired-state changes also make repeated Live Activity taps safe.
    @discardableResult
    static func setPaused(_ paused: Bool, workout: Workout, context: ModelContext, now: Date = Date()) throws -> Bool {
        guard let start = workout.cardioTimerStartedAt, workout.activity != .strength, !workout.isPublished, workout.endedAt == nil else { throw GymFailure.message(L("This cardio session has ended.")) }
        guard workout.cardioIsPaused != paused else { return false }
        let previous = workout.cardioPauses
        let latest = previous.last?.endedAt ?? previous.last?.startedAt ?? start
        guard now >= latest else { throw GymFailure.message(L("The device clock changed. Please retry when it is correct.")) }
        if paused { workout.cardioPauses.append(CardioPause(startedAt: now)) }
        else { workout.cardioPauses[workout.cardioPauses.count - 1].endedAt = now }
        do { try context.save() } catch { workout.cardioPauses = previous; throw error }
        return true
    }

    @discardableResult
    static func finish(_ workout: Workout, context: ModelContext, now: Date = Date()) throws -> CardioSession {
        let id = TrainingHealthManager.syncIdentifier(workout.id)
        if let saved = try context.fetch(FetchDescriptor<CardioSession>()).first(where: { $0.externalID == id }) { return saved }
        guard workout.activity != .strength, let started = workout.cardioTimerStartedAt, !workout.isPublished else { throw GymFailure.message(L("Start the cardio timer first.")) }
        let end = workout.endedAt ?? now
        guard end >= (workout.cardioPauses.last?.endedAt ?? workout.cardioPauses.last?.startedAt ?? started) else { throw GymFailure.message(L("The device clock changed. Please retry when it is correct.")) }
        let duration = max(0.001, workout.cardioElapsed(at: end))
        let type = CardioType(rawValue: workout.activity.rawValue) ?? .other
        let record = CardioSession(date: started, type: type, durationMinutes: duration / 60,
                                   distanceKm: workout.isOutdoor ? workout.routeDistanceMeters / 1000 : 0,
                                   source: "timer", externalID: id)
        let previousEnd = workout.endedAt
        workout.endedAt = end; workout.isPublished = true; workout.publishedAt = end
        context.insert(record)
        do { try context.save() }
        catch { context.delete(record); workout.endedAt = previousEnd; workout.isPublished = false; workout.publishedAt = nil; throw error }
        return record
    }
}
