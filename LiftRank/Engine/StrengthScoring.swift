import Foundation

/// Deterministic strength scoring: e1RM → bodyweight ratio → 1–1000 score → tier.
enum StrengthScoring {
    static let repCap = 30
    static let anchorScores: [Double] = [200, 400, 600, 800, 1000]

    /// Epley estimate, reps capped at 30, RIR adds "reps left in the tank".
    static func epley(weightKg: Double, reps: Int, rir: Int? = nil) -> Double {
        let effective = min(reps + max(0, rir ?? 0), repCap)
        guard effective > 0, weightKg > 0 else { return 0 }
        if effective == 1 { return weightKg }
        return weightKg * (1 + Double(effective) / 30)
    }

    static func brzycki(weightKg: Double, reps: Int) -> Double {
        let r = min(max(reps, 1), 36)
        if r == 1 { return weightKg }
        return weightKg * 36 / (37 - Double(r))
    }

    /// Load used for scoring; bodyweight movements count a fraction of bodyweight plus added load.
    static func effectiveLoad(exercise: Exercise, weightKg: Double, bodyweightKg: Double) -> Double {
        exercise.bodyweightFactor * bodyweightKg + weightKg
    }

    static func e1RM(set: WorkoutSet, exercise: Exercise, bodyweightKg: Double) -> Double {
        let load = effectiveLoad(exercise: exercise, weightKg: set.weightKg, bodyweightKg: bodyweightKg)
        return epley(weightKg: load, reps: set.reps, rir: set.rir)
    }

    /// Maps e1RM to a 1–1000 score via piecewise-linear interpolation over the exercise standards.
    static func score(e1RM: Double, bodyweightKg: Double, anchors: [Double]) -> Int {
        guard e1RM > 0, bodyweightKg > 0, anchors.count == 5 else { return 0 }
        let ratio = e1RM / bodyweightKg
        if ratio <= anchors[0] {
            return max(1, Int((ratio / anchors[0] * 200).rounded(.down)))
        }
        for i in 1..<anchors.count where ratio <= anchors[i] {
            let t = (ratio - anchors[i - 1]) / (anchors[i] - anchors[i - 1])
            return Int((anchorScores[i - 1] + t * 200).rounded(.down))
        }
        return 1000
    }

    static func score(set: WorkoutSet, exercise: Exercise, bodyweightKg: Double, sex: Sex) -> Int {
        guard exercise.isRanked, set.type != .warmup else { return 0 }
        let e = e1RM(set: set, exercise: exercise, bodyweightKg: bodyweightKg)
        return score(e1RM: e, bodyweightKg: bodyweightKg, anchors: exercise.standards(for: sex))
    }

    /// Weight needed at a given rep count to hit a target score (used by the rank calculator).
    static func ratio(forScore target: Int, anchors: [Double]) -> Double {
        guard anchors.count == 5 else { return 0 }
        let s = Double(max(1, min(1000, target)))
        if s <= 200 { return anchors[0] * s / 200 }
        let i = min(4, Int((s - 200) / 200) + 1)
        let t = (s - anchorScores[i - 1]) / 200
        return anchors[i - 1] + t * (anchors[i] - anchors[i - 1])
    }
}

struct ExerciseBest: Identifiable {
    var id: String { exerciseKey }
    let exerciseKey: String
    let name: String
    let muscleGroup: MuscleGroup
    let bestScore: Int
    let bestE1RM: Double
    let date: Date
    var tier: RankTier { RankTier.tier(for: bestScore) }
}

enum RankAggregator {
    /// Best score per ranked exercise across published workouts.
    static func exerciseBests(workouts: [Workout], exercises: [Exercise], sex: Sex) -> [ExerciseBest] {
        let byKey = Dictionary(uniqueKeysWithValues: exercises.map { ($0.key, $0) })
        var best: [String: ExerciseBest] = [:]
        for w in workouts where w.isPublished {
            for we in w.exercises {
                guard let ex = byKey[we.exerciseKey], ex.isRanked else { continue }
                for s in we.sets where s.isCompleted && s.type != .warmup {
                    let score = StrengthScoring.score(set: s, exercise: ex, bodyweightKg: w.bodyweightKg, sex: sex)
                    let e = StrengthScoring.e1RM(set: s, exercise: ex, bodyweightKg: w.bodyweightKg)
                    if score > (best[ex.key]?.bestScore ?? -1) {
                        best[ex.key] = ExerciseBest(exerciseKey: ex.key, name: ex.name, muscleGroup: ex.muscleGroup,
                                                    bestScore: score, bestE1RM: e, date: w.publishedAt ?? w.startedAt)
                    }
                }
            }
        }
        return best.values.sorted { $0.bestScore > $1.bestScore }
    }

    /// Weighted average where the strongest exercise in a group counts most.
    static func muscleScores(bests: [ExerciseBest]) -> [MuscleGroup: Int] {
        var out: [MuscleGroup: Int] = [:]
        for g in MuscleGroup.rankable {
            let scores = bests.filter { $0.muscleGroup == g }.map { Double($0.bestScore) }.sorted(by: >)
            guard !scores.isEmpty else { continue }
            out[g] = weighted(scores, decay: 0.5)
        }
        return out
    }

    /// Overall strength score (GSR): stronger groups weigh more.
    static func overall(muscleScores: [MuscleGroup: Int]) -> Int {
        let scores = muscleScores.values.map(Double.init).sorted(by: >)
        guard !scores.isEmpty else { return 0 }
        return weighted(scores, decay: 0.8)
    }

    private static func weighted(_ sorted: [Double], decay: Double) -> Int {
        var wsum = 0.0, total = 0.0, w = 1.0
        for s in sorted { total += s * w; wsum += w; w *= decay }
        return Int((total / wsum).rounded())
    }
}
