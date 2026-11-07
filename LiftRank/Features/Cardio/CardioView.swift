import SwiftUI
import SwiftData
import Charts

struct CardioView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \CardioSession.date, order: .reverse) private var sessions: [CardioSession]
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var claims: [QuestClaim]
    @AppStorage("cardio.writeToHealth") private var writeToHealth = false
    @AppStorage(AIProgram.combinedKey) private var combined = Data()
    @State private var showEditor = false
    @State private var scheduled: AIProgram.Cardio?
    @State private var editing: CardioSession?
    @State private var healthStatus: String?
    @State private var importing = false

    private var week: [CardioSession] { sessions.filter { $0.date.weekKey == Date().weekKey } }

    private struct WeekBucket: Identifiable { let id: String; let start: Date; let minutes: Double }
    private var weekly: [WeekBucket] {
        let cal = Calendar(identifier: .iso8601)
        return (0..<8).reversed().map { back in
            let ref = Date().adding(days: -7 * back)
            let start = cal.dateInterval(of: .weekOfYear, for: ref)?.start ?? ref
            let minutes = sessions.filter { $0.date.weekKey == ref.weekKey }.reduce(0) { $0 + $1.durationMinutes }
            return WeekBucket(id: ref.weekKey, start: start, minutes: minutes)
        }
    }

    var body: some View {
        List {
            if let program = AIProgram.load(combined) {
                Section("AI 有氧安排") {
                    NavigationLink("查看四周有氧计划") {
                        AIProgramView(program: program, focus: .cardio, onCardio: { scheduled = $0 })
                    }
                }
            }
            Section {
                HStack(spacing: 10) {
                    StatTile(title: "本周时长", value: "\(week.reduce(0) { $0 + $1.durationMinutes }.fmt(0)) 分")
                    StatTile(title: "本周距离", value: "\(week.reduce(0) { $0 + $1.distanceKm }.fmt(1)) km", color: .blue)
                    StatTile(title: "本周次数", value: "\(week.count)", color: .green)
                }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                Chart(weekly) { b in
                    BarMark(x: .value("周", b.start, unit: .weekOfYear), y: .value("分钟", b.minutes)).foregroundStyle(Color.accentColor.gradient)
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                .frame(height: 120)
                Button { showEditor = true } label: { Label("记录有氧", systemImage: "plus.circle.fill").font(.headline) }
            } header: { Text("最近 8 周") }

            Section {
                Button { connectHealth() } label: { Label("连接 Apple Health", systemImage: "heart.fill") }
                Button { importFromHealth() } label: { Label(importing ? "导入中…" : "从健康 App 导入最近 90 天运动", systemImage: "square.and.arrow.down") }.disabled(importing)
                Toggle(isOn: $writeToHealth) { Label("手动记录同步写入健康", systemImage: "arrow.up.heart") }
                if let healthStatus { Text(healthStatus).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Apple Watch 与 Fitness") } footer: {
                Text("Apple Watch 上记录的跑步、骑行、游泳等体能训练会同步到健康 App；授权后在这里导入即可计入连续记录与每日奖励。手动记录可写回健康，在 Fitness 中显示。模拟器与未签名构建无法访问 HealthKit。")
            }

            Section(sessions.isEmpty ? "记录" : "记录 · \(sessions.count) 次") {
                if sessions.isEmpty { Text("还没有有氧记录。").font(.footnote).foregroundStyle(.secondary) }
                ForEach(sessions) { s in
                    Button { editing = s } label: {
                        HStack {
                            Image(systemName: s.type.icon).font(.title3).frame(width: 30).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(s.type.name).bold().foregroundStyle(.primary)
                                    if s.isFromHealth { Image(systemName: "applewatch").font(.caption2).foregroundStyle(.secondary) }
                                }
                                Text(detail(s)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(s.date.shortString).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in idx.map { sessions[$0] }.forEach(context.delete); try? context.save() }
            }
        }
        .sheet(isPresented: $showEditor) { CardioEditor(profile: profile, session: nil) { s in saved(s) } }
        .sheet(item: $scheduled) { day in
            CardioEditor(profile: profile, session: nil, suggested: day) { saved($0) }
        }
        .sheet(item: $editing) { s in CardioEditor(profile: profile, session: s) { _ in try? context.save() } }
    }

    private func detail(_ s: CardioSession) -> String {
        var parts = ["\(s.durationMinutes.fmt(0)) 分钟"]
        if s.distanceKm > 0 { parts.append("\(s.distanceKm.fmt(2)) km") }
        if s.distanceKm > 0 && s.durationMinutes > 0 && s.type.usesDistance { parts.append("配速 \((s.durationMinutes / s.distanceKm).paceString)/km") }
        if s.calories > 0 { parts.append("\(s.calories.fmt(0)) kcal") }
        if s.avgHeartRate > 0 { parts.append("♥ \(s.avgHeartRate.fmt(0))") }
        return parts.joined(separator: " · ")
    }

    private func saved(_ s: CardioSession) {
        context.insert(s)
        try? context.save()
        let gsr = RankAggregator.overall(muscleScores: RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)))
        let eggs = DailyTrainingEngine.claimIfEarned(profile: profile, workouts: workouts, cardio: sessions + [s], claims: claims, gsr: gsr, context: context)
        if eggs > 0 { AppState.shared.flash("今日训练完成 +\(eggs) Eggs") }
        if writeToHealth {
            Task {
                do { try await HealthKitManager.shared.save(s); s.writtenToHealth = true; try? context.save() }
                catch { healthStatus = "写入健康失败：\(error.localizedDescription)" }
            }
        }
    }

    private func connectHealth() {
        Task {
            do { try await HealthKitManager.shared.requestAuthorization(); healthStatus = "已请求授权。若未弹出窗口，请到「设置 → 健康 → 数据访问与设备」中开启。" }
            catch { healthStatus = "无法连接：\(error.localizedDescription)" }
        }
    }

    private func importFromHealth() {
        importing = true
        Task {
            defer { importing = false }
            do {
                try await HealthKitManager.shared.requestAuthorization()
                let imports = try await HealthKitManager.shared.importWorkouts(since: Date().adding(days: -90))
                let existing = Set(sessions.map(\.externalID))
                var added = 0
                for i in imports where !existing.contains(i.externalID) {
                    let s = CardioSession(date: i.date, type: i.type, durationMinutes: i.durationMinutes, distanceKm: i.distanceKm, calories: i.calories,
                                          avgHeartRate: i.avgHeartRate, source: "health", externalID: i.externalID)
                    s.notes = "来自 \(i.sourceName)"
                    s.writtenToHealth = true
                    context.insert(s)
                    added += 1
                }
                try? context.save()
                healthStatus = added > 0 ? "已导入 \(added) 条运动记录。" : "没有新的运动记录（共找到 \(imports.count) 条）。"
            } catch {
                healthStatus = "导入失败：\(error.localizedDescription)"
            }
        }
    }
}

struct CardioEditor: View {
    let profile: UserProfile
    let session: CardioSession?
    var suggested: AIProgram.Cardio? = nil
    let onSave: (CardioSession) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var type: CardioType = .running
    @State private var date = Date()
    @State private var minutes = "30"
    @State private var distance = ""
    @State private var calories = ""
    @State private var heartRate = ""
    @State private var notes = ""

    private var estimatedKcal: Double {
        let m = Double(minutes) ?? 0
        return (type.metValue * profile.bodyweightKg * m / 60).rounded()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("运动") {
                    Picker("类型", selection: $type) { ForEach(CardioType.allCases) { Label($0.name, systemImage: $0.icon).tag($0) } }
                    DatePicker("时间", selection: $date)
                    numField("时长（分钟）", $minutes)
                    if type.usesDistance { numField("距离（km）", $distance) }
                    numField("消耗（kcal）", $calories)
                    numField("平均心率", $heartRate)
                    Button("按体重估算消耗：\(estimatedKcal.fmt(0)) kcal") { calories = estimatedKcal.fmt(0) }.font(.subheadline)
                }
                Section("备注") { TextField("感受、路线、器械…", text: $notes, axis: .vertical).lineLimit(2...5) }
            }
            .navigationTitle(session == nil ? "记录有氧" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let s = session ?? CardioSession(date: date, type: type, durationMinutes: 0)
                        s.type = type; s.date = date
                        s.durationMinutes = Double(minutes) ?? 0
                        s.distanceKm = type.usesDistance ? (Double(distance) ?? 0) : 0
                        s.calories = Double(calories) ?? 0
                        s.avgHeartRate = Double(heartRate) ?? 0
                        s.notes = notes
                        onSave(s)
                        dismiss()
                    }.disabled((Double(minutes) ?? 0) <= 0)
                }
            }
            .onAppear {
                guard let s = session else {
                    if let suggested {
                        type = suggested.type
                        minutes = String(suggested.minutes)
                        notes = suggested.effort
                    }
                    return
                }
                type = s.type; date = s.date; minutes = s.durationMinutes.fmt(0)
                distance = s.distanceKm > 0 ? s.distanceKm.fmt(2) : ""
                calories = s.calories > 0 ? s.calories.fmt(0) : ""
                heartRate = s.avgHeartRate > 0 ? s.avgHeartRate.fmt(0) : ""
                notes = s.notes
            }
        }
    }

    private func numField(_ label: String, _ b: Binding<String>) -> some View {
        HStack { Text(label); Spacer(); TextField("0", text: b).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
    }
}

extension Double {
    /// Minutes per km → "5'30\"".
    var paceString: String {
        guard isFinite, self > 0 else { return "—" }
        let total = Int((self * 60).rounded())
        return "\(total / 60)'\(String(format: "%02d", total % 60))\""
    }
}
