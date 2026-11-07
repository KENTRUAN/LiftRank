import SwiftUI
import SwiftData

struct QuestsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Query private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]
    @Query private var foods: [FoodEntry]
    @Query private var claims: [QuestClaim]
    @Query(sort: \RewardEvent.date, order: .reverse) private var rewards: [RewardEvent]
    @State private var toast: String?

    private var streak: StreakInfo {
        let posts = Set(workouts.filter { $0.isPublished }.map { ($0.publishedAt ?? $0.startedAt).startOfDay })
        let bridge = Set(profile.streakBridgeDays.compactMap { WorkoutPublisher.dayKeyToDate($0) })
        return StreakEngine.compute(postDays: posts, bridgeDays: bridge)
    }
    private var season: Season { SeasonEngine.current() }
    private var seasonXP: Int { rewards.filter { $0.date >= season.start && $0.date < season.end && $0.kind != .season }.reduce(0) { $0 + $1.xp } }
    private var quests: [Quest] { QuestEngine.quests(workouts: workouts, measurements: measurements, foods: foods) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    streakCard
                    levelCard
                    seasonCard
                    questSection("每日任务", quests.filter { $0.period == .daily })
                    questSection("每周任务", quests.filter { $0.period == .weekly })
                    shopCard
                    historyCard
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("任务与奖励")
            .onAppear(perform: autoClaim)
            .overlay(alignment: .top) {
                if let toast {
                    Text(toast).font(.subheadline.bold()).padding(12).background(.regularMaterial, in: Capsule()).padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private var streakCard: some View {
        let s = streak
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "flame.fill").font(.largeTitle).foregroundStyle(s.isActive ? .orange : .gray)
                VStack(alignment: .leading) {
                    Text(s.isActive ? "连续记录 \(s.currentDays) 天" : "连续记录已中断").font(.title3.bold())
                    if let d = s.deadline, s.isActive {
                        Text("最迟 \(d.shortString) 前再次发布训练即可保持。允许休息日，连续 3 天不发布会中断。").font(.caption).foregroundStyle(.secondary)
                    } else if s.lastPostDate == nil {
                        Text("发布第一次训练开始连续记录。").font(.caption).foregroundStyle(.secondary)
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
            context.insert(RewardEvent(kind: .streakRestore, xp: 0, eggs: 0, note: "使用 \(name) 恢复连续记录"))
            try? context.save()
            show("已恢复连续记录")
        } label: {
            VStack(spacing: 2) { Text(name).font(.caption2.bold()); Text("×\(count)").font(.caption2) }.frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(count <= 0 || days > limit)
    }

    private var levelCard: some View {
        let lv = XPEngine.level(totalXP: profile.totalXP)
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("等级 \(lv.level)").font(.title3.bold())
                ProgressView(value: Double(lv.progress), total: Double(lv.needed))
                Text("\(lv.progress) / \(lv.needed) XP · 累计 \(profile.totalXP) XP").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                EggIcon(size: 36)
                Text("\(profile.eggs) Eggs").font(.caption.bold())
            }
        }.card()
    }

    private var seasonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(season.name).font(.headline)
                Spacer()
                Text("剩余 \(season.daysLeft) 天").font(.caption).foregroundStyle(.secondary)
            }
            Text("赛季 XP \(seasonXP)").font(.subheadline.bold())
            ForEach(Array(Season.milestones.enumerated()), id: \.offset) { _, m in
                let claimed = claims.contains { $0.questID == "season.\(m.xp)" && $0.periodKey == season.name }
                HStack {
                    Image(systemName: claimed ? "checkmark.seal.fill" : seasonXP >= m.xp ? "gift.fill" : "lock.fill").foregroundStyle(claimed ? .green : seasonXP >= m.xp ? .orange : .secondary)
                    Text("\(m.xp) XP · 称号「\(m.title)」+ \(m.eggs) Eggs").font(.caption)
                    Spacer()
                    if !claimed && seasonXP >= m.xp {
                        Button("领取") {
                            context.insert(QuestClaim(questID: "season.\(m.xp)", periodKey: season.name))
                            profile.eggs += m.eggs
                            context.insert(RewardEvent(kind: .season, xp: 0, eggs: m.eggs, note: "赛季奖励：\(m.title)"))
                            try? context.save()
                            show("获得称号「\(m.title)」 +\(m.eggs) Eggs")
                        }.buttonStyle(.borderedProminent).controlSize(.mini)
                    }
                }
            }
            Text("赛季每年 1 月 1 日、5 月 1 日、9 月 1 日重置。").font(.caption2).foregroundStyle(.secondary)
        }.card()
    }

    private func questSection(_ title: String, _ list: [Quest]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(list) { q in
                let claimed = claims.contains { $0.questID == q.id && $0.periodKey == QuestEngine.periodKey(q) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(q.title).font(.subheadline)
                        Spacer()
                        HStack(spacing: 2) { Text("+\(q.rewardXP) XP ·"); EggAmount(amount: q.rewardEggs, signed: true) }.font(.caption2).foregroundStyle(.secondary)
                        Image(systemName: claimed ? "checkmark.circle.fill" : "circle").foregroundStyle(claimed ? .green : .secondary)
                    }
                    ProgressView(value: Double(min(q.progress, q.target)), total: Double(q.target)).tint(claimed ? .green : .accentColor)
                    Text("\(min(q.progress, q.target)) / \(q.target)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.card()
    }

    private var shopCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("商店").font(.headline)
            shopRow("Super Restore", price: 100, desc: "恢复最长 30 天的连续记录") { profile.superRestore += 1 }
            shopRow("Mega Restore", price: 200, desc: "恢复最长 60 天的连续记录") { profile.megaRestore += 1 }
            shopRow("Streak Revive", price: 400, desc: "恢复任意长度的连续记录") { profile.streakRevive += 1 }
            Text("Eggs 通过每日首次发布训练、任务与赛季获得；连续记录越长，每日收益越高。虚拟物品不可兑换现金。").font(.caption2).foregroundStyle(.secondary)
        }.card()
    }

    private func shopRow(_ name: String, price: Int, desc: String, buy: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) { Text(name).font(.subheadline.bold()); Text(desc).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button { 
                guard profile.eggs >= price else { show("Eggs 不足"); return }
                profile.eggs -= price
                buy()
                context.insert(RewardEvent(kind: .shop, xp: 0, eggs: -price, note: "购买 \(name)"))
                try? context.save()
                show("已购买 \(name)")
            } label: { EggAmount(amount: price) }.buttonStyle(.bordered).controlSize(.small).disabled(profile.eggs < price)
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近奖励").font(.headline)
            if rewards.isEmpty { Text("暂无记录").font(.footnote).foregroundStyle(.secondary) }
            ForEach(rewards.prefix(8)) { r in
                HStack {
                    Text(r.note).font(.caption).lineLimit(1)
                    Spacer()
                    if r.xp != 0 { Text("\(r.xp > 0 ? "+" : "")\(r.xp) XP").font(.caption.monospacedDigit()) }
                    if r.eggs != 0 { EggAmount(amount: r.eggs, signed: true).font(.caption.monospacedDigit()) }
                }
            }
        }.card()
    }

    private func autoClaim() {
        var gained = (xp: 0, eggs: 0)
        for q in quests where q.isComplete {
            let key = QuestEngine.periodKey(q)
            guard !claims.contains(where: { $0.questID == q.id && $0.periodKey == key }) else { continue }
            context.insert(QuestClaim(questID: q.id, periodKey: key))
            context.insert(RewardEvent(kind: .quest, xp: q.rewardXP, eggs: q.rewardEggs, note: "任务完成：\(q.title)"))
            profile.totalXP += q.rewardXP
            profile.eggs += q.rewardEggs
            gained.xp += q.rewardXP; gained.eggs += q.rewardEggs
        }
        if gained.xp > 0 || gained.eggs > 0 {
            try? context.save()
            show("任务完成 +\(gained.xp) XP +\(gained.eggs) Eggs")
        }
    }

    private func show(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { withAnimation { toast = nil } }
    }
}
