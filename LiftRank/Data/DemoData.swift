import Foundation
import SwiftData

/// Development helper: launch with env LIFTRANK_DEMO=1 to seed a sample history, LIFTRANK_TAB=<0-4> to open a tab.
enum DemoData {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["LIFTRANK_DEMO"] == "1" }
    static var initialTab: Int { Int(ProcessInfo.processInfo.environment["LIFTRANK_TAB"] ?? "") ?? 0 }
    static var autoOpenActive: Bool { ProcessInfo.processInfo.environment["LIFTRANK_ACTIVE"] == "1" }

    static func seedIfNeeded(context: ModelContext, profile: UserProfile) {
        guard isEnabled else { return }
        let published = (try? context.fetch(FetchDescriptor<Workout>()))?.filter { $0.isPublished } ?? []
        guard published.isEmpty else { return }
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let byKey = Dictionary(uniqueKeysWithValues: exercises.map { ($0.key, $0) })
        profile.completeOnboarding(name: "示例用户")
        profile.bodyweightKg = 75

        let plan: [(daysAgo: Int, title: String, items: [(String, [(Double, Int)])])] = [
            (12, "推力日", [("bench_press", [(60, 10), (70, 8), (75, 6)]), ("ohp", [(35, 10), (40, 8)]), ("tricep_pushdown", [(25, 12), (25, 12)])]),
            (10, "拉力日", [("deadlift", [(100, 5), (120, 5), (130, 3)]), ("pullup", [(0, 8), (0, 7)]), ("barbell_row", [(60, 10), (65, 8)])]),
            (7, "腿部日", [("squat", [(80, 8), (90, 6), (100, 5)]), ("rdl", [(80, 10), (90, 8)]), ("leg_press", [(160, 12), (180, 10)])]),
            (4, "推力日", [("bench_press", [(65, 10), (75, 8), (80, 5)]), ("incline_db_bench", [(24, 10), (26, 8)]), ("lateral_raise", [(8, 15), (8, 15)])]),
            (2, "拉力日", [("deadlift", [(110, 5), (130, 4), (140, 2)]), ("lat_pulldown", [(60, 10), (65, 8)]), ("barbell_curl", [(30, 10), (32.5, 8)])]),
            (0, "腿部日", [("squat", [(85, 8), (95, 6), (105, 4)]), ("hip_thrust", [(100, 10), (120, 8)]), ("standing_calf_raise", [(80, 15), (90, 12)])]),
        ]
        var allWorkouts: [Workout] = []
        for day in plan {
            let w = Workout(title: day.title, bodyweightKg: 75)
            w.startedAt = Date().adding(days: -day.daysAgo).addingTimeInterval(-3600 * 3)
            w.endedAt = w.startedAt.addingTimeInterval(3600)
            context.insert(w)
            for (i, item) in day.items.enumerated() {
                guard let ex = byKey[item.0] else { continue }
                let we = WorkoutExercise(order: i, exercise: ex, restSeconds: 90)
                for (j, s) in item.1.enumerated() {
                    let set = WorkoutSet(order: j, weightKg: s.0, reps: s.1)
                    set.isCompleted = true
                    set.completedAt = w.startedAt.addingTimeInterval(Double(i * 600 + j * 120))
                    we.sets.append(set)
                }
                w.exercises.append(we)
            }
            _ = WorkoutPublisher.publish(w, profile: profile, exercises: exercises, workouts: allWorkouts, context: context)
            w.publishedAt = w.endedAt
            allWorkouts.append(w)
        }
        for (d, v) in [(12, 76.2), (7, 75.8), (2, 75.1), (0, 75.0)] {
            context.insert(BodyMeasurement(date: Date().adding(days: -d), metric: .weight, value: v))
        }
        context.insert(BodyMeasurement(date: Date(), metric: .waist, value: 82))
        if autoOpenActive, let bench = byKey["bench_press"], let row = byKey["barbell_row"] {
            let w = Workout(title: "推拉日（进行中）", bodyweightKg: 75)
            w.startedAt = Date().addingTimeInterval(-25 * 60)
            context.insert(w)
            let a = WorkoutExercise(order: 0, exercise: bench, restSeconds: 120)
            for (j, s) in [(60.0, 10), (70.0, 8), (80.0, 5)].enumerated() {
                let set = WorkoutSet(order: j, weightKg: s.0, reps: s.1, type: j == 0 ? .warmup : .normal)
                set.isCompleted = j < 2; set.rpe = j == 1 ? 8 : nil; set.rir = j == 1 ? 2 : nil
                a.sets.append(set)
            }
            let b = WorkoutExercise(order: 1, exercise: row, restSeconds: 90)
            for j in 0..<3 { b.sets.append(WorkoutSet(order: j, weightKg: 65, reps: 8)) }
            w.exercises.append(a); w.exercises.append(b)
        }
        context.insert(FoodEntry(date: Date(), meal: .breakfast, name: "燕麦 50g", kcal: 190, protein: 6.5, fat: 3.5, carbs: 33))
        context.insert(FoodEntry(date: Date(), meal: .breakfast, name: "全蛋 2 个", kcal: 144, protein: 12.6, fat: 9.6, carbs: 0.8))
        context.insert(FoodEntry(date: Date(), meal: .lunch, name: "鸡胸肉 150g", kcal: 248, protein: 46, fat: 5.4, carbs: 0))
        context.insert(FoodEntry(date: Date(), meal: .lunch, name: "白米饭 1 碗", kcal: 230, protein: 4.5, fat: 0.5, carbs: 50))
        try? context.save()
    }
}
