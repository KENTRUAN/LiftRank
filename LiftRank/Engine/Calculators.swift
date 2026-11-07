import Foundation

struct MacroTargets {
    var kcal: Double
    var protein: Double
    var fat: Double
    var carbs: Double
}

enum NutritionEngine {
    /// Mifflin–St Jeor basal metabolic rate.
    static func bmr(sex: Sex, weightKg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    static func tdee(sex: Sex, weightKg: Double, heightCm: Double, age: Int, activity: ActivityLevel) -> Double {
        bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age) * activity.multiplier
    }

    /// Protein 2.2 g/kg, fat 1 g/kg, carbs take the remainder; carbs are protected at ≥20% of calories.
    static func targets(tdee: Double, weightKg: Double, goal: NutritionGoal) -> MacroTargets {
        let kcal = max(1200, tdee + goal.kcalAdjustment)
        var protein = weightKg * 2.2
        var fat = weightKg * 1.0
        let minCarbKcal = kcal * 0.20
        let pfKcal = protein * 4 + fat * 9
        if kcal - pfKcal < minCarbKcal {
            let scale = max(0, (kcal - minCarbKcal) / pfKcal)
            protein *= scale
            fat *= scale
        }
        let carbs = max(0, (kcal - protein * 4 - fat * 9) / 4)
        return MacroTargets(kcal: kcal.rounded(), protein: protein.rounded(), fat: fat.rounded(), carbs: carbs.rounded())
    }
}

enum BodyFatCalculator {
    /// US Navy circumference method (metric, cm). Hip is required for women.
    static func percent(sex: Sex, heightCm: Double, neckCm: Double, waistCm: Double, hipCm: Double = 0) -> Double? {
        guard heightCm > 0, neckCm > 0, waistCm > neckCm else { return nil }
        let value: Double
        switch sex {
        case .male:
            value = 495 / (1.0324 - 0.19077 * log10(waistCm - neckCm) + 0.15456 * log10(heightCm)) - 450
        case .female:
            guard hipCm > 0, waistCm + hipCm > neckCm else { return nil }
            value = 495 / (1.29579 - 0.35004 * log10(waistCm + hipCm - neckCm) + 0.22100 * log10(heightCm)) - 450
        }
        return value.isFinite ? max(2, min(60, value)) : nil
    }
}

enum PlateCalculator {
    static let defaultPlatesKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    static let defaultPlatesLb: [Double] = [45, 35, 25, 10, 5, 2.5]

    /// Greedy per-side loading that never exceeds the target.
    static func plates(target: Double, bar: Double, available: [Double]) -> (perSide: [Double], achieved: Double) {
        var remaining = max(0, (target - bar) / 2)
        var out: [Double] = []
        for p in available.sorted(by: >) {
            while remaining >= p - 0.0001 { out.append(p); remaining -= p }
        }
        let achieved = bar + out.reduce(0, +) * 2
        return (out, achieved)
    }
}

enum WorkoutGoal: String, CaseIterable, Identifiable {
    case strength, hypertrophy, general, fatLoss
    var id: String { rawValue }
    var name: String {
        switch self {
        case .strength: "力量"
        case .hypertrophy: "增肌"
        case .general: "综合体能"
        case .fatLoss: "减脂"
        }
    }
    var scheme: (sets: Int, low: Int, high: Int, rest: Int) {
        switch self {
        case .strength: (4, 3, 6, 180)
        case .hypertrophy: (3, 8, 12, 90)
        case .general: (3, 8, 15, 75)
        case .fatLoss: (3, 12, 20, 45)
        }
    }
}

enum ExperienceLevel: String, CaseIterable, Identifiable {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var name: String {
        switch self {
        case .beginner: "新手"
        case .intermediate: "进阶"
        case .advanced: "高级"
        }
    }
    var exercisesPerDay: Int { self == .beginner ? 4 : self == .intermediate ? 5 : 6 }
}

