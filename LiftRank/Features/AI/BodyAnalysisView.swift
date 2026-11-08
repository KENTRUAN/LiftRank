import SwiftUI
import SwiftData

/// Compiles the user's data into a compact text block for the model.
enum FitnessDataSummary {
    static func build(profile: UserProfile, workouts: [Workout], exercises: [Exercise], cardio: [CardioSession],
                      measurements: [BodyMeasurement], foods: [FoodEntry], days: Int = 28) -> String {
        let since = Date().adding(days: -days)
        let separator = AppLanguage.current.isEnglish ? ", " : "，"
        var out: [String] = []
        out.append(L("## 用户"))
        out.append(L("%@，%lld 岁，身高 %@ cm，体重 %@ kg，活动水平 %@，饮食目标 %@。", profile.sex.label, profile.age, profile.heightCm.fmt(0), profile.bodyweightKg.fmt(1), profile.activityLevel.name, profile.nutritionGoal.name))

        let bests = RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)
        let muscles = RankAggregator.muscleScores(bests: bests)
        let gsr = RankAggregator.overall(muscleScores: muscles)
        out.append(L("## 力量段位"))
        out.append(L("总体评分 GSR %lld，当前为 %@ 段位。评分 1–1000，按 e1RM/体重与性别曲线换算。", gsr, RankTier.tier(for: gsr).displayName))
        let muscleLine = MuscleGroup.rankable.compactMap { g in muscles[g].map { "\(g.name) \($0)" } }.joined(separator: separator)
        if !muscleLine.isEmpty { out.append(L("肌群评分：%@。", muscleLine)) }
        if !bests.isEmpty { out.append(L("动作最佳：%@", bests.prefix(10).map { "\(ExerciseNames.display($0.name)) e1RM \($0.bestE1RM.fmt(1)) kg (\($0.bestScore))" }.joined(separator: separator))) }

        let recent = workouts.filter { $0.isPublished && $0.activity == .strength && ($0.publishedAt ?? $0.startedAt) >= since }
        out.append(L("## 最近 %lld 天力量训练", days))
        out.append(L("共 %lld 次，总训练量 %@ kg，%lld 组。", recent.count, recent.reduce(0) { $0 + $1.totalVolumeKg }.fmt(0), recent.reduce(0) { $0 + $1.completedSets.count }))
        if let earliest = recent.map({ $0.publishedAt ?? $0.startedAt }).min(),
           let latest = recent.map({ $0.publishedAt ?? $0.startedAt }).max() {
            out.append(L("本窗口实际训练记录日期范围：%@–%@。", earliest.shortString, latest.shortString))
        }
        var setsByGroup: [MuscleGroup: Int] = [:]
        for w in recent { for we in w.exercises { setsByGroup[we.muscleGroup, default: 0] += we.sets.filter { $0.isCompleted }.count } }
        if !setsByGroup.isEmpty { out.append(L("各肌群组数：%@", setsByGroup.sorted { $0.value > $1.value }.map { "\($0.key.name) \($0.value)" }.joined(separator: separator))) }
        for w in recent.sorted(by: { ($0.publishedAt ?? $0.startedAt) > ($1.publishedAt ?? $1.startedAt) }).prefix(6) {
            let items = w.sortedExercises.map { we in
                let top = we.sets.filter { $0.isCompleted }.max { $0.weightKg * Double($0.reps) < $1.weightKg * Double($1.reps) }
                return L("%@ · %lld 组", ExerciseNames.display(we.exerciseName), we.sets.filter { $0.isCompleted }.count) + (top.map { L(" · 最重 %@ kg × %lld", $0.weightKg.fmt(1), $0.reps) } ?? "")
            }.joined(separator: AppLanguage.current.isEnglish ? "; " : "；")
            out.append("- \((w.publishedAt ?? w.startedAt).shortString) \(WorkoutLabels.title(w.title)): \(items)")
        }

