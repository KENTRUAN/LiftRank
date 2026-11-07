import SwiftUI
import SwiftData

/// Compiles the user's data into a compact text block for the model.
enum FitnessDataSummary {
    static func build(profile: UserProfile, workouts: [Workout], exercises: [Exercise], cardio: [CardioSession],
                      measurements: [BodyMeasurement], foods: [FoodEntry], days: Int = 28) -> String {
        let since = Date().adding(days: -days)
        var out: [String] = []
        out.append("## 用户")
        out.append("\(profile.sex.label)，\(profile.age) 岁，身高 \(profile.heightCm.fmt(0)) cm，体重 \(profile.bodyweightKg.fmt(1)) kg，活动水平 \(profile.activityLevel.name)，饮食目标 \(profile.nutritionGoal.name)。")

        let bests = RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)
        let muscles = RankAggregator.muscleScores(bests: bests)
        let gsr = RankAggregator.overall(muscleScores: muscles)
        out.append("## 力量段位")
        out.append("总体评分 GSR \(gsr)，当前已经是 \(RankTier.tier(for: gsr).name) 段位。评分 1–1000，按 e1RM/体重与性别曲线换算。")
        let muscleLine = MuscleGroup.rankable.compactMap { g in muscles[g].map { "\(g.name) \($0)" } }.joined(separator: "，")
        if !muscleLine.isEmpty { out.append("肌群评分：\(muscleLine)。") }
        if !bests.isEmpty { out.append("动作最佳：" + bests.prefix(10).map { "\($0.name) e1RM \($0.bestE1RM.fmt(1)) kg（\($0.bestScore)）" }.joined(separator: "，")) }

        let recent = workouts.filter { $0.isPublished && ($0.publishedAt ?? $0.startedAt) >= since }
        out.append("## 最近 \(days) 天力量训练")
        out.append("共 \(recent.count) 次，总训练量 \(recent.reduce(0) { $0 + $1.totalVolumeKg }.fmt(0)) kg，\(recent.reduce(0) { $0 + $1.completedSets.count }) 组。")
        if let earliest = recent.map({ $0.publishedAt ?? $0.startedAt }).min(),
           let latest = recent.map({ $0.publishedAt ?? $0.startedAt }).max() {
            out.append("本窗口实际训练记录日期范围：\(earliest.shortString)–\(latest.shortString)。")
        }
        var setsByGroup: [MuscleGroup: Int] = [:]
        for w in recent { for we in w.exercises { setsByGroup[we.muscleGroup, default: 0] += we.sets.filter { $0.isCompleted }.count } }
        if !setsByGroup.isEmpty { out.append("各肌群组数：" + setsByGroup.sorted { $0.value > $1.value }.map { "\($0.key.name) \($0.value)" }.joined(separator: "，")) }
        for w in recent.sorted(by: { ($0.publishedAt ?? $0.startedAt) > ($1.publishedAt ?? $1.startedAt) }).prefix(6) {
            let items = w.sortedExercises.map { we in
                let top = we.sets.filter { $0.isCompleted }.max { $0.weightKg * Double($0.reps) < $1.weightKg * Double($1.reps) }
                return "\(we.exerciseName) \(we.sets.filter { $0.isCompleted }.count) 组" + (top.map { " 最重 \($0.weightKg.fmt(1))kg×\($0.reps)" } ?? "")
            }.joined(separator: "；")
            out.append("- \((w.publishedAt ?? w.startedAt).shortString) \(w.title)：\(items)")
        }

        let recentCardio = cardio.filter { $0.date >= since }
        out.append("## 最近 \(days) 天有氧")
        if recentCardio.isEmpty { out.append("无记录。") } else {
            out.append("共 \(recentCardio.count) 次，\(recentCardio.reduce(0) { $0 + $1.durationMinutes }.fmt(0)) 分钟，\(recentCardio.reduce(0) { $0 + $1.distanceKm }.fmt(1)) km，消耗约 \(recentCardio.reduce(0) { $0 + $1.calories }.fmt(0)) kcal。")
            let byType = Dictionary(grouping: recentCardio, by: { $0.type }).map { "\($0.key.name) \($0.value.count) 次" }.joined(separator: "，")
            out.append(byType)
        }

