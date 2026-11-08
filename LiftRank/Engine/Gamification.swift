import Foundation
import SwiftData

struct StreakInfo {
    var currentDays: Int
    var isActive: Bool
    var lastPostDate: Date?
    var deadline: Date?
    var brokenStreakDays: Int
    var brokenAt: Date?
    var canRestore: Bool
}

enum StreakEngine {
    /// A streak survives up to two rest days: posting Monday requires the next post by Thursday.
    static let graceDays = 3

    static func compute(postDays: Set<Date>, bridgeDays: Set<Date>, today: Date = Date()) -> StreakInfo {
        let days = Array(postDays.union(bridgeDays)).map(\.startOfDay).sorted()
        guard let last = days.last else {
            return StreakInfo(currentDays: 0, isActive: false, lastPostDate: nil, deadline: nil, brokenStreakDays: 0, brokenAt: nil, canRestore: false)
        }
        // Walk back from the last post, chaining days within the grace window.
        var start = last
        var i = days.count - 1
        while i > 0 {
            if days[i].daysSince(days[i - 1]) <= graceDays { start = days[i - 1]; i -= 1 } else { break }
        }
        let todayStart = today.startOfDay
        let gap = todayStart.daysSince(last)
        let realLast = postDays.map(\.startOfDay).max() ?? last
        if gap <= graceDays {
            return StreakInfo(currentDays: todayStart.daysSince(start) + 1, isActive: true, lastPostDate: realLast,
                              deadline: last.adding(days: graceDays), brokenStreakDays: 0, brokenAt: nil, canRestore: false)
        }
        let brokenAt = last.adding(days: graceDays + 1)
        let brokenDays = last.daysSince(start) + 1
        return StreakInfo(currentDays: 0, isActive: false, lastPostDate: realLast, deadline: nil,
                          brokenStreakDays: brokenDays, brokenAt: brokenAt,
                          canRestore: todayStart.daysSince(brokenAt) <= 7 && brokenDays > 0)
    }

    /// Bridge days needed to re-connect the broken chain up to today.
    static func bridgeDays(from last: Date, to today: Date = Date()) -> [String] {
        var out: [String] = []
        var d = last.startOfDay.adding(days: graceDays)
        while d.startOfDay <= today.startOfDay {
            out.append(d.dayKey)
            d = d.adding(days: graceDays)
        }
        return out
    }

    /// Days on which training was posted (strength workouts and cardio both count).
    static func trainingDays(workouts: [Workout], cardio: [CardioSession]) -> Set<Date> {
        var days = Set(workouts.filter { $0.isPublished }.map { ($0.publishedAt ?? $0.startedAt).startOfDay })
        for c in cardio where c.durationMinutes >= DailyTrainingEngine.minCardioMinutes { days.insert(c.date.startOfDay) }
        return days
    }

    static func current(profile: UserProfile, workouts: [Workout], cardio: [CardioSession], today: Date = Date()) -> StreakInfo {
        let bridge = Set(profile.streakBridgeDays.compactMap { WorkoutPublisher.dayKeyToDate($0) })
        return compute(postDays: trainingDays(workouts: workouts, cardio: cardio), bridgeDays: bridge, today: today)
    }
}

struct Season {
    let index: Int
    let year: Int
    let start: Date
    let end: Date
    var name: String { L("%lld 年第 %lld 赛季", year, index) }
    var daysLeft: Int { max(0, end.daysSince(Date())) }
    /// Milestones are counted in training days within the season.
    static var milestones: [(days: Int, eggs: Int, title: String)] {
        [(5, 30, L("赛季新秀")), (12, 60, L("稳定输出")), (24, 120, L("赛季主力")), (40, 200, L("赛季王者"))]
    }
}

enum SeasonEngine {
    /// Seasons reset on Jan 1, May 1 and Sep 1.
    static func current(_ date: Date = Date()) -> Season {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let (idx, startMonth, endMonth, endYear): (Int, Int, Int, Int) = month < 5 ? (1, 1, 5, year) : month < 9 ? (2, 5, 9, year) : (3, 9, 1, year + 1)
        let start = cal.date(from: DateComponents(year: year, month: startMonth, day: 1))!
        let end = cal.date(from: DateComponents(year: endYear, month: endMonth, day: 1))!
        return Season(index: idx, year: year, start: start, end: end)
    }
}

