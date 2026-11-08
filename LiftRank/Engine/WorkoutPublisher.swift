import Foundation
import SwiftData

struct PublishSummary {
    var eggs: Int
    var bestScore: Int
    var overallScore: Int
    var prs: [String]
    var firstOfDay: Bool
    var streakDays: Int
}

enum WorkoutPublisher {
    static func previousBests(before workout: Workout, workouts: [Workout], exercises: [Exercise]) -> [String: Double] {
        let byKey = Dictionary(uniqueKeysWithValues: exercises.map { ($0.key, $0) })
        var best: [String: Double] = [:]
        for w in workouts where w.isPublished && w.id != workout.id {
            for we in w.exercises {
                guard let ex = byKey[we.exerciseKey], !ex.isCardio else { continue }
                for s in we.sets where s.isCompleted && s.type != .warmup {
                    let e = StrengthScoring.e1RM(set: s, exercise: ex, bodyweightKg: w.bodyweightKg)
                    best[ex.key] = max(best[ex.key] ?? 0, e)
                }
            }
        }
        return best
    }

    /// Finalises a workout: strips unfinished sets, scores it, pays the daily training reward and updates the streak.
    @MainActor
    static func publish(_ workout: Workout, profile: UserProfile, exercises: [Exercise], workouts: [Workout],
                        cardio: [CardioSession] = [], claims: [QuestClaim] = [], context: ModelContext) throws -> PublishSummary {
        let byKey = Dictionary(uniqueKeysWithValues: exercises.map { ($0.key, $0) })
        // Drop unfinished sets and empty exercises so history only holds real work.
        for we in workout.exercises {
            let unfinished = we.sets.filter { !$0.isCompleted }
            // Detach first: active SwiftUI rows can still observe these relationships during publication.
            we.sets.removeAll { !$0.isCompleted }
            for set in unfinished { context.delete(set) }
            if we.sets.isEmpty {
                workout.exercises.removeAll { $0 === we }
                context.delete(we)
            }
        }

        let old = previousBests(before: workout, workouts: workouts, exercises: exercises)
        var prs: [String] = []
        var bestScore = 0
        for we in workout.exercises {
            guard let ex = byKey[we.exerciseKey], !ex.isCardio else { continue }
            var newBest = 0.0
            for s in we.sets where s.isCompleted && s.type != .warmup {
                newBest = max(newBest, StrengthScoring.e1RM(set: s, exercise: ex, bodyweightKg: workout.bodyweightKg))
                bestScore = max(bestScore, StrengthScoring.score(set: s, exercise: ex, bodyweightKg: workout.bodyweightKg, sex: profile.sex))
            }
            if newBest > (old[ex.key] ?? 0) + 0.01, newBest > 0 { prs.append("\(ex.displayName) e1RM \(newBest.fmt(1)) kg") }
        }

        let now = Date()
        workout.isPublished = true
        workout.publishedAt = now
        workout.endedAt = workout.endedAt ?? now
        workout.strengthScore = bestScore

        let all = workouts.contains { $0.id == workout.id } ? workouts : workouts + [workout]
        let gsr = RankAggregator.overall(muscleScores: RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: all, exercises: exercises, sex: profile.sex)))
        let streak = StreakEngine.current(profile: profile, workouts: all, cardio: cardio, today: now)
        context.insert(RewardEvent(date: now, kind: .workout, xp: 0, eggs: 0, note: L("发布训练：%@", workout.title)))
        let eggs = DailyTrainingEngine.claimIfEarned(profile: profile, workouts: all, cardio: cardio, claims: claims, gsr: gsr, context: context, today: now, save: false)
        workout.xpEarned = 0
        do { try context.save() }
        catch {
            context.rollback()
            throw GymFailure.message(L("无法发布训练，请重试。"))
        }
        if workout.startOptionsChosen, workout.healthState != "off" {
            // Keep the store alive until the asynchronous Health write completes.
            Task { [container = context.container] in
                defer { withExtendedLifetime(container) {} }
                await TrainingHealthManager.shared.finish(workout, context: context)
            }
        }
        return PublishSummary(eggs: eggs, bestScore: bestScore, overallScore: gsr, prs: prs, firstOfDay: eggs > 0, streakDays: streak.currentDays)
    }

    static func dayKeyToDate(_ key: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: key)
    }

    static func lastSets(for exerciseKey: String, workouts: [Workout], excluding: Workout?) -> [WorkoutSet] {
        let candidates = workouts
            .filter { $0.isPublished && $0.id != excluding?.id }
            .sorted { ($0.publishedAt ?? $0.startedAt) > ($1.publishedAt ?? $1.startedAt) }
        for w in candidates {
            if let we = w.exercises.first(where: { $0.exerciseKey == exerciseKey }) {
                let sets = we.sortedSets.filter { $0.isCompleted }
                if !sets.isEmpty { return sets }
            }
        }
        return []
    }

    /// Builds a workout from plan items, pre-filling weights from the last time each exercise was done.
    @MainActor
    static func makeWorkout(title: String, items: [TemplateExercise], profile: UserProfile, exercises: [Exercise], workouts: [Workout], context: ModelContext, save: Bool = true) -> Workout {
        let w = Workout(title: title, bodyweightKg: profile.bodyweightKg)
        context.insert(w)
        let byKey = Dictionary(uniqueKeysWithValues: exercises.map { ($0.key, $0) })
        for (i, item) in items.enumerated() {
            guard let ex = byKey[item.exerciseKey] else { continue }
            let we = WorkoutExercise(order: i, exercise: ex, restSeconds: item.restSeconds)
            let prev = lastSets(for: ex.key, workouts: workouts, excluding: nil)
            for s in 0..<max(1, item.sets) {
                let set = WorkoutSet(order: s, weightKg: prev.indices.contains(s) ? prev[s].weightKg : (prev.last?.weightKg ?? 0), reps: item.repsLow)
                we.sets.append(set)
            }
            w.exercises.append(we)
        }
        if save { try? context.save() }
        return w
    }
}

