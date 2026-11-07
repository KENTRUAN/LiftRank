import SwiftUI
import SwiftData

struct RanksView: View {
    let profile: UserProfile
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @State private var front = true

    var body: some View {
        let bests = RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)
        let muscleScores = RankAggregator.muscleScores(bests: bests)
        let overall = RankAggregator.overall(muscleScores: muscleScores)
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
                            HStack(spacing: 2) {
                                sideButton("正面", showsFront: true)
                                sideButton("背面", showsFront: false)
                            }
                            .padding(3)
                            .background(.quaternary, in: Capsule())
                        }
                        Text(front ? "点选肌群查看细分段位 · 三头肌在背面" : "点选肌群查看细分段位")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        MuscleMapView(scores: muscleScores, front: front)
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
            .navigationDestination(for: MuscleGroup.self) { group in
                MuscleRankDetail(group: group, score: muscleScores[group], bests: bests,
                                 exercises: exercises, profile: profile)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { RankCalculatorView(profile: profile) } label: { Label("评分计算器", systemImage: "function") }
                }
            }
        }
    }

    private func sideButton(_ title: String, showsFront: Bool) -> some View {
        let selected = front == showsFront
        return Button {
            front = showsFront
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if selected { Capsule().fill(Color(.secondarySystemGroupedBackground)) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

private struct MuscleRankDetail: View {
    let group: MuscleGroup
    let score: Int?
    let bests: [ExerciseBest]
    let exercises: [Exercise]
    let profile: UserProfile

    var body: some View {
        List {
            Section("肌群总段位") {
                HStack {
                    Text(group.name)
                    Spacer()
                    rankValue(score)
                }
            }

            Section {
                ForEach(group.regions) { region in
                    let related = exercises.filter { region.exerciseKeys.contains($0.key) }
                    let records = bests.filter { region.exerciseKeys.contains($0.exerciseKey) && $0.bestScore > 0 }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(region.name).font(.headline)
                            Spacer()
                            rankValue(RankAggregator.muscleScore(bests: records),
                                      empty: related.contains(where: \.isRanked) ? "待评分" : "暂无独立评分")
                        }
                        if !related.isEmpty {
                            Text(related.map(\.name).sorted().joined(separator: "、"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            } header: {
                Text("细分段位")
            } footer: {
                Text(group == .chest
                     ? "细分段位由相关动作的最佳记录估算。训练记录未区分左右侧，左右胸暂不单独评分。"
                     : "细分段位由相关动作的最佳记录估算。发布有评分标准的相关训练后，才会显示对应段位。")
            }

            Section("本肌群已评分动作") {
                let records = bests.filter { $0.muscleGroup == group && $0.bestScore > 0 }
                if records.isEmpty {
                    Text("还没有评分记录").foregroundStyle(.secondary)
                }
                ForEach(records) { record in
                    NavigationLink {
                        ExerciseProgressView(exerciseKey: record.exerciseKey, profile: profile)
                    } label: {
                        HStack {
                            Text(record.name)
                            Spacer()
                            rankValue(record.bestScore)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(group.name)段位")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func rankValue(_ score: Int?, empty: String = "待评分") -> some View {
        if let score {
            Text("\(score)").monospacedDigit()
            TierBadge(tier: RankTier.tier(for: score), compact: true)
        } else {
            Text(empty).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct MuscleMapView: View {
    let scores: [MuscleGroup: Int]
    let front: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var groups: [MuscleGroup] { front ? MuscleGroup.frontGroups : MuscleGroup.backGroups }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .center, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            ZStack {
                BodySilhouette()
                    .fill(Color.secondary.opacity(0.12))
                    .allowsHitTesting(false)
                ForEach(groups) { group in
                    let region = BodyRegion(group: group, front: front)
                    NavigationLink(value: group) {
                        region
                            .fill(LinearGradient(colors: [color(for: group), color(for: group).opacity(0.72)],
                                                 startPoint: .top, endPoint: .bottom))
                            .overlay { region.strokeBorderColor }
                            .contentShape(region)
                    }
                    .buttonStyle(.plain)
                }
                .id(front)
                .transition(.opacity)
            }
            .frame(width: 160, height: 310)
            .accessibilityHidden(true)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: front)

            VStack(spacing: 0) {
                ForEach(groups) { group in
                    NavigationLink(value: group) {
                        HStack(spacing: 6) {
                            Circle().fill(color(for: group)).frame(width: 8, height: 8)
                            Text(group.name).font(.subheadline).foregroundStyle(.primary)
                            Spacer(minLength: 2)
                            Text(scores[group].map { String($0) } ?? "—")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(group.name)
                    .accessibilityValue(scores[group].map { String($0) } ?? "待评分")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func color(for group: MuscleGroup) -> Color {
        scores[group].map { RankTier.tier(for: $0).color } ?? .secondary.opacity(0.38)
    }
}

private struct BodySilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.width * 0.415, y: rect.height * 0.01,
                                   width: rect.width * 0.17, height: rect.height * 0.12))
        path.addRoundedOutline([(45, 20), (55, 20), (57, 27), (71, 30), (73, 46), (65, 68),
                                (69, 87), (60, 96), (40, 96), (31, 87), (35, 68),
                                (27, 46), (29, 30), (43, 27)], in: rect)
        path.addMirroredOutline([(31, 29), (23, 30), (16, 41), (13, 61), (9, 76), (7, 93),
                                 (10, 100), (15, 98), (19, 80), (24, 65), (29, 53), (34, 41)], in: rect)
        path.addMirroredOutline([(32, 84), (49, 91), (47, 114), (43, 137), (43, 150),
                                 (39, 172), (42, 177), (29, 178), (29, 173), (31, 151),
                                 (29, 135), (26, 111), (27, 94)], in: rect)
        return path
    }
}

private struct BodyRegion: Shape {
    let group: MuscleGroup
    let front: Bool

    var strokeBorderColor: some View {
        stroke(Color(.systemBackground).opacity(0.65), lineWidth: 0.8)
    }

    func path(in rect: CGRect) -> Path {
        let points: [BodyPoint]
        switch group {
        case .shoulders:
            points = [(31, 30), (25, 31), (20, 36), (18, 45), (23, 46), (29, 42), (33, 35)]
        case .chest:
            points = [(34, 33), (46, 33), (49, 37), (48, 51), (39, 53), (29, 48), (30, 41)]
        case .biceps, .triceps:
            points = front
                ? [(19, 46), (26, 46), (28, 50), (24, 61), (19, 66), (15, 62), (16, 53)]
                : [(18, 46), (25, 46), (27, 51), (23, 62), (17, 67), (14, 62), (15, 53)]
        case .forearms:
            points = [(16, 65), (22, 66), (21, 72), (15, 89), (10, 91), (10, 83), (12, 74)]
        case .abs:
            points = [(37, 53), (47, 54), (49, 62), (48, 79), (44, 86), (36, 80), (36, 70)]
        case .quads:
            points = [(34, 88), (46, 94), (46, 105), (43, 120), (40, 133), (34, 135), (30, 122), (28, 104), (29, 94)]
        case .calves:
            points = [(34, 136), (41, 136), (42, 143), (39, 157), (36, 169), (32, 171), (32, 160), (31, 146)]
        case .traps:
            points = [(44, 26), (49, 24), (49, 49), (44, 49), (40, 38), (33, 32)]
        case .back:
            points = [(33, 37), (40, 39), (44, 50), (49, 52), (46, 64), (41, 72), (36, 64), (31, 51)]
        case .lowerBack:
            points = [(47, 64), (49, 64), (49, 79), (46, 85), (38, 79), (40, 73)]
        case .glutes:
            points = [(35, 81), (44, 84), (49, 89), (48, 97), (42, 101), (33, 98), (29, 92)]
        case .hamstrings:
            points = [(30, 100), (38, 103), (46, 100), (44, 115), (40, 132), (34, 134), (31, 125), (28, 108)]
        case .cardio, .fullBody:
            return Path()
        }
        var path = Path()
        path.addMirroredOutline(points, in: rect)
        return path
    }
}

private typealias BodyPoint = (x: CGFloat, y: CGFloat)

private extension Path {
    mutating func addMirroredOutline(_ points: [BodyPoint], in rect: CGRect) {
        addRoundedOutline(points, in: rect)
        addRoundedOutline(points.reversed().map { (100 - $0.x, $0.y) }, in: rect)
    }

    mutating func addRoundedOutline(_ points: [BodyPoint], in rect: CGRect) {
        let scaled = points.map { CGPoint(x: rect.minX + $0.x * rect.width / 100,
                                          y: rect.minY + $0.y * rect.height / 180) }
        guard let first = scaled.first, let last = scaled.last else { return }
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        move(to: midpoint(last, first))
        for (index, point) in scaled.enumerated() {
            let next = scaled[(index + 1) % scaled.count]
            addQuadCurve(to: midpoint(point, next), control: point)
        }
        closeSubpath()
    }
}
