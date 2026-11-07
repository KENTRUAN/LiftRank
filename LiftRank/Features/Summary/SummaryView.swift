import SwiftUI
import SwiftData
import Charts

enum SummaryPeriod: String, CaseIterable, Identifiable {
    case week, month, quarter, year
    var id: String { rawValue }
    var name: String { ["周", "月", "季度", "年"][SummaryPeriod.allCases.firstIndex(of: self)!] }
    var component: Calendar.Component { self == .week ? .weekOfYear : self == .month ? .month : self == .quarter ? .quarter : .year }

    func interval(offset: Int, now: Date = Date()) -> DateInterval {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "zh_CN")
        let ref = cal.date(byAdding: component, value: offset, to: now) ?? now
        if self == .quarter {
            let month = cal.component(.month, from: ref)
            let startMonth = ((month - 1) / 3) * 3 + 1
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: ref), month: startMonth, day: 1))!
            return DateInterval(start: start, end: cal.date(byAdding: .month, value: 3, to: start)!)
        }
        return cal.dateInterval(of: component, for: ref) ?? DateInterval(start: ref, end: ref)
    }

    func label(_ i: DateInterval) -> String {
        let f = DateFormatter()
        switch self {
        case .week: f.dateFormat = "M月d日"; return "\(f.string(from: i.start)) – \(f.string(from: i.end.addingTimeInterval(-1)))"
        case .month: f.dateFormat = "yyyy年M月"; return f.string(from: i.start)
        case .quarter: f.dateFormat = "yyyy年"; return "\(f.string(from: i.start)) 第 \((Calendar.current.component(.month, from: i.start) - 1) / 3 + 1) 季度"
        case .year: f.dateFormat = "yyyy年"; return f.string(from: i.start)
        }
    }
}

struct SummaryStats {
    var workouts = 0
    var sets = 0
    var volumeKg = 0.0
    var durationMin = 0.0
    var cardioSessions = 0
    var cardioMinutes = 0.0
    var cardioKm = 0.0
    var trainingDays = 0
    var prs: [String] = []
    var gsrStart = 0
    var gsrEnd = 0
    var muscleSets: [(MuscleGroup, Int)] = []
    var weightStart: Double?
    var weightEnd: Double?
    var eggs = 0
    var buckets: [(Date, Double)] = []
}

enum SummaryEngine {
    static func compute(period: SummaryPeriod, interval: DateInterval, profile: UserProfile, workouts: [Workout], exercises: [Exercise],
                        cardio: [CardioSession], measurements: [BodyMeasurement], rewards: [RewardEvent]) -> SummaryStats {
        var s = SummaryStats()
        let inRange = workouts.filter { $0.isPublished && interval.contains($0.publishedAt ?? $0.startedAt) }
        s.workouts = inRange.count
        s.sets = inRange.reduce(0) { $0 + $1.completedSets.count }
        s.volumeKg = inRange.reduce(0) { $0 + $1.totalVolumeKg }
        s.durationMin = inRange.reduce(0) { $0 + $1.duration / 60 }
        let c = cardio.filter { interval.contains($0.date) }
        s.cardioSessions = c.count
        s.cardioMinutes = c.reduce(0) { $0 + $1.durationMinutes }
        s.cardioKm = c.reduce(0) { $0 + $1.distanceKm }
        s.trainingDays = StreakEngine.trainingDays(workouts: inRange, cardio: c).count

        var byGroup: [MuscleGroup: Int] = [:]
        for w in inRange { for we in w.exercises { byGroup[we.muscleGroup, default: 0] += we.sets.filter { $0.isCompleted }.count } }
        s.muscleSets = byGroup.sorted { $0.value > $1.value }

        let before = workouts.filter { $0.isPublished && ($0.publishedAt ?? $0.startedAt) < interval.start }
        let through = workouts.filter { $0.isPublished && ($0.publishedAt ?? $0.startedAt) < interval.end }
        s.gsrStart = RankAggregator.overall(muscleScores: RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: before, exercises: exercises, sex: profile.sex)))
        s.gsrEnd = RankAggregator.overall(muscleScores: RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: through, exercises: exercises, sex: profile.sex)))

        // PRs: exercise bests reached inside the period that beat everything before it.
        let oldBest = Dictionary(uniqueKeysWithValues: RankAggregator.exerciseBests(workouts: before, exercises: exercises, sex: profile.sex).map { ($0.exerciseKey, $0.bestE1RM) })
        for b in RankAggregator.exerciseBests(workouts: through, exercises: exercises, sex: profile.sex) where interval.contains(b.date) && b.bestE1RM > (oldBest[b.exerciseKey] ?? 0) + 0.01 {
            s.prs.append("\(b.name) e1RM \(profile.unit.fromKg(b.bestE1RM).fmt(1)) \(profile.unit.label)")
        }

        let weights = measurements.filter { $0.metric == .weight && interval.contains($0.date) }.sorted { $0.date < $1.date }
        s.weightStart = weights.first?.value
        s.weightEnd = weights.last?.value
        s.eggs = rewards.filter { interval.contains($0.date) && $0.eggs > 0 }.reduce(0) { $0 + $1.eggs }

        // Volume buckets: days for a week/month, weeks for a quarter, months for a year.
        let cal = Calendar(identifier: .iso8601)
        let unit: Calendar.Component = period == .week || period == .month ? .day : period == .quarter ? .weekOfYear : .month
        var buckets: [Date: Double] = [:]
        for w in inRange {
            let d = cal.dateInterval(of: unit, for: w.publishedAt ?? w.startedAt)?.start ?? w.startedAt
            buckets[d, default: 0] += w.totalVolumeKg
        }
        s.buckets = buckets.sorted { $0.key < $1.key }
        return s
    }
}