        let recentCardio = cardio.filter { $0.date >= since }
        out.append(L("## 最近 %lld 天有氧", days))
        if recentCardio.isEmpty { out.append(L("无记录。")) } else {
            out.append(L("共 %lld 次，%@ 分钟，%@ km，消耗约 %@ kcal。", recentCardio.count, recentCardio.reduce(0) { $0 + $1.durationMinutes }.fmt(0), recentCardio.reduce(0) { $0 + $1.distanceKm }.fmt(1), recentCardio.reduce(0) { $0 + $1.calories }.fmt(0)))
            let byType = Dictionary(grouping: recentCardio, by: { $0.type }).map { L("%@ · %lld 次", $0.key.name, $0.value.count) }.joined(separator: separator)
            out.append(byType)
        }

        out.append(L("## 身体数据"))
        for metric in [BodyMetric.weight, .bodyFat, .waist] {
            let values = measurements.filter { $0.metric == metric && $0.date >= since }.sorted { $0.date < $1.date }
            if let first = values.first, let last = values.last, values.count >= 2 {
                out.append(L("%@：%@ %@ %@ → %@ %@ %@（共 %lld 次记录）。", metric.name, first.date.shortString, first.value.fmt(1), metric.unit, last.date.shortString, last.value.fmt(1), metric.unit, values.count))
            }
        }
        var latest: [BodyMetric: BodyMeasurement] = [:]
        for m in measurements.sorted(by: { $0.date > $1.date }) where latest[m.metric] == nil && m.metric != .weight { latest[m.metric] = m }
        if !latest.isEmpty { out.append(L("最新身体测量：%@", latest.values.sorted { $0.metric.name < $1.metric.name }.map { "\($0.metric.name) \($0.value.fmt(1)) \($0.metric.unit)" }.joined(separator: separator))) }

        let recentFood = foods.filter { $0.date >= Date().adding(days: -7) }
        out.append(L("## 最近 7 天饮食"))
        if recentFood.isEmpty { out.append(L("无记录。")) } else {
            let daysLogged = Set(recentFood.map { $0.date.dayKey }).count
            out.append(L("有餐食记录的天数：%lld/7；共 %lld 条。没有全天记录完整性的标记，无法判断是否达到每日摄入目标。", daysLogged, recentFood.count))
            if daysLogged <= 2 {
                out.append(L("有效记录太少，暂不估算摄入。请记录几天完整饮食后再评估。"))
            } else {
                for entry in recentFood.sorted(by: { $0.date > $1.date }).prefix(8) {
                    out.append(L("- %@ %@：%@（仅一条记录）。", entry.date.shortString, entry.meal.name, entry.name))
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
    @AppStorage(AIProgram.nutritionKey) private var nutrition = Data()
    @AppStorage(CoachHistory.key) private var conversation = Data()
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
                        Label(profile.lastBodyAnalysis.isEmpty ? "生成分析和四周饮食建议" : "重新分析并更新饮食建议", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).disabled(loading || !AIBackend.isConfigured)
                }.card()
                if let program = AIProgram.load(nutrition) {
                    NavigationLink {
                        AIProgramView(program: program, focus: .nutrition, exercises: exercises)
                    } label: {
                        Label("查看四周饮食建议", systemImage: "calendar.badge.checkmark")
                    }.card()
                }
                Button("Plan workouts with AI trainer") { AppState.shared.perform(.openCoach) }
                    .buttonStyle(.bordered)
                Text("Workout plans are managed by your private trainer. This analysis only updates nutrition guidance.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("发送给模型的数据", isExpanded: $showData) {
                    Text(summary).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    if !conversation.isEmpty {
                        Text("分析也会参考本机保存的近期小段聊天。").font(.caption).foregroundStyle(.secondary)
                    }
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
        let planAtStart = nutrition
        let history = CoachHistory.context(from: conversation)
        Task {
            defer { loading = false }
            do {
                let (text, program) = try await AIProgram.generateNutrition(request: data, history: history,
                                                                 profile: profile, exercises: exercises, config: config)
                let encoded = try program.encoded()
                guard nutrition == planAtStart else {
                    self.error = L("饮食建议已更新，请重新分析以继续调整。")
                    return
                }
                let previous = (profile.lastBodyAnalysis, profile.lastBodyAnalysisAt)
                profile.lastBodyAnalysis = text
                profile.lastBodyAnalysisAt = Date()
                do {
                    try context.save()
                    nutrition = encoded
                } catch {
                    (profile.lastBodyAnalysis, profile.lastBodyAnalysisAt) = previous
                    throw error
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}