enum EquipmentAccess: String, CaseIterable, Identifiable {
    case fullGym, dumbbellsOnly, bodyweight
    var id: String { rawValue }
    var name: String {
        switch self {
        case .fullGym: "健身房"
        case .dumbbellsOnly: "仅哑铃"
        case .bodyweight: "自重"
        }
    }
    func allows(_ e: Equipment) -> Bool {
        switch self {
        case .fullGym: return e != .cardio
        case .dumbbellsOnly: return e == .dumbbell || e == .bodyweight || e == .band
        case .bodyweight: return e == .bodyweight || e == .band
        }
    }
}

/// Rule-based program generator. No AI: splits by training days, exercises by equipment, volume by goal.
enum WorkoutGenerator {
    static func splits(daysPerWeek: Int) -> [(name: String, groups: [MuscleGroup])] {
        switch daysPerWeek {
        case ...2: return [("全身 A", [.quads, .chest, .back, .shoulders, .abs]), ("全身 B", [.hamstrings, .back, .chest, .glutes, .biceps, .triceps])]
        case 3: return [("全身 A", [.quads, .chest, .back, .abs]), ("全身 B", [.hamstrings, .shoulders, .back, .biceps, .triceps]), ("全身 C", [.glutes, .chest, .back, .calves, .abs])]
        case 4: return [("上肢 A", [.chest, .back, .shoulders, .triceps]), ("下肢 A", [.quads, .hamstrings, .glutes, .calves]), ("上肢 B", [.back, .chest, .biceps, .shoulders]), ("下肢 B", [.glutes, .quads, .hamstrings, .abs])]
        default: return [("推", [.chest, .shoulders, .triceps, .chest]), ("拉", [.back, .back, .biceps, .traps]), ("腿", [.quads, .hamstrings, .glutes, .calves]), ("上肢", [.chest, .back, .shoulders, .biceps]), ("下肢核心", [.quads, .glutes, .hamstrings, .abs]), ("弱项补强", [.shoulders, .back, .triceps, .abs])]
        }
    }

    static func generate(goal: WorkoutGoal, daysPerWeek: Int, equipment: EquipmentAccess, experience: ExperienceLevel,
                         weeks: Int, exercises: [Exercise]) -> [WorkoutTemplate] {
        let pool = exercises.filter { !$0.isCardio && equipment.allows($0.equipment) }
        let scheme = goal.scheme
        let perDay = experience.exercisesPerDay
        let planName = "\(goal.name) · 每周 \(daysPerWeek) 天 · \(weeks) 周"
        var templates: [WorkoutTemplate] = []
        for (i, split) in splits(daysPerWeek: max(1, min(6, daysPerWeek))).prefix(max(1, daysPerWeek)).enumerated() {
            var chosen: [Exercise] = []
            var groups = split.groups
            var chosenAtPassStart = 0
            while chosen.count < perDay, !groups.isEmpty {
                let g = groups.removeFirst()
                // Prefer barbell/machine compounds first, then whatever is left for the group.
                let candidates = pool.filter { $0.muscleGroup == g && !chosen.contains($0) }
                    .sorted { ($0.isRanked ? 0 : 1, $0.equipment == .barbell ? 0 : 1) < ($1.isRanked ? 0 : 1, $1.equipment == .barbell ? 0 : 1) }
                if let pick = candidates.first { chosen.append(pick) }
                if groups.isEmpty && chosen.count < perDay {
                    // Stop when a full pass cannot add an exercise for this split.
                    guard chosen.count > chosenAtPassStart else { break }
                    chosenAtPassStart = chosen.count
                    groups = split.groups.reversed()
                }
            }
            let items = chosen.map { ex in
                TemplateExercise(exerciseKey: ex.key, exerciseName: ex.name, sets: scheme.sets, repsLow: scheme.low, repsHigh: scheme.high,
                                 restSeconds: scheme.rest, weekProgressionPercent: goal == .strength ? 2.5 : 1.5)
            }
            templates.append(WorkoutTemplate(name: "第 \(i + 1) 天 · \(split.name)", items: items, weeks: weeks, dayIndex: i, planName: planName))
        }
        return templates
    }
}
