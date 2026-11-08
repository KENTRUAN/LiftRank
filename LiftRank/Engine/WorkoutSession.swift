import Foundation
import SwiftData

/// Home and the visual gym share one local, unpublished workout.
@MainActor
enum WorkoutSession {
    static func startOrResume(profile: UserProfile, context: ModelContext, activity: TrainingActivity = .strength, outdoor: Bool = false) throws -> Workout {
        let workouts = try context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\Workout.startedAt, order: .reverse)]))
        if let active = workouts.first(where: { !$0.isPublished }) {
            if !active.exercises.isEmpty { active.startOptionsChosen = true }
            return active
        }
        let workout = Workout(title: "Workout", bodyweightKg: profile.bodyweightKg)
        workout.activity = activity; workout.isOutdoor = outdoor
        context.insert(workout)
        do { try context.save(); return workout }
        catch { context.delete(workout); throw error }
    }

    static func applyPreset(to workout: Workout, title: String, items: [TemplateExercise], exercises: [Exercise], context: ModelContext,
                            plan: DailyPlan? = nil) throws {
        guard !workout.isPublished, workout.endedAt == nil, workout.exercises.isEmpty, !workout.hasPendingSet else {
            throw GymFailure.message(L("A preset can only be added to an empty workout. Your recorded work has been kept."))
        }
        let resolved = items.compactMap { item in exercises.first { $0.key == item.exerciseKey } }
        guard !items.isEmpty, resolved.count == items.count else {
            throw GymFailure.message(L("Some exercises in this saved plan are unavailable. Your workout is unchanged."))
        }
        let history = try context.fetch(FetchDescriptor<Workout>())
        let previous = (workout.title, workout.hasChecklist, workout.startOptionsChosen, plan?.workoutID)
        for (index, pair) in zip(items, resolved).enumerated() {
            let (item, exercise) = pair
            let entry = WorkoutExercise(order: index, exercise: exercise, restSeconds: item.restSeconds)
            let previous = WorkoutPublisher.lastSets(for: exercise.key, workouts: history, excluding: workout)
            for order in 0..<max(1, item.sets) {
                entry.sets.append(WorkoutSet(order: order, weightKg: previous.indices.contains(order) ? previous[order].weightKg : previous.last?.weightKg ?? 0, reps: item.repsLow))
            }
            workout.exercises.append(entry)
        }
        workout.title = title
        workout.hasChecklist = true
        workout.startOptionsChosen = true
        plan?.workoutID = workout.id
        do { try context.save() }
        catch {
            for entry in workout.exercises { context.delete(entry) }
            workout.exercises = []
            (workout.title, workout.hasChecklist, workout.startOptionsChosen) = (previous.0, previous.1, previous.2)
            plan?.workoutID = previous.3
            throw error
        }
    }

    static func beginSet(_ workout: Workout, exerciseKey: String, context: ModelContext, now: Date = Date()) throws {
        guard !workout.isPublished, workout.endedAt == nil, !workout.hasPendingSet, !exerciseKey.isEmpty else { throw GymFailure.message(L("Finish or discard the current set first.")) }
        workout.currentExerciseKey = exerciseKey; workout.setStartedAt = now; workout.setEndedAt = nil; workout.restUntil = nil
        try context.save()
    }
    static func endSet(_ workout: Workout, restSeconds: Int, context: ModelContext, now: Date = Date()) throws {
        guard !workout.isPublished, workout.setStartedAt != nil, workout.setEndedAt == nil else { return }
        workout.setEndedAt = now; workout.restUntil = now.addingTimeInterval(Double(max(0, restSeconds)))
        try context.save()
    }
    static func discardSet(_ workout: Workout, context: ModelContext) throws {
        workout.setStartedAt = nil; workout.setEndedAt = nil; workout.currentExerciseKey = ""; workout.restUntil = nil
        try context.save()
    }

    static func saveEndedSet(_ workout: Workout, exercise: Exercise, weight: Double, reps: Int, unit: WeightUnit, restSeconds: Int, context: ModelContext) throws {
        guard workout.hasPendingSet, let ended = workout.setEndedAt, workout.currentExerciseKey == exercise.key else {
            throw GymFailure.message(L("End your set before saving it."))
        }
        let started = workout.setStartedAt
        // Clear pending state in the same save as the completed set, preventing double saves.
        workout.setStartedAt = nil; workout.setEndedAt = nil; workout.currentExerciseKey = ""
        do { try log(exercise: exercise, workout: workout, weight: weight, reps: reps, unit: unit, restSeconds: restSeconds, context: context, completedAt: ended) }
        catch { workout.setStartedAt = started; workout.setEndedAt = ended; workout.currentExerciseKey = exercise.key; throw error }
    }

    /// Confirm one real set. Fill the next planned slot before adding an extra set.
    @discardableResult
    static func log(exercise: Exercise, workout: Workout, weight: Double, reps: Int, unit: WeightUnit,
                    restSeconds: Int, context: ModelContext, completedAt: Date = Date()) throws -> WorkoutSet {
        guard !workout.isPublished else { throw GymFailure.message(L("This workout is finished. Start a new session first.")) }
        let storedWeight = exercise.isCardio ? weight : unit.toKg(weight)
        guard weight.isFinite, storedWeight.isFinite, storedWeight >= 0, storedWeight <= (exercise.isCardio ? 1000 : 1500),
              reps > 0, reps <= (exercise.isCardio ? 1440 : 1000) else {
            throw GymFailure.message(L("Enter a valid nonnegative weight or distance, and a positive number of reps or minutes."))
        }
        let existingExercise = workout.exercises.first { $0.exerciseKey == exercise.key }
        let entry = existingExercise ?? WorkoutExercise(order: (workout.exercises.map(\.order).max() ?? -1) + 1, exercise: exercise, restSeconds: restSeconds)
        if existingExercise == nil { workout.exercises.append(entry) }
        let planned = entry.sortedSets.first { !$0.isCompleted }
        let set = planned ?? WorkoutSet(order: (entry.sets.map(\.order).max() ?? -1) + 1)
        if planned == nil { entry.sets.append(set) }
        let oldWeight = set.weightKg, oldReps = set.reps, oldDate = set.completedAt
        set.weightKg = storedWeight; set.reps = reps; set.isCompleted = true; set.completedAt = completedAt
        do { try context.save(); return set }
        catch {
            set.weightKg = oldWeight; set.reps = oldReps; set.isCompleted = false; set.completedAt = oldDate
            if planned == nil { entry.sets.removeAll { $0 === set }; context.delete(set) }
            if existingExercise == nil { workout.exercises.removeAll { $0 === entry }; context.delete(entry) }
            throw error
        }
    }
}

enum GymEquipment {
    static func exerciseKeys(at station: String) -> [String] {
        switch station {
        case "bench": ["bench_press", "incline_bench", "db_bench", "incline_db_bench"]
        case "rack": ["squat", "front_squat", "ohp", "pullup"]
        case "platform": ["deadlift", "rdl", "barbell_row", "clean_and_press"]
        case "cardio": ["running", "cycling", "rowing", "walking", "stair_climb"]
        default: []
        }
    }
    static func title(_ station: String) -> String {
        switch station { case "rack": L("Squat rack"); case "platform": L("Lifting platform"); case "cardio": L("Cardio zone"); case "bench": L("Bench"); default: L("Social lounge") }
    }
}
