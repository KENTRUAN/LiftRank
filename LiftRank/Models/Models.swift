import Foundation
import SwiftData

@Model
final class UserProfile {
    private(set) var name: String = "训练者"
    var sexRaw: String = Sex.male.rawValue
    var birthYear: Int = 1995
    var birthday: Date?
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
    private(set) var hasOnboarded: Bool = false
    var createdAt: Date = Date()
    // Cosmetics bought in the shop ("外观") and the ones currently equipped, stored as "slot:id".
    var ownedCosmetics: [String] = []
    var equippedCosmetics: [String] = []
    // Preferences used to auto-publish the daily training item.
    var planGoalRaw: String = WorkoutGoal.hypertrophy.rawValue
    var planDaysPerWeek: Int = 3
    var planEquipmentRaw: String = EquipmentAccess.fullGym.rawValue
    var planExperienceRaw: String = ExperienceLevel.beginner.rawValue
    var autoPublishDailyPlan: Bool = false
    // AI assistant persona: display name, the character parts drawn in chat ("hair.spiky", …) and the user's description.
    var coachName: String = "小段"
    var coachAvatarIDs: [String] = []
    var coachIntro: String = ""
    // Retained only for compatibility with existing local stores.
    var aiProviderRaw: String = AIProvider.anthropic.rawValue
    var aiModel: String = ""
    var aiBaseURL: String = ""
    var lastBodyAnalysis: String = ""
    var lastBodyAnalysisAt: Date?
    /// Stable identifier embedded in the rank code shared with friends.
    var friendCode: String = ""

    init() {}

    func completeOnboarding(name: String) {
        guard !hasOnboarded else { return }
        updateNickname(name)
        hasOnboarded = true
    }

    func updateNickname(_ value: String) {
        let nickname = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else { return }
        name = nickname
    }

    var sex: Sex { get { Sex(rawValue: sexRaw) ?? .male } set { sexRaw = newValue.rawValue } }
    var unit: WeightUnit { get { WeightUnit(rawValue: unitRaw) ?? .kg } set { unitRaw = newValue.rawValue } }
    var activityLevel: ActivityLevel { get { ActivityLevel(rawValue: activityLevelRaw) ?? .moderate } set { activityLevelRaw = newValue.rawValue } }
    var nutritionGoal: NutritionGoal { get { NutritionGoal(rawValue: nutritionGoalRaw) ?? .maintain } set { nutritionGoalRaw = newValue.rawValue } }
    var planGoal: WorkoutGoal { get { WorkoutGoal(rawValue: planGoalRaw) ?? .hypertrophy } set { planGoalRaw = newValue.rawValue } }
    var planEquipment: EquipmentAccess { get { EquipmentAccess(rawValue: planEquipmentRaw) ?? .fullGym } set { planEquipmentRaw = newValue.rawValue } }
    var planExperience: ExperienceLevel { get { ExperienceLevel(rawValue: planExperienceRaw) ?? .beginner } set { planExperienceRaw = newValue.rawValue } }

    static var birthdayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    var age: Int {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        if let birthday {
            let day = Self.birthdayCalendar.dateComponents([.year, .month, .day], from: birthday)
            if let localBirthday = calendar.date(from: day),
               let years = calendar.dateComponents([.year], from: localBirthday, to: today).year {
                return max(10, years)
            }
        }
        return max(10, calendar.component(.year, from: today) - birthYear)
    }
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
    // Additive defaults keep existing local workouts readable.
    var hasChecklist: Bool = false
    var isOutdoor: Bool = false
    var cardioTimerStartedAt: Date?
    var cardioPauses: [CardioPause] = []
    var routePoints: [WorkoutRoutePoint] = []
    var startOptionsChosen: Bool = false
    var activityRaw: String = "strength"
    var currentExerciseKey: String = ""
    var setStartedAt: Date?
    var setEndedAt: Date?
    var restUntil: Date?
    var healthState: String = "notStarted"
    var healthOwner: String = ""
    var healthWorkoutID: String = ""
    var healthError: String = ""
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout) var exercises: [WorkoutExercise] = []

    init(title: String = "训练", bodyweightKg: Double) {
        self.title = title
        self.bodyweightKg = bodyweightKg
    }

    var sortedExercises: [WorkoutExercise] { exercises.sorted { $0.order < $1.order } }
    var activity: TrainingActivity { get { TrainingActivity(rawValue: activityRaw) ?? .strength } set { activityRaw = newValue.rawValue } }
    var hasPendingSet: Bool { setStartedAt != nil }
    func trainingState(at date: Date = Date()) -> String {
        if isPublished || endedAt != nil { return "Ready" }
        if activity != .strength && cardioTimerStartedAt != nil { return cardioIsPaused ? "Resting" : "Training" }
        if setStartedAt != nil && setEndedAt == nil { return "Training" }
        if let restUntil, restUntil > date { return "Resting" }
        return "Ready"
    }
    var cardioIsPaused: Bool { cardioPauses.last.map { $0.endedAt == nil } ?? false }
    func cardioElapsed(at date: Date = Date()) -> TimeInterval {
        CardioClock.elapsed(start: cardioTimerStartedAt ?? startedAt, pauses: cardioPauses, at: endedAt ?? date)
    }
    var cardioClockRevision: String { "\(id)|\(cardioTimerStartedAt?.timeIntervalSince1970 ?? 0)|\(cardioPauses)|\(endedAt?.timeIntervalSince1970 ?? 0)|\(isPublished)" }
    var duration: TimeInterval { cardioTimerStartedAt == nil ? (endedAt ?? Date()).timeIntervalSince(startedAt) : cardioElapsed() }
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
    case workout, firstOfDay, quest, season, purchase, shop, streakRestore, cardio, dailyTraining
}