struct DailyTrainingStatus {
    var dayKey: String
    var strengthWorkouts: Int
    var cardioMinutes: Double
    var isComplete: Bool
    var reward: Int
    var claimed: Bool
}

/// The daily training reward: one Egg payout per day for training, scaled by rank tier and streak.
enum DailyTrainingEngine {
    static let questID = "daily.training"
    static let minCardioMinutes = 10.0

    static func reward(tier: RankTier, streakDays: Int) -> Int {
        // Higher tiers earn more, so the shop stays tied to the rank system.
        10 + tier.rawValue * 3 + min(streakDays, 30) / 3
    }

    static func status(profile: UserProfile, workouts: [Workout], cardio: [CardioSession], claims: [QuestClaim], gsr: Int, today: Date = Date()) -> DailyTrainingStatus {
        let key = today.dayKey
        let strength = workouts.filter { $0.isPublished && $0.activity == .strength && ($0.publishedAt ?? $0.startedAt).dayKey == key }.count
        let minutes = cardio.filter { $0.date.dayKey == key }.reduce(0) { $0 + $1.durationMinutes }
        let streak = StreakEngine.current(profile: profile, workouts: workouts, cardio: cardio, today: today)
        let complete = strength > 0 || minutes >= minCardioMinutes
        return DailyTrainingStatus(dayKey: key, strengthWorkouts: strength, cardioMinutes: minutes, isComplete: complete,
                                   reward: reward(tier: RankTier.tier(for: gsr), streakDays: max(streak.currentDays, 1)),
                                   claimed: claims.contains { $0.questID == questID && $0.periodKey == key })
    }

    /// Pays the daily reward once per day. Returns the Eggs granted (0 when nothing new).
    @discardableResult
    static func claimIfEarned(profile: UserProfile, workouts: [Workout], cardio: [CardioSession], claims: [QuestClaim], gsr: Int, context: ModelContext, today: Date = Date(), save: Bool = true) -> Int {
        let s = status(profile: profile, workouts: workouts, cardio: cardio, claims: claims, gsr: gsr, today: today)
        guard s.isComplete, !s.claimed else { return 0 }
        context.insert(QuestClaim(questID: questID, periodKey: s.dayKey))
        context.insert(RewardEvent(date: today, kind: .dailyTraining, xp: 0, eggs: s.reward, note: L("完成今日训练（%@ 段位加成）", RankTier.tier(for: gsr).name)))
        profile.eggs += s.reward
        if save { try? context.save() }
        return s.reward
    }
}

struct Quest: Identifiable {
    let id: String
    let title: String
    let target: Int
    let progress: Int
    let rewardEggs: Int
    var isComplete: Bool { progress >= target }
}

/// Weekly bonus quests. Eggs only; the level system was removed in favour of rank-linked rewards.
enum QuestEngine {
    static func weeklyQuests(workouts: [Workout], cardio: [CardioSession], today: Date = Date()) -> [Quest] {
        let weekKey = today.weekKey
        let weeks = workouts.filter { $0.isPublished && ($0.publishedAt ?? $0.startedAt).weekKey == weekKey }
        let cardioWeek = cardio.filter { $0.date.weekKey == weekKey }
        let weekVolume = Int(weeks.reduce(0) { $0 + $1.totalVolumeKg })
        let trainingDays = Set(weeks.map { ($0.publishedAt ?? $0.startedAt).dayKey } + cardioWeek.filter { $0.durationMinutes >= DailyTrainingEngine.minCardioMinutes }.map { $0.date.dayKey }).count
        return [
            Quest(id: "w.days", title: L("本周训练 3 天"), target: 3, progress: trainingDays, rewardEggs: 25),
            Quest(id: "w.volume", title: L("本周训练量 10,000 kg"), target: 10000, progress: weekVolume, rewardEggs: 20),
            Quest(id: "w.sets", title: L("本周完成 60 组"), target: 60, progress: weeks.reduce(0) { $0 + $1.completedSets.count }, rewardEggs: 15),
            Quest(id: "w.cardio", title: L("本周有氧 90 分钟"), target: 90, progress: Int(cardioWeek.reduce(0) { $0 + $1.durationMinutes }), rewardEggs: 20),
        ]
    }

    static func periodKey(_ q: Quest, today: Date = Date()) -> String { today.weekKey }
}
