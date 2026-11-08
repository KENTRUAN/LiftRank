import Foundation
import SwiftData

struct TrainerPlanItem: Codable {
    var exerciseKey: String
    var sets: Int
    var repsLow: Int
    var repsHigh: Int
    var restSeconds: Int
}
struct TrainerScheduleDay: Codable {
    var dayOffset: Int
    var title: String
    var remove: Bool
    var items: [TrainerPlanItem]
}
struct TrainerReply: Codable {
    var reply: String
    var todos: [TrainerPlanItem]?
    var schedule: [TrainerScheduleDay]
}

@MainActor
enum TrainerPlanEditor {
    static func remainingTodos(_ workout: Workout) -> [TrainerPlanItem] {
        workout.sortedExercises.compactMap { entry in
            let remaining = entry.sortedSets.filter { !$0.isCompleted }
            guard let next = remaining.first else { return nil }
            return TrainerPlanItem(exerciseKey: entry.exerciseKey, sets: remaining.count,
                repsLow: max(1, next.reps), repsHigh: max(1, next.reps), restSeconds: entry.restSeconds)
        }
    }
    static func revision(_ workout: Workout?) -> String {
        guard let workout else { return "none" }
        return "\(workout.id)|\(workout.isPublished)|\(workout.setStartedAt?.timeIntervalSince1970 ?? 0)|" + workout.sortedExercises.map { "\($0.exerciseKey):" + $0.sortedSets.map { "\($0.order):\($0.isCompleted):\($0.reps):\($0.weightKg)" }.joined(separator: ",") }.joined(separator: "|")
    }
    static func validate(_ items: [TrainerPlanItem], exercises: [Exercise]) throws {
        let catalog = Set(exercises.map(\.key))
        guard items.count <= 20, Set(items.map(\.exerciseKey)).count == items.count,
              items.allSatisfy({ catalog.contains($0.exerciseKey) && (1...10).contains($0.sets) && (1...1440).contains($0.repsLow) && ($0.repsLow...1440).contains($0.repsHigh) && (0...600).contains($0.restSeconds) }) else {
            throw GymFailure.message(L("The trainer returned an invalid plan. Nothing was changed."))
        }
    }
    static func replaceTodos(_ items: [TrainerPlanItem], workout: Workout, exercises: [Exercise], context: ModelContext) throws {
        try validate(items, exercises: exercises)
        guard workout.activity == .strength, !workout.isPublished, workout.endedAt == nil, !workout.hasPendingSet else { throw GymFailure.message(L("Finish the current set before editing your remaining todos.")) }
        for entry in workout.exercises {
            for set in entry.sets.filter({ !$0.isCompleted }) { entry.sets.removeAll { $0 === set }; context.delete(set) }
            if entry.sets.isEmpty { workout.exercises.removeAll { $0 === entry }; context.delete(entry) }
        }
        for item in items {
            guard let exercise = exercises.first(where: { $0.key == item.exerciseKey }) else { continue }
            let entry = workout.exercises.first { $0.exerciseKey == item.exerciseKey } ?? WorkoutExercise(order: workout.exercises.count, exercise: exercise, restSeconds: item.restSeconds)
            if !workout.exercises.contains(where: { $0 === entry }) { workout.exercises.append(entry) }
            entry.restSeconds = item.restSeconds
            let next = (entry.sets.map(\.order).max() ?? -1) + 1
            for index in 0..<item.sets { entry.sets.append(WorkoutSet(order: next + index, weightKg: entry.sortedSets.last?.weightKg ?? 0, reps: item.repsLow)) }
        }
        workout.hasChecklist = !items.isEmpty
    }
    static func apply(_ reply: TrainerReply, workout: Workout?, expectedRevision: String, exercises: [Exercise], plans: [DailyPlan], context: ModelContext, today: Date) throws -> String {
        if let todos = reply.todos {
            try validate(todos, exercises: exercises)
            guard let workout, workout.activity == .strength, revision(workout) == expectedRevision, !workout.hasPendingSet, !workout.isPublished, workout.endedAt == nil else {
                throw GymFailure.message(L("Your workout changed while the trainer was thinking. Ask again to update its remaining todos."))
            }
        }
        guard reply.schedule.count <= 28, Set(reply.schedule.map(\.dayOffset)).count == reply.schedule.count else { throw GymFailure.message(L("Invalid schedule. Nothing was changed.")) }
        for day in reply.schedule {
            guard (0...27).contains(day.dayOffset), !day.title.isEmpty else { throw GymFailure.message(L("Invalid schedule date.")) }
            try validate(day.items, exercises: exercises)
        }
        if let todos = reply.todos, let workout { try replaceTodos(todos, workout: workout, exercises: exercises, context: context) }
        for day in reply.schedule {
            let key = today.adding(days: day.dayOffset).dayKey
            let existing = plans.first { $0.dayKey == key }
            if day.remove { if let existing { context.delete(existing) }; continue }
            let items = day.items.compactMap { item -> TemplateExercise? in
                guard let exercise = exercises.first(where: { $0.key == item.exerciseKey }) else { return nil }
                return TemplateExercise(exerciseKey: item.exerciseKey, exerciseName: exercise.nameEn, sets: item.sets, repsLow: item.repsLow, repsHigh: item.repsHigh, restSeconds: item.restSeconds)
            }
            let plan = existing ?? DailyPlan(dayKey: key, title: day.title, items: [], source: "ai")
            if existing == nil { context.insert(plan) }
            plan.title = day.title; plan.items = items; plan.sourceRaw = "ai"; plan.requestedByUser = true
        }
        do { try context.save() }
        catch { context.rollback(); throw GymFailure.message(L("Your changes could not be saved. The previous workout and schedule were restored.")) }
        var notes: [String] = []
        if reply.todos != nil { notes.append(L("Remaining workout todos updated. Recorded sets are locked.")) }
        if !reply.schedule.isEmpty { notes.append(L("Schedule updated for %lld day(s).", reply.schedule.count)) }
        return notes.joined(separator: "\n")
    }
}
