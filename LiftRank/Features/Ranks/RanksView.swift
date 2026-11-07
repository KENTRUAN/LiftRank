import SwiftUI
import SwiftData

struct RanksView: View {
    let profile: UserProfile
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @State private var side = 0

    private var bests: [ExerciseBest] { RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex) }
    private var muscleScores: [MuscleGroup: Int] { RankAggregator.muscleScores(bests: bests) }
    private var overall: Int { RankAggregator.overall(muscleScores: muscleScores) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        HStack(spacing: 20) {
                            ScoreGauge(score: overall, size: 130)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("总体力量评分 GSR").font(.caption).foregroundStyle(.secondary)
                                TierBadge(tier: RankTier.tier(for: overall))
                                Text("已评分动作 \(bests.count) 个 · 肌群 \(muscleScores.count)/\(MuscleGroup.rankable.count)").font(.caption).foregroundStyle(.secondary)
                                Text("评分 1–1000，按体重与性别曲线换算。").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        LPBar(score: overall)
                    }.card()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("肌群段位图").font(.headline)
                            Spacer()
                            Picker("", selection: $side) { Text("正面").tag(0); Text("背面").tag(1) }.pickerStyle(.segmented).frame(width: 150)
                        }
                        MuscleMapView(scores: muscleScores, front: side == 0)
                        TierLegend()
                    }.card()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("动作段位").font(.headline)
                        if bests.isEmpty {
                            Text("发布一次包含支持段位动作（如卧推、深蹲、硬拉）的训练后，这里会显示每个动作的评分与段位。").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(bests) { b in
                            NavigationLink { ExerciseProgressView(exerciseKey: b.exerciseKey, profile: profile) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(b.name).foregroundStyle(.primary)
                                        Text("\(b.muscleGroup.name) · e1RM \(profile.unit.fromKg(b.bestE1RM).fmt(1)) \(profile.unit.label)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(b.bestScore)").font(.headline.monospacedDigit()).foregroundStyle(b.tier.color)
                                    TierBadge(tier: b.tier, compact: true)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }.padding(.vertical, 6)
                            }
                            Divider()
                        }
                    }.card()
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("段位")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { RankCalculatorView(profile: profile) } label: { Label("评分计算器", systemImage: "function") }
                }
            }
        }
    }
}

struct TierLegend: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RankTier.allCases) { t in
                    HStack(spacing: 4) {
                        Circle().fill(t.color).frame(width: 8, height: 8)
                        Text("\(t.name) \(t.minScore)+").font(.caption2)
                    }
                }
            }
        }
    }
}

struct MuscleMapView: View {
    let scores: [MuscleGroup: Int]
    let front: Bool

    private struct Slot: Identifiable { var id: MuscleGroup { group }; let group: MuscleGroup; let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat }
    private var slots: [Slot] {
        front ? [
            Slot(group: .shoulders, x: 0.22, y: 0.14, w: 0.56, h: 0.07),
            Slot(group: .chest, x: 0.30, y: 0.22, w: 0.40, h: 0.11),
            Slot(group: .biceps, x: 0.12, y: 0.24, w: 0.14, h: 0.14),
            Slot(group: .forearms, x: 0.08, y: 0.40, w: 0.14, h: 0.14),
            Slot(group: .abs, x: 0.36, y: 0.35, w: 0.28, h: 0.18),
            Slot(group: .quads, x: 0.30, y: 0.56, w: 0.40, h: 0.20),
            Slot(group: .calves, x: 0.32, y: 0.80, w: 0.36, h: 0.14),
        ] : [
            Slot(group: .traps, x: 0.30, y: 0.12, w: 0.40, h: 0.08),
            Slot(group: .back, x: 0.28, y: 0.22, w: 0.44, h: 0.16),
            Slot(group: .triceps, x: 0.12, y: 0.24, w: 0.14, h: 0.14),
            Slot(group: .lowerBack, x: 0.36, y: 0.40, w: 0.28, h: 0.10),
            Slot(group: .glutes, x: 0.30, y: 0.52, w: 0.40, h: 0.11),
            Slot(group: .hamstrings, x: 0.30, y: 0.65, w: 0.40, h: 0.15),
            Slot(group: .calves, x: 0.32, y: 0.82, w: 0.36, h: 0.13),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            ZStack {
                BodySilhouette().fill(Color.secondary.opacity(0.10))
                ForEach(slots) { s in
                    let score = scores[s.group]
                    let color = score.map { RankTier.tier(for: $0).color } ?? Color.secondary.opacity(0.25)
                    let tile = VStack(spacing: 1) {
                        Text(s.group.name).font(.system(size: 10, weight: .bold))
                        Text(score.map { "\($0)" } ?? "—").font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(score == nil ? Color.secondary : Color.white)
                    .frame(width: s.w * W, height: s.h * H)
                    .background(color, in: RoundedRectangle(cornerRadius: 8))
                    tile.position(x: (s.x + s.w / 2) * W, y: (s.y + s.h / 2) * H)
                    // Mirror arms on the other side.
                    if s.group == .biceps || s.group == .triceps || s.group == .forearms {
                        tile.position(x: (1 - s.x - s.w / 2) * W, y: (s.y + s.h / 2) * H)
                    }
                }
            }
        }
        .frame(height: 340)
    }
}

/// Simple symmetric human outline used behind the muscle tiles.
struct BodySilhouette: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.addEllipse(in: CGRect(x: w * 0.42, y: 0, width: w * 0.16, height: h * 0.11))
        p.addRoundedRect(in: CGRect(x: w * 0.26, y: h * 0.12, width: w * 0.48, height: h * 0.42), cornerSize: CGSize(width: 24, height: 24))
        p.addRoundedRect(in: CGRect(x: w * 0.08, y: h * 0.14, width: w * 0.16, height: h * 0.42), cornerSize: CGSize(width: 14, height: 14))
        p.addRoundedRect(in: CGRect(x: w * 0.76, y: h * 0.14, width: w * 0.16, height: h * 0.42), cornerSize: CGSize(width: 14, height: 14))
        p.addRoundedRect(in: CGRect(x: w * 0.28, y: h * 0.54, width: w * 0.20, height: h * 0.44), cornerSize: CGSize(width: 14, height: 14))
        p.addRoundedRect(in: CGRect(x: w * 0.52, y: h * 0.54, width: w * 0.20, height: h * 0.44), cornerSize: CGSize(width: 14, height: 14))
        return p
    }
}
