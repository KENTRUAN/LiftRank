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
                            Text("我的形象").font(.headline)
                            Spacer()
                            NavigationLink {
                                ShopView(profile: profile, gsr: overall, muscles: muscleScores, slots: CosmeticSlot.avatarSlots, title: "形象工坊")
                            } label: { Label("修改形象", systemImage: "wand.and.stars").font(.subheadline.bold()).labelStyle(.titleAndIcon) }
                            .padding(.trailing, 4)
                            HStack(spacing: 2) {
                                sideButton("正面", showsFront: true)
                                sideButton("背面", showsFront: false)
                            }
                            .padding(3)
                            .background(.quaternary, in: Capsule())
                        }
                        Text(front ? "小人的身体按各肌群段位着色，点选肌群查看细分段位 · 三头肌在背面" : "点选肌群查看细分段位")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        MuscleMapView(scores: muscleScores, front: front, spec: profile.avatar)
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
                ToolbarItemGroup(placement: .primaryAction) {
                    NavigationLink { SocialView(profile: profile) } label: { Label("分享与好友", systemImage: "person.2.fill") }
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
    var spec = AvatarSpec()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var groups: [MuscleGroup] { front ? MuscleGroup.frontGroups : MuscleGroup.backGroups }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .center, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            AvatarFigureView(spec: spec, muscles: scores, front: front)
                .frame(width: 170, height: 300)
                .id(front)
                .transition(.opacity)
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
