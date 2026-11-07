import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String = "训练者"
    var sexRaw: String = Sex.male.rawValue
    var birthYear: Int = 1995
    var heightCm: Double = 175
    var bodyweightKg: Double = 70
    var unitRaw: String = WeightUnit.kg.rawValue
    var activityLevelRaw: String = ActivityLevel.moderate.rawValue
    var nutritionGoalRaw: String = NutritionGoal.maintain.rawValue
    var totalXP: Int = 0
    var eggs: Int = 0
    var superRestore: Int = 1
    var megaRestore: Int = 0
    var streakRevive: Int = 0
    var streakBridgeDays: [String] = []
    var isPro: Bool = false
    var defaultRestSeconds: Int = 90
    var hasOnboarded: Bool = false
    var createdAt: Date = Date()

    init() {}

    var sex: Sex { get { Sex(rawValue: sexRaw) ?? .male } set { sexRaw = newValue.rawValue } }
    var unit: WeightUnit { get { WeightUnit(rawValue: unitRaw) ?? .kg } set { unitRaw = newValue.rawValue } }
    var activityLevel: ActivityLevel { get { ActivityLevel(rawValue: activityLevelRaw) ?? .moderate } set { activityLevelRaw = newValue.rawValue } }
    var nutritionGoal: NutritionGoal { get { NutritionGoal(rawValue: nutritionGoalRaw) ?? .maintain } set { nutritionGoalRaw = newValue.rawValue } }
    var age: Int { max(10, Calendar.current.component(.year, from: Date()) - birthYear) }
}

@Model
final class Exercise {
    @Attribute(.unique) var key: String
    var name: String
    var nameEn: String
    var muscleGroupRaw: String
    var secondaryMuscles: [String]
    var equipmentRaw: String
    var isCardio: Bool
    var isCustom: Bool
    var isRanked: Bool
    /// Fraction of bodyweight lifted for bodyweight movements (0 for external load only).
    var bodyweightFactor: Double
    /// e1RM / bodyweight ratios reaching scores 200, 400, 600, 800, 1000.
    var standardsMale: [Double]
    var standardsFemale: [Double]
    var instructions: String
    var imageData: Data?

    init(key: String, name: String, nameEn: String, muscle: MuscleGroup, secondary: [MuscleGroup] = [], equipment: Equipment,
         isCardio: Bool = false, isCustom: Bool = false, isRanked: Bool = true, bodyweightFactor: Double = 0,
         standardsMale: [Double] = [], standardsFemale: [Double] = [], instructions: String = "") {
        self.key = key
        self.name = name
        self.nameEn = nameEn
        self.muscleGroupRaw = muscle.rawValue
        self.secondaryMuscles = secondary.map(\.rawValue)
        self.equipmentRaw = equipment.rawValue
        self.isCardio = isCardio
        self.isCustom = isCustom
        self.isRanked = isRanked && !standardsMale.isEmpty
        self.bodyweightFactor = bodyweightFactor
        self.standardsMale = standardsMale
        self.standardsFemale = standardsFemale.isEmpty ? standardsMale.map { $0 * 0.72 } : standardsFemale
        self.instructions = instructions
    }

    var muscleGroup: MuscleGroup { MuscleGroup(rawValue: muscleGroupRaw) ?? .fullBody }
    var equipment: Equipment { Equipment(rawValue: equipmentRaw) ?? .other }
    func standards(for sex: Sex) -> [Double] { sex == .male ? standardsMale : standardsFemale }
}

@Model
final class Workout {
    var id: UUID = UUID()
    var title: String = "训练"
    var startedAt: Date = Date()
    var endedAt: Date?
    var notes: String = ""
    var isPublished: Bool = false
    var publishedAt: Date?
    var bodyweightKg: Double = 70
    var strengthScore: Int = 0
    var xpEarned: Int = 0
    var postToStrava: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout) var exercises: [WorkoutExercise] = []

    init(title: String = "训练", bodyweightKg: Double) {
        self.title = title
        self.bodyweightKg = bodyweightKg
    }

    var sortedExercises: [WorkoutExercise] { exercises.sorted { $0.order < $1.order } }
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
    var completedSets: [WorkoutSet] { exercises.flatMap { $0.sets }.filter { $0.isCompleted } }
    var totalVolumeKg: Double { completedSets.filter { $0.type != .warmup }.reduce(0) { $0 + $1.weightKg * Double($1.reps) } }
}

@Model
final class WorkoutExercise {
    var order: Int = 0
    var exerciseKey: String = ""
    var exerciseName: String = ""
    var muscleGroupRaw: String = MuscleGroup.fullBody.rawValue
    var isCardio: Bool = false
    var restSeconds: Int = 90
    var supersetGroup: Int = 0
    var notes: String = ""
    var workout: Workout?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.exercise) var sets: [WorkoutSet] = []

    init(order: Int, exercise: Exercise, restSeconds: Int) {
        self.order = order
        self.exerciseKey = exercise.key
        self.exerciseName = exercise.name
        self.muscleGroupRaw = exercise.muscleGroupRaw
        self.isCardio = exercise.isCardio
        self.restSeconds = restSeconds
    }

    var muscleGroup: MuscleGroup { MuscleGroup(rawValue: muscleGroupRaw) ?? .fullBody }
    var sortedSets: [WorkoutSet] { sets.sorted { $0.order < $1.order } }
}