/// A cardio session (run, ride, swim...). Imported from Apple Health or logged by hand.
@Model
final class CardioSession {
    var id: UUID = UUID()
    var date: Date = Date()
    var typeRaw: String = CardioType.running.rawValue
    var durationMinutes: Double = 0
    var distanceKm: Double = 0
    var calories: Double = 0
    var avgHeartRate: Double = 0
    var notes: String = ""
    var sourceRaw: String = "manual"
    /// HealthKit workout UUID when imported, used to avoid duplicates.
    var externalID: String = ""
    var writtenToHealth: Bool = false

    init(date: Date, type: CardioType, durationMinutes: Double, distanceKm: Double = 0, calories: Double = 0, avgHeartRate: Double = 0, source: String = "manual", externalID: String = "") {
        self.date = date
        self.typeRaw = type.rawValue
        self.durationMinutes = durationMinutes
        self.distanceKm = distanceKm
        self.calories = calories
        self.avgHeartRate = avgHeartRate
        self.sourceRaw = source
        self.externalID = externalID
    }

    var type: CardioType { get { CardioType(rawValue: typeRaw) ?? .other } set { typeRaw = newValue.rawValue } }
    var isFromHealth: Bool { sourceRaw == "health" }
}

enum CardioType: String, Codable, CaseIterable, Identifiable {
    case running, walking, hiking, cycling, swimming, rowing, elliptical, stairs, jumpRope, hiit, other
    var id: String { rawValue }
    var name: String {
        switch self {
        case .running: "跑步"
        case .walking: "步行"
        case .hiking: "徒步"
        case .cycling: "骑行"
        case .swimming: "游泳"
        case .rowing: "划船机"
        case .elliptical: "椭圆机"
        case .stairs: "爬楼"
        case .jumpRope: "跳绳"
        case .hiit: "HIIT"
        case .other: "其他"
        }
    }
    var icon: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .stairs: "figure.stairs"
        case .jumpRope: "figure.jumprope"
        case .hiit: "figure.highintensity.intervaltraining"
        case .other: "heart.circle"
        }
    }
    var usesDistance: Bool { [.running, .walking, .hiking, .cycling, .swimming, .rowing].contains(self) }
    /// Rough kcal per minute per kg of bodyweight (MET-based) for estimates when no device data exists.
    var metValue: Double {
        switch self {
        case .running: 9.8
        case .walking: 3.5
        case .hiking: 6
        case .cycling: 7.5
        case .swimming: 8
        case .rowing: 7
        case .elliptical: 5
        case .stairs: 8.8
        case .jumpRope: 11
        case .hiit: 10
        case .other: 5
        }
    }
}

/// The training item auto-published for a given day. Edited by hand or through the AI coach.
@Model
final class DailyPlan {
    var dayKey: String = ""
    var title: String = ""
    var items: [TemplateExercise] = []
    var requestedByUser: Bool = false
    var sourceRaw: String = "auto"
    var createdAt: Date = Date()
    var workoutID: UUID?
    init(dayKey: String, title: String, items: [TemplateExercise], source: String = "auto") {
        self.dayKey = dayKey
        self.title = title
        self.items = items
        self.sourceRaw = source
    }
}

/// A friend added through a shared rank code (offline, no account needed).
@Model
final class Friend {
    var code: String = ""
    var name: String = ""
    var gsr: Int = 0
    var muscleScoresJSON: String = "{}"
    var cosmetics: [String] = []
    var streakDays: Int = 0
    var updatedAt: Date = Date()
    var addedAt: Date = Date()
    init(code: String, name: String, gsr: Int, muscleScoresJSON: String, cosmetics: [String], streakDays: Int, updatedAt: Date) {
        self.code = code
        self.name = name
        self.gsr = gsr
        self.muscleScoresJSON = muscleScoresJSON
        self.cosmetics = cosmetics
        self.streakDays = streakDays
        self.updatedAt = updatedAt
    }
    var muscleScores: [MuscleGroup: Int] {
        guard let data = muscleScoresJSON.data(using: .utf8), let dict = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        var out: [MuscleGroup: Int] = [:]
        for (k, v) in dict { if let g = MuscleGroup(rawValue: k) { out[g] = v } }
        return out
    }
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
    var isPublic: Bool = false
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

struct WorkoutRoutePoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
}

@Model
final class TrainerMessage {
    var id: UUID = UUID()
    var role: String = "user"
    var text: String = ""
    var createdAt: Date = Date()
    init(role: String, text: String) { self.role = role; self.text = text }
}