struct SummaryView: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var cardio: [CardioSession]
    @Query private var measurements: [BodyMeasurement]
    @Query private var rewards: [RewardEvent]
    @State private var period: SummaryPeriod = .week
    @State private var offset = 0
    @State private var aiText: String?
    @State private var aiLoading = false
    @State private var aiError: String?

    private var interval: DateInterval { period.interval(offset: offset) }
    private var stats: SummaryStats {
        SummaryEngine.compute(period: period, interval: interval, profile: profile, workouts: workouts, exercises: exercises, cardio: cardio, measurements: measurements, rewards: rewards)
    }

    var body: some View {
        let s = stats
        ScrollView {
            VStack(spacing: 16) {
                Picker("周期", selection: $period) { ForEach(SummaryPeriod.allCases) { Text($0.name).tag($0) } }.pickerStyle(.segmented)
                    .onChange(of: period) { _, _ in offset = 0; aiText = nil }
                HStack {
                    Button { offset -= 1; aiText = nil } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(period.label(interval)).font(.headline)
                    Spacer()
                    Button { offset += 1; aiText = nil } label: { Image(systemName: "chevron.right") }.disabled(offset >= 0)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(title: "训练天数", value: "\(s.trainingDays)")
                    StatTile(title: "力量训练", value: "\(s.workouts) 次", subtitle: "\(s.durationMin.fmt(0)) 分钟")
                    StatTile(title: "总组数", value: "\(s.sets)")
                    StatTile(title: "训练量", value: "\(profile.unit.fromKg(s.volumeKg).fmt(0))", subtitle: profile.unit.label, color: .purple)
                    StatTile(title: "有氧", value: "\(s.cardioMinutes.fmt(0)) 分", subtitle: s.cardioKm > 0 ? "\(s.cardioKm.fmt(1)) km · \(s.cardioSessions) 次" : "\(s.cardioSessions) 次", color: .blue)
                    StatTile(title: "Eggs", value: "+\(s.eggs)", color: .orange)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("段位变化").font(.headline)
                    HStack(spacing: 16) {
                        VStack(spacing: 4) { Text("期初").font(.caption).foregroundStyle(.secondary); Text("\(s.gsrStart)").font(.title2.bold()); TierBadge(tier: RankTier.tier(for: s.gsrStart), compact: true) }
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        VStack(spacing: 4) { Text("期末").font(.caption).foregroundStyle(.secondary); Text("\(s.gsrEnd)").font(.title2.bold()); TierBadge(tier: RankTier.tier(for: s.gsrEnd), compact: true) }
                        Spacer()
                        let delta = s.gsrEnd - s.gsrStart
                        Text(delta >= 0 ? "+\(delta)" : "\(delta)").font(.title3.bold()).foregroundStyle(delta > 0 ? .green : delta < 0 ? .red : .secondary)
                    }
                    if let a = s.weightStart, let b = s.weightEnd {
                        Text("体重 \(profile.unit.fromKg(a).fmt(1)) → \(profile.unit.fromKg(b).fmt(1)) \(profile.unit.label)（\((profile.unit.fromKg(b) - profile.unit.fromKg(a)) >= 0 ? "+" : "")\((profile.unit.fromKg(b) - profile.unit.fromKg(a)).fmt(1))）").font(.caption).foregroundStyle(.secondary)
                    }
                }.card()

                if !s.buckets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("训练量分布").font(.headline)
                        Chart(s.buckets, id: \.0) { b in
                            BarMark(x: .value("时间", b.0, unit: period == .year ? .month : period == .quarter ? .weekOfYear : .day), y: .value("kg", profile.unit.fromKg(b.1)))
                                .foregroundStyle(Color.accentColor.gradient)
                        }.frame(height: 140)
                    }.card()
                }

                if !s.muscleSets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("肌群组数").font(.headline)
                        Chart(s.muscleSets, id: \.0) { m in
                            BarMark(x: .value("组", m.1), y: .value("肌群", m.0.name)).foregroundStyle(by: .value("肌群", m.0.name))
                        }
                        .chartLegend(.hidden)
                        .frame(height: CGFloat(max(100, s.muscleSets.count * 24)))
                    }.card()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("个人纪录 PR · \(s.prs.count)").font(.headline)
                    if s.prs.isEmpty { Text("本周期没有刷新纪录。").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(s.prs, id: \.self) { Label($0, systemImage: "trophy.fill").font(.subheadline).foregroundStyle(.orange) }
                }.card()

                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("AI 点评").font(.headline); Spacer(); if aiLoading { ProgressView() } }
                    if let aiText { Text(markdown(aiText)).font(.subheadline) }
                    else { Text(profile.isAIConfigured ? "让 AI 根据本周期数据给出总结与下一步建议。" : "配置 AI 后可生成总结点评（我的 → AI 助手）。").font(.footnote).foregroundStyle(.secondary) }
                    if let aiError { Text(aiError).font(.footnote).foregroundStyle(.red) }
                    Button { generateAI(s) } label: { Label(aiText == nil ? "生成点评" : "重新生成", systemImage: "sparkles").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).disabled(aiLoading || !profile.isAIConfigured)
                }.card()
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("训练总结")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }

    private func generateAI(_ s: SummaryStats) {
        guard let config = profile.aiConfig else { return }
        aiLoading = true; aiError = nil
        let data = """
        周期：\(period.label(interval))。训练天数 \(s.trainingDays)，力量训练 \(s.workouts) 次 \(s.sets) 组，训练量 \(s.volumeKg.fmt(0)) kg，时长 \(s.durationMin.fmt(0)) 分钟。
        有氧 \(s.cardioSessions) 次 \(s.cardioMinutes.fmt(0)) 分钟 \(s.cardioKm.fmt(1)) km。GSR \(s.gsrStart) → \(s.gsrEnd)。
        肌群组数：\(s.muscleSets.map { "\($0.0.name) \($0.1)" }.joined(separator: "，"))。
        PR：\(s.prs.isEmpty ? "无" : s.prs.joined(separator: "；"))。
        体重：\(s.weightStart.map { $0.fmt(1) } ?? "—") → \(s.weightEnd.map { $0.fmt(1) } ?? "—") kg。
        用户目标 \(profile.planGoal.name)，经验 \(profile.planExperience.name)。
        """
        Task {
            do {
                aiText = try await AIService.complete(system: "你是力量训练教练。根据给定周期数据，用简体中文写一段 150–250 字的总结：先肯定亮点，再指出 1–2 个不足，最后给出下一周期的 3 条具体建议。使用 Markdown 粗体与列表，不要用标题符号。", messages: [AIChatMessage(role: .user, text: data)], config: config, maxTokens: 1024)
            } catch { aiError = error.localizedDescription }
            aiLoading = false
        }
    }
}