        out.append("## 身体数据")
        for metric in [BodyMetric.weight, .bodyFat, .waist] {
            let values = measurements.filter { $0.metric == metric && $0.date >= since }.sorted { $0.date < $1.date }
            if let first = values.first, let last = values.last, values.count >= 2 {
                out.append("\(metric.name)：\(first.date.shortString) \(first.value.fmt(1)) \(metric.unit) → \(last.date.shortString) \(last.value.fmt(1)) \(metric.unit)（共 \(values.count) 次记录）。")
            }
        }
        var latest: [BodyMetric: BodyMeasurement] = [:]
        for m in measurements.sorted(by: { $0.date > $1.date }) where latest[m.metric] == nil && m.metric != .weight { latest[m.metric] = m }
        if !latest.isEmpty { out.append("最新围度：" + latest.values.sorted { $0.metric.name < $1.metric.name }.map { "\($0.metric.name) \($0.value.fmt(1))\($0.metric.unit)" }.joined(separator: "，")) }

        let recentFood = foods.filter { $0.date >= Date().adding(days: -7) }
        out.append("## 最近 7 天饮食")
        if recentFood.isEmpty { out.append("无记录。") } else {
            let daysLogged = Set(recentFood.map { $0.date.dayKey }).count
            out.append("有餐食记录的天数：\(daysLogged)/7；共 \(recentFood.count) 条。没有全天记录完整性的标记，无法判断是否达到每日摄入目标。")
            if daysLogged <= 2 {
                out.append("有效记录太少，不提供摄入估算；建议补记几天完整饮食后再评估。")
            } else {
                for entry in recentFood.sorted(by: { $0.date > $1.date }).prefix(8) {
                    out.append("- \(entry.date.shortString) \(entry.meal.name)：\(entry.name)（仅一条记录）。")
                }
            }
        }
        return out.joined(separator: "\n")
    }
}

struct BodyAnalysisView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var cardio: [CardioSession]
    @Query private var measurements: [BodyMeasurement]
    @Query private var foods: [FoodEntry]
    @State private var loading = false
    @State private var error: String?
    @State private var showData = false

    private var summary: String { FitnessDataSummary.build(profile: profile, workouts: workouts, exercises: exercises, cardio: cardio, measurements: measurements, foods: foods) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !AIBackend.isConfigured {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AI 服务暂未开通", systemImage: "exclamationmark.triangle.fill").font(.headline)
                        Text(AIBackend.unavailableHint).font(.footnote).foregroundStyle(.secondary)
                    }.card()
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("综合分析").font(.headline)
                        Spacer()
                        if let at = profile.lastBodyAnalysisAt { Text(at.mediumString).font(.caption2).foregroundStyle(.secondary) }
                    }
                    if loading {
                        HStack { ProgressView(); Text("正在分析训练、身体与饮食数据…").font(.footnote).foregroundStyle(.secondary) }
                    } else if profile.lastBodyAnalysis.isEmpty {
                        Text("AI 会结合段位、训练量、有氧、体重趋势与饮食，给出优势短板、风险提示与下一步建议。").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(markdown(profile.lastBodyAnalysis)).font(.subheadline)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button { analyze() } label: {
                        Label(profile.lastBodyAnalysis.isEmpty ? "生成分析" : "重新分析", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).disabled(loading || !AIBackend.isConfigured)
                }.card()
                DisclosureGroup("发送给模型的数据", isExpanded: $showData) {
                    Text(summary).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }.card()
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("AI 身体分析")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func analyze() {
        guard let config = AIBackend.config else { return }
        loading = true; error = nil
        let data = summary
        let system = """
        你是一位专业的力量训练与营养教练。根据用户提供的训练、段位、有氧、身体与饮食数据，用简体中文给出综合分析。
        要求：结构化、具体、可执行；分为「总体评价」「力量结构与短板」「身体成分与体重趋势」「饮食与恢复」「未来 4 周建议」五部分，每部分 2–4 条要点。
        引用具体日期、动作或数值支持主要判断。「身体成分与体重趋势」只描述实际测量值、日期和数据缺口，不解释体重变化原因。体脂记录不足时直接写无法判断体脂趋势。若饮食有效记录只有 0–2 天，「饮食与恢复」只写缺了哪些记录和怎么补记，不推断当前饮食质量、恢复状态、蛋白质或热量。即使条目较多也不能断定全天饮食不足或解释体重变化。力量段位与肌群组数反映记录表现，不等同于肌肉量。指出缺的数据，不做医疗诊断。使用 Markdown 的粗体与列表，不要使用标题符号 #。
        """
        Task {
            do {
                let text = try await AIService.complete(system: system, messages: [AIChatMessage(role: .user, text: data)], config: config, maxTokens: 4096)
                let previous = (profile.lastBodyAnalysis, profile.lastBodyAnalysisAt)
                profile.lastBodyAnalysis = text
                profile.lastBodyAnalysisAt = Date()
                do {
                    try context.save()
                } catch {
                    (profile.lastBodyAnalysis, profile.lastBodyAnalysisAt) = previous
                    throw error
                }
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}