@Model
final class WorkoutSet {
    var order: Int = 0
    var weightKg: Double = 0
    var reps: Int = 0
    var rpe: Double?
    var rir: Int?
    var typeRaw: String = SetType.normal.rawValue
    var isCompleted: Bool = false
    var completedAt: Date?
    var exercise: WorkoutExercise?

    init(order: Int, weightKg: Double = 0, reps: Int = 0, type: SetType = .normal) {
        self.order = order
        self.weightKg = weightKg
        self.reps = reps
        self.typeRaw = type.rawValue
    }

    var type: SetType { get { SetType(rawValue: typeRaw) ?? .normal } set { typeRaw = newValue.rawValue } }
}

@Model
final class BodyMeasurement {
    var date: Date = Date()
    var metricRaw: String = BodyMetric.weight.rawValue
    var value: Double = 0
    init(date: Date, metric: BodyMetric, value: Double) {
        self.date = date
        self.metricRaw = metric.rawValue
        self.value = value
    }
    var metric: BodyMetric { BodyMetric(rawValue: metricRaw) ?? .weight }
}

@Model
final class FoodEntry {
    var date: Date = Date()
    var mealRaw: String = MealType.lunch.rawValue
    var name: String = ""
    var kcal: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0
    var sourceRaw: String = "manual"
    init(date: Date, meal: MealType, name: String, kcal: Double, protein: Double, fat: Double, carbs: Double, source: String = "manual") {
        self.date = date
        self.mealRaw = meal.rawValue
        self.name = name
        self.kcal = kcal
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.sourceRaw = source
    }
    var meal: MealType { MealType(rawValue: mealRaw) ?? .lunch }
}

@Model
final class CustomMeal {
    var name: String = ""
    var kcal: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0
    init(name: String, kcal: Double, protein: Double, fat: Double, carbs: Double) {
        self.name = name; self.kcal = kcal; self.protein = protein; self.fat = fat; self.carbs = carbs
    }
}

@Model
final class QuestClaim {
    var questID: String = ""
    var periodKey: String = ""
    var claimedAt: Date = Date()
    init(questID: String, periodKey: String) {
        self.questID = questID
        self.periodKey = periodKey
    }
}

/// Ledger of XP / Egg movements. Used for season XP, history and auditing.
@Model
final class RewardEvent {
    var date: Date = Date()
    var kindRaw: String = RewardKind.workout.rawValue
    var xp: Int = 0
    var eggs: Int = 0
    var note: String = ""
    init(date: Date = Date(), kind: RewardKind, xp: Int, eggs: Int, note: String) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.xp = xp
        self.eggs = eggs
        self.note = note
    }
    var kind: RewardKind { RewardKind(rawValue: kindRaw) ?? .workout }
}

enum RewardKind: String, Codable {
    case workout, firstOfDay, quest, season, purchase, shop, streakRestore
}

struct TemplateExercise: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var exerciseKey: String
    var exerciseName: String
    var sets: Int
    var repsLow: Int
    var repsHigh: Int
    var restSeconds: Int
    var weekProgressionPercent: Double = 0
}

@Model
final class WorkoutTemplate {
    var name: String = ""
    var createdAt: Date = Date()
    var weeks: Int = 1
    var dayIndex: Int = 0
    var planName: String = ""
    var items: [TemplateExercise] = []
    init(name: String, items: [TemplateExercise], weeks: Int = 1, dayIndex: Int = 0, planName: String = "") {
        self.name = name
        self.items = items
        self.weeks = weeks
        self.dayIndex = dayIndex
        self.planName = planName
    }
}

enum BodyMetric: String, Codable, CaseIterable, Identifiable {
    case weight, bodyFat, height, neck, shoulders, chest, waist, abdomen, hips
    case leftUpperArm, rightUpperArm, leftForearm, rightForearm, leftThigh, rightThigh, leftCalf, rightCalf
    var id: String { rawValue }
    var name: String {
        switch self {
        case .weight: "体重"
        case .bodyFat: "体脂率"
        case .height: "身高"
        case .neck: "颈围"
        case .shoulders: "肩围"
        case .chest: "胸围"
        case .waist: "腰围"
        case .abdomen: "腹围"
        case .hips: "臀围"
        case .leftUpperArm: "左上臂"
        case .rightUpperArm: "右上臂"
        case .leftForearm: "左前臂"
        case .rightForearm: "右前臂"
        case .leftThigh: "左大腿"
        case .rightThigh: "右大腿"
        case .leftCalf: "左小腿"
        case .rightCalf: "右小腿"
        }
    }
    var unit: String {
        switch self {
        case .weight: "kg"
        case .bodyFat: "%"
        default: "cm"
        }
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var name: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .snack: "加餐"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }
    var name: String {
        switch self {
        case .sedentary: "久坐"
        case .light: "轻度活动"
        case .moderate: "中度活动"
        case .active: "活跃"
        case .veryActive: "非常活跃"
        }
    }
    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }
}

enum NutritionGoal: String, Codable, CaseIterable, Identifiable {
    case cut, maintain, bulk
    var id: String { rawValue }
    var name: String {
        switch self {
        case .cut: "减脂"
        case .maintain: "维持"
        case .bulk: "增肌"
        }
    }
    var kcalAdjustment: Double {
        switch self {
        case .cut: -500
        case .maintain: 0
        case .bulk: 300
        }
    }
}
