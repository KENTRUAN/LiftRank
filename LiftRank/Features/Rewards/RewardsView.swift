import SwiftUI
import SwiftData

/// 奖励 tab: daily training reward, streak, season, weekly bonuses and the cosmetics shop.
struct RewardsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Query private var workouts: [Workout]
    @Query private var cardio: [CardioSession]
    @Query private var claims: [QuestClaim]
    @Query private var plans: [DailyPlan]
    @Query private var exercises: [Exercise]
    @Query(sort: \RewardEvent.date, order: .reverse) private var rewards: [RewardEvent]
    @State private var toast: String?

    private var gsr: Int {
        RankAggregator.overall(muscleScores: RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)))
    }
    private var tier: RankTier { RankTier.tier(for: gsr) }
    private var streak: StreakInfo { StreakEngine.current(profile: profile, workouts: workouts, cardio: cardio) }
    private var season: Season { SeasonEngine.current() }
    private var seasonDays: Int {
        StreakEngine.trainingDays(workouts: workouts, cardio: cardio).filter { $0 >= season.start && $0 < season.end }.count
    }
    private var daily: DailyTrainingStatus { DailyTrainingEngine.status(profile: profile, workouts: workouts, cardio: cardio, claims: claims, gsr: gsr) }
    private var quests: [Quest] { QuestEngine.weeklyQuests(workouts: workouts, cardio: cardio) }
    private var todayPlan: DailyPlan? { plans.first { $0.dayKey == Date().dayKey } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dailyCard
                    streakCard
                    cosmeticsCard
                    seasonCard
                    questCard
                    historyCard
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("奖励")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 4) { EggIcon(size: 16); Text("\(profile.eggs)").font(.subheadline.bold().monospacedDigit()) }
                }
            }
            .onAppear(perform: autoClaim)
            .toast($toast)
        }
    }

    private var dailyCard: some View {
        let s = daily
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: s.isComplete ? "checkmark.seal.fill" : "figure.strengthtraining.traditional")
                    .font(.largeTitle).foregroundStyle(s.isComplete ? .green : Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.isComplete ? "今日训练已完成" : "今日训练").font(.title3.bold())
                    if s.isComplete {
                        HStack(spacing: 3) { Text("已获得"); EggAmount(amount: s.reward, signed: true) }.font(.caption).foregroundStyle(.secondary)
                    } else if let p = todayPlan {
                        Text("\(p.title) · \(p.items.count) 个动作").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("发布一次力量训练或 10 分钟以上有氧即可完成。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if !s.isComplete {
                HStack(spacing: 3) {
                    Text("完成可得")
                    EggAmount(amount: s.reward)
                    Text("· \(tier.name) 段位加成 +\(tier.rawValue * 3)")
                    if streak.currentDays > 0 { Text("· 连续 +\(min(streak.currentDays, 30) / 3)") }
                }.font(.caption).foregroundStyle(.secondary)
                Button {
                    AppState.shared.perform(.startTodayWorkout)
                } label: { Label(todayPlan == nil ? "去训练" : "开始今日训练", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("段位越高、连续天数越长，每日奖励越多。Eggs 可在商店购买外观。").font(.caption2).foregroundStyle(.secondary)
            }
        }.card()
    }

    private var streakCard: some View {
        let s = streak
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "flame.fill").font(.largeTitle).foregroundStyle(s.isActive ? .orange : .gray)
                VStack(alignment: .leading) {
                    Text(s.isActive ? "连续训练 \(s.currentDays) 天" : "连续训练已中断").font(.title3.bold())
                    if let d = s.deadline, s.isActive {
                        Text("最迟 \(d.shortString) 前再训练一次即可保持。允许休息日，连续 3 天不训练会中断。").font(.caption).foregroundStyle(.secondary)
                    } else if s.lastPostDate == nil {
                        Text("完成第一次训练开始连续记录。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("上次连续 \(s.brokenStreakDays) 天。\(s.canRestore ? "中断后一周内可用恢复道具找回。" : "超过一周，无法恢复。")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !s.isActive && s.canRestore {
                HStack {
                    restoreButton("Super Restore", count: profile.superRestore, limit: 30, days: s.brokenStreakDays) { profile.superRestore -= 1 }
                    restoreButton("Mega Restore", count: profile.megaRestore, limit: 60, days: s.brokenStreakDays) { profile.megaRestore -= 1 }
                    restoreButton("Streak Revive", count: profile.streakRevive, limit: .max, days: s.brokenStreakDays) { profile.streakRevive -= 1 }
                }
            }
        }.card()
    }

    private func restoreButton(_ name: String, count: Int, limit: Int, days: Int, consume: @escaping () -> Void) -> some View {
        Button {
            guard let last = streak.lastPostDate else { return }
            consume()
            profile.streakBridgeDays.append(contentsOf: StreakEngine.bridgeDays(from: last))
            context.insert(RewardEvent(kind: .streakRestore, xp: 0, eggs: 0, note: L("使用 %@ 恢复连续记录", name)))
            try? context.save()
            toast = L("已恢复连续记录")
        } label: {
            VStack(spacing: 2) { Text(name).font(.caption2.bold()); Text("×\(count)").font(.caption2) }.frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(count <= 0 || days > limit)
    }

    private var cosmeticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("外观与商店").font(.headline)
                Spacer()
                NavigationLink { ShopView(profile: profile, gsr: gsr, slots: CosmeticSlot.avatarSlots, title: "形象工坊") } label: { Label("形象", systemImage: "wand.and.stars").font(.subheadline.bold()) }
                NavigationLink { ShopView(profile: profile, gsr: gsr) } label: { Label("商店", systemImage: "cart.fill").font(.subheadline.bold()) }
            }
            HStack(spacing: 14) {
                AvatarBadge(name: profile.name, frame: profile.equipped(.frame), size: 60, spec: profile.avatar)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(profile.name).font(.subheadline.bold())
                        TitleTag(cosmetic: profile.equipped(.title))
                    }
                    HStack(spacing: 6) {
                        TierBadge(tier: tier, compact: true)
                        Text("GSR \(gsr)").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        ForEach(CosmeticSlot.badgeSlots) { slot in
                            let item = profile.equipped(slot)
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 3).fill(item.gradient).frame(width: 10, height: 10)
                                Text(item.name).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer()
            }
            Text("用每日训练赚到的 Eggs 购买小人的发型、衣服、配饰、背景，以及头像框、称号、主题色与段位卡；高段位外观需要达到对应段位。").font(.caption2).foregroundStyle(.secondary)
        }.card()
    }

    private var seasonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(season.name).font(.headline)
                Spacer()
                Text("剩余 \(season.daysLeft) 天").font(.caption).foregroundStyle(.secondary)
            }
            Text("本赛季训练 \(seasonDays) 天").font(.subheadline.bold())
            ForEach(Array(Season.milestones.enumerated()), id: \.offset) { _, m in
                let claimed = claims.contains { $0.questID == "season.\(m.days)" && $0.periodKey == season.name }
                HStack {
                    Image(systemName: claimed ? "checkmark.seal.fill" : seasonDays >= m.days ? "gift.fill" : "lock.fill").foregroundStyle(claimed ? .green : seasonDays >= m.days ? .orange : .secondary)
                    Text("\(m.days) 天 · 称号「\(m.title)」+ \(m.eggs) Eggs").font(.caption)
                    Spacer()
                    if !claimed && seasonDays >= m.days {
                        Button("领取") {
                            context.insert(QuestClaim(questID: "season.\(m.days)", periodKey: season.name))
                            profile.eggs += m.eggs
                            context.insert(RewardEvent(kind: .season, xp: 0, eggs: m.eggs, note: L("赛季奖励：%@", m.title)))
                            try? context.save()
                            toast = L("获得称号「%@」 +%lld Eggs", m.title, m.eggs)
                        }.buttonStyle(.borderedProminent).controlSize(.mini)
                    }
                }
            }
            Text("赛季每年 1 月 1 日、5 月 1 日、9 月 1 日重置。").font(.caption2).foregroundStyle(.secondary)
        }.card()
    }

    private var questCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本周额外奖励").font(.headline)
            ForEach(quests) { q in
                let claimed = claims.contains { $0.questID == q.id && $0.periodKey == QuestEngine.periodKey(q) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(q.title).font(.subheadline)
                        Spacer()
                        EggAmount(amount: q.rewardEggs, signed: true).font(.caption2).foregroundStyle(.secondary)
                        Image(systemName: claimed ? "checkmark.circle.fill" : "circle").foregroundStyle(claimed ? .green : .secondary)
                    }
                    ProgressView(value: Double(min(q.progress, q.target)), total: Double(q.target)).tint(claimed ? .green : .accentColor)
                    Text("\(min(q.progress, q.target)) / \(q.target)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.card()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近奖励").font(.headline)
            if rewards.isEmpty { Text("暂无记录").font(.footnote).foregroundStyle(.secondary) }
            ForEach(rewards.filter { $0.eggs != 0 }.prefix(8)) { r in
                HStack {
                    Text(r.note).font(.caption).lineLimit(1)
                    Spacer()
                    Text(r.date.shortString).font(.caption2).foregroundStyle(.secondary)
                    EggAmount(amount: r.eggs, signed: true).font(.caption.monospacedDigit())
                }
            }
        }.card()
    }

    private func autoClaim() {
        var gained = 0
        gained += DailyTrainingEngine.claimIfEarned(profile: profile, workouts: workouts, cardio: cardio, claims: claims, gsr: gsr, context: context)
        for q in quests where q.isComplete {
            let key = QuestEngine.periodKey(q)
            guard !claims.contains(where: { $0.questID == q.id && $0.periodKey == key }) else { continue }
            context.insert(QuestClaim(questID: q.id, periodKey: key))
            context.insert(RewardEvent(kind: .quest, xp: 0, eggs: q.rewardEggs, note: L("本周奖励：%@", q.title)))
            profile.eggs += q.rewardEggs
            gained += q.rewardEggs
        }
        if gained > 0 {
            try? context.save()
            toast = L("获得 +%lld Eggs", gained)
        }
    }
}
