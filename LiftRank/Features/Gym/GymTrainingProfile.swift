import Foundation
import SwiftData

struct GymActivityMemory: Codable, Identifiable, Equatable {
    var id: String
    var date: Double
    var title: String
    var minutes: Int
    var sets: Int
    var score: Int
}
struct GymActivityMonth: Codable, Identifiable, Equatable {
    var month: Double
    var sessions: Int
    var minutes: Int
    var id: Double { month }
}
struct GymRoutineExercise: Codable, Equatable {
    var name: String
    var sets: Int
    var repsLow: Int
    var repsHigh: Int
}
struct GymPublicRoutine: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var exercises: [GymRoutineExercise]
}
struct GymTrainingHighlights: Codable, Equatable {
    var workoutCount: Int
    var streakDays: Int
    var weekMuscles: [String: Int]
    var memories: [GymActivityMemory]
    var months: [GymActivityMonth]
    var updatedAt: Double

    init(workoutCount: Int, streakDays: Int, weekMuscles: [String: Int], memories: [GymActivityMemory], months: [GymActivityMonth], updatedAt: Double) {
        self.workoutCount = workoutCount; self.streakDays = streakDays; self.weekMuscles = weekMuscles
        self.memories = memories; self.months = months; self.updatedAt = updatedAt
    }
    enum CodingKeys: String, CodingKey { case workoutCount, streakDays, weekMuscles, memories, months, updatedAt }
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        workoutCount = try v.decodeIfPresent(Int.self, forKey: .workoutCount) ?? 0
        streakDays = try v.decodeIfPresent(Int.self, forKey: .streakDays) ?? 0
        weekMuscles = try v.decodeIfPresent([String: Int].self, forKey: .weekMuscles) ?? [:]
        memories = try v.decodeIfPresent([GymActivityMemory].self, forKey: .memories) ?? []
        months = try v.decodeIfPresent([GymActivityMonth].self, forKey: .months) ?? []
        updatedAt = try v.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
    }
}

enum GymProfileSnapshot {
    static func ranks(profile: UserProfile, workouts: [Workout], exercises: [Exercise]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)).map { ($0.key.rawValue, $0.value) })
    }
    static func highlights(profile: UserProfile, workouts: [Workout], exercises: [Exercise], cardio: [CardioSession], now: Date = Date()) -> GymTrainingHighlights {
        let completed = workouts.filter { $0.isPublished }
        let recent = completed.filter { ($0.publishedAt ?? $0.startedAt) >= now.addingTimeInterval(-7 * 86400) }
        var memories = completed.map { workout in
            GymActivityMemory(id: workout.id.uuidString, date: workout.startedAt.timeIntervalSince1970 * 1000,
                              title: workout.activity.name, minutes: min(1440, max(0, Int(workout.duration / 60))),
                              sets: workout.completedSets.count, score: workout.strengthScore)
        }
        let recordedIDs = Set(completed.map { TrainingHealthManager.syncIdentifier($0.id) })
        let uniqueCardio = cardio.filter { !recordedIDs.contains($0.externalID) }
        memories += uniqueCardio.map { effort in
            GymActivityMemory(id: effort.id.uuidString, date: effort.date.timeIntervalSince1970 * 1000,
                              title: HealthKitManager.activityType(for: effort.type) == .running ? "Running" : "Cardio workout",
                              minutes: min(1440, max(0, Int(effort.durationMinutes))), sets: 0, score: 0)
        }
        let cal = Calendar.current
        let first = cal.dateInterval(of: .month, for: now)?.start ?? now.startOfDay
        let months = (-5...0).compactMap { offset -> GymActivityMonth? in
            guard let start = cal.date(byAdding: .month, value: offset, to: first),
                  let end = cal.date(byAdding: .month, value: 1, to: start) else { return nil }
            let records = memories.filter { $0.date >= start.timeIntervalSince1970 * 1000 && $0.date < end.timeIntervalSince1970 * 1000 }
            return GymActivityMonth(month: start.timeIntervalSince1970 * 1000, sessions: records.count, minutes: records.reduce(0) { $0 + $1.minutes })
        }
        return GymTrainingHighlights(workoutCount: completed.count + uniqueCardio.count,
            streakDays: StreakEngine.current(profile: profile, workouts: workouts, cardio: cardio, today: now).currentDays,
            weekMuscles: ranks(profile: profile, workouts: recent, exercises: exercises),
            memories: Array(memories.sorted { $0.date > $1.date }.prefix(8)), months: months,
            updatedAt: now.timeIntervalSince1970 * 1000)
    }
    static func routines(_ templates: [WorkoutTemplate], exercises: [Exercise], selectedOnly: Bool = true) -> [GymPublicRoutine] {
        templates.filter { (!selectedOnly || $0.isPublic) && !$0.items.isEmpty }.sorted { $0.name < $1.name }.prefix(5).enumerated().map { index, routine in
            GymPublicRoutine(id: "routine-\(Int(routine.createdAt.timeIntervalSince1970 * 1_000_000))", name: routine.name, exercises: routine.items.prefix(20).map { item in
                GymRoutineExercise(name: exercises.first { $0.key == item.exerciseKey }?.nameEn ?? item.exerciseName,
                                   sets: item.sets, repsLow: item.repsLow, repsHigh: item.repsHigh)
            })
        }
    }
}