/// Auto-publishes the training item for today from the user's plan or generator preferences.
enum DailyPlanEngine {
    static func todayKey(_ date: Date = Date()) -> String { date.dayKey }

    @MainActor
    @discardableResult
    static func ensureToday(profile: UserProfile, templates: [WorkoutTemplate], exercises: [Exercise], workouts: [Workout], plans: [DailyPlan], context: ModelContext, today: Date = Date()) -> DailyPlan? {
        let key = todayKey(today)
        if let existing = plans.first(where: { $0.dayKey == key }) { return existing }
        guard profile.autoPublishDailyPlan, !exercises.isEmpty else { return nil }
        let (title, items) = suggest(profile: profile, templates: templates, exercises: exercises, workouts: workouts, today: today)
        guard !items.isEmpty else { return nil }
        let plan = DailyPlan(dayKey: key, title: title, items: items, source: "auto")
        context.insert(plan)
        try? context.save()
        return plan
    }

    /// Rotates through the saved multi-day plan; otherwise generates a day from the stored preferences.
    static func suggest(profile: UserProfile, templates: [WorkoutTemplate], exercises: [Exercise], workouts: [Workout], today: Date = Date()) -> (String, [TemplateExercise]) {
        let planTemplates = templates.filter { !$0.planName.isEmpty }.sorted { $0.dayIndex < $1.dayIndex }
        let candidates = planTemplates.isEmpty ? templates.sorted { $0.createdAt < $1.createdAt } : planTemplates
        if !candidates.isEmpty {
            // Continue after the most recently published workout that matched a template.
            let recent = workouts.filter { $0.isPublished }.sorted { ($0.publishedAt ?? $0.startedAt) > ($1.publishedAt ?? $1.startedAt) }
            var next = 0
            for w in recent {
                if let idx = candidates.firstIndex(where: { $0.name == w.title }) { next = (idx + 1) % candidates.count; break }
            }
            let t = candidates[next]
            return (t.name, t.items)
        }
        let generated = WorkoutGenerator.generate(goal: profile.planGoal, daysPerWeek: profile.planDaysPerWeek, equipment: profile.planEquipment,
                                                  experience: profile.planExperience, weeks: 1, exercises: exercises)
        guard !generated.isEmpty else { return (L("今日训练"), []) }
        let dayNumber = Calendar.current.ordinality(of: .day, in: .era, for: today) ?? 0
        let t = generated[dayNumber % generated.count]
        return (t.name, t.items)
    }

    static func regenerate(plan: DailyPlan, profile: UserProfile, templates: [WorkoutTemplate], exercises: [Exercise], workouts: [Workout]) {
        let (title, items) = suggest(profile: profile, templates: templates, exercises: exercises, workouts: workouts)
        plan.title = title
        plan.items = items
        plan.sourceRaw = "auto"
    }
}
