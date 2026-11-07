import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    let workout: Workout
    let profile: UserProfile
    @Query private var exercises: [Exercise]
    private var byKey: [String: Exercise] { Dictionary(uniqueKeysWithValues: exercises.map { ($0.key, $0) }) }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((workout.publishedAt ?? workout.startedAt).mediumString).font(.caption).foregroundStyle(.secondary)
                        Text("时长 \(workout.duration.clockString)")
                        Text("训练量 \(profile.unit.fromKg(workout.totalVolumeKg).fmt(0)) \(profile.unit.label) · \(workout.completedSets.count) 组")
                        Text("体重 \(profile.unit.fromKg(workout.bodyweightKg).fmt(1)) \(profile.unit.label) · +\(workout.xpEarned) XP").foregroundStyle(.secondary).font(.caption)
                    }
                    Spacer()
                    if workout.strengthScore > 0 { ScoreGauge(score: workout.strengthScore, size: 84) }
                }
                if !workout.notes.isEmpty { Text(workout.notes).font(.footnote) }
            }
            ForEach(workout.sortedExercises) { we in
                Section(we.exerciseName) {
                    ForEach(we.sortedSets) { s in
                        HStack {
                            Text(s.type == .normal ? "\(s.order + 1)" : s.type.tag).font(.caption.bold()).frame(width: 24)
                            if we.isCardio {
                                Text("\(s.weightKg.fmt(2)) km · \(s.reps) 分钟")
                            } else {
                                Text("\(profile.unit.fromKg(s.weightKg).fmt(1)) \(profile.unit.label) × \(s.reps)")
                            }
                            if let rpe = s.rpe { Text("RPE \(rpe.fmt(1))").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if let ex = byKey[we.exerciseKey], ex.isRanked, s.type != .warmup {
                                let score = StrengthScoring.score(set: s, exercise: ex, bodyweightKg: workout.bodyweightKg, sex: profile.sex)
                                Text("e1RM \(StrengthScoring.e1RM(set: s, exercise: ex, bodyweightKg: workout.bodyweightKg).fmt(1))").font(.caption2).foregroundStyle(.secondary)
                                Text("\(score)").font(.caption.bold().monospacedDigit()).foregroundStyle(RankTier.tier(for: score).color)
                            }
                        }
                    }
                    if !we.notes.isEmpty { Text(we.notes).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
