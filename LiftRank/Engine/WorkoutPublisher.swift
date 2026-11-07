import Foundation
import SwiftData

struct PublishSummary {
    var xp: Int
    var eggs: Int
    var bestScore: Int
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

    static func publish(_ workout: Workout, profile: UserProfile, exercises: [Exercise], workouts: [Workout], context: ModelContext) -> PublishSummary {
        let byKey = Dictionary(uniqueKeysWithValues: exercises.map { ($0.key, $0) })
        // Drop unfinished sets and empty exercises so history only holds real work.
        for we in workout.exercises {
            for s in we.sets where !s.isCompleted { context.delete(s) }
        }
        for we in workout.exercises where we.sets.filter({ $0.isCompleted }).isEmpty { context.delete(we) }

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
            if newBest > (old[ex.key] ?? 0) + 0.01, newBest > 0 { prs.append("\(ex.name) e1RM \(newBest.fmt(1)) kg") }
        }

        let now = Date()
        let firstOfDay = !workouts.contains { $0.isPublished && $0.id != workout.id && ($0.publishedAt ?? $0.startedAt).dayKey == now.dayKey }
        workout.isPublished = true
        workout.publishedAt = now
        workout.endedAt = workout.endedAt ?? now
        workout.strengthScore = bestScore

        let postDays = Set(workouts.filter { $0.isPublished }.map { ($0.publishedAt ?? $0.startedAt).startOfDay } + [now.startOfDay])
        let bridge = Set(profile.streakBridgeDays.compactMap { dayKeyToDate($0) })
        let streak = StreakEngine.compute(postDays: postDays, bridgeDays: bridge, today: now)

        var xp = XPEngine.workoutXP(sets: workout.completedSets.count)
        var eggs = 0
        context.insert(RewardEvent(date: now, kind: .workout, xp: xp, eggs: 0, note: "发布训练：\(workout.title)"))
        if firstOfDay {
            xp += XPEngine.firstOfDayXP
            eggs = XPEngine.firstOfDayEggs(streakDays: streak.currentDays)
            context.insert(RewardEvent(date: now, kind: .firstOfDay, xp: XPEngine.firstOfDayXP, eggs: eggs, note: "今日首次发布训练（XP Shake）"))
        }
        workout.xpEarned = xp
        profile.totalXP += xp
        profile.eggs += eggs
        try? context.save()
        return PublishSummary(xp: xp, eggs: eggs, bestScore: bestScore, prs: prs, firstOfDay: firstOfDay, streakDays: streak.currentDays)
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
}
