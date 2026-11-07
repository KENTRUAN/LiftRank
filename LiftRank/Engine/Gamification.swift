import Foundation

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
}

struct Season {
    let index: Int
    let year: Int
    let start: Date
    let end: Date
    var name: String { "\(year) 年第 \(index) 赛季" }
    var daysLeft: Int { max(0, end.daysSince(Date())) }
    static let milestones: [(xp: Int, eggs: Int, title: String)] = [
        (300, 20, "赛季新秀"), (800, 40, "稳定输出"), (1500, 80, "赛季主力"), (2500, 150, "赛季王者")
    ]
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

enum XPEngine {
    static func xpToNext(level: Int) -> Int { 100 + 50 * (level - 1) }

    static func level(totalXP: Int) -> (level: Int, progress: Int, needed: Int) {
        var level = 1
        var remaining = totalXP
        while remaining >= xpToNext(level: level) {
            remaining -= xpToNext(level: level)
            level += 1
        }
        return (level, remaining, xpToNext(level: level))
    }

    static func workoutXP(sets: Int) -> Int { 50 + 2 * sets }
    static let firstOfDayXP = 50
    /// Eggs for the first published workout of the day; longer streaks pay more.
    static func firstOfDayEggs(streakDays: Int) -> Int { 5 + min(streakDays, 30) / 3 }
}

struct Quest: Identifiable {
    enum Period { case daily, weekly }
    let id: String
    let title: String
    let period: Period
    let target: Int
    let progress: Int
    let rewardXP: Int
    let rewardEggs: Int
    var isComplete: Bool { progress >= target }
}

enum QuestEngine {
    static func quests(workouts: [Workout], measurements: [BodyMeasurement], foods: [FoodEntry], today: Date = Date()) -> [Quest] {
        let todayKey = today.dayKey
        let weekKey = today.weekKey
        let published = workouts.filter { $0.isPublished }
        let todays = published.filter { ($0.publishedAt ?? $0.startedAt).dayKey == todayKey }
        let weeks = published.filter { ($0.publishedAt ?? $0.startedAt).weekKey == weekKey }
        let todaySets = todays.reduce(0) { $0 + $1.completedSets.count }
        let weekVolume = Int(weeks.reduce(0) { $0 + $1.totalVolumeKg })
        let loggedBody = measurements.contains { $0.date.dayKey == todayKey }
        let loggedFood = foods.contains { $0.date.dayKey == todayKey }
        return [
            Quest(id: "d.workout", title: "发布一次训练", period: .daily, target: 1, progress: todays.count, rewardXP: 30, rewardEggs: 3),
            Quest(id: "d.sets", title: "完成 12 组", period: .daily, target: 12, progress: todaySets, rewardXP: 20, rewardEggs: 2),
            Quest(id: "d.body", title: "记录一项身体数据", period: .daily, target: 1, progress: loggedBody ? 1 : 0, rewardXP: 10, rewardEggs: 1),
            Quest(id: "d.food", title: "记录一餐饮食", period: .daily, target: 1, progress: loggedFood ? 1 : 0, rewardXP: 10, rewardEggs: 1),
            Quest(id: "w.workouts", title: "本周训练 3 次", period: .weekly, target: 3, progress: weeks.count, rewardXP: 120, rewardEggs: 15),
            Quest(id: "w.volume", title: "本周训练量 10,000 kg", period: .weekly, target: 10000, progress: weekVolume, rewardXP: 100, rewardEggs: 10),
            Quest(id: "w.sets", title: "本周完成 60 组", period: .weekly, target: 60, progress: weeks.reduce(0) { $0 + $1.completedSets.count }, rewardXP: 80, rewardEggs: 8),
        ]
    }

    static func periodKey(_ q: Quest, today: Date = Date()) -> String { q.period == .daily ? today.dayKey : today.weekKey }
}
