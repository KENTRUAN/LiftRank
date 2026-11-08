import SwiftUI
import SwiftData
import Charts

struct CardioView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \CardioSession.date, order: .reverse) private var sessions: [CardioSession]
    @Query private var workouts: [Workout]
    @AppStorage(AIProgram.combinedKey) private var combined = Data()
    @State private var editor: EditorTarget?
    @State private var healthStatus: String?
    @State private var importing = false
    @State private var activeWorkout: Workout?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var week: [CardioSession] { sessions.filter { $0.date.weekKey == Date().weekKey } }

    private enum EditorTarget: Identifiable {
        case existing(CardioSession)
        case planned(AIProgram.Cardio)

        var id: String {
            switch self {
            case .existing(let session): session.id.uuidString
            case .planned: "planned"
            }
        }
    }

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
            if let program = AIProgram.load(combined), program.weeks.contains(where: { !$0.cardio.isEmpty }) {
                Section("Saved cardio plan") {
                    NavigationLink("查看四周有氧计划") {
                        AIProgramView(program: program, focus: .cardio, onCardio: { editor = .planned($0) })
                    }
                }
            }
            Section {
                if let active = workouts.first(where: { !$0.isPublished && $0.isOutdoor }), active.startOptionsChosen { OutdoorWorkoutMap(workout: active) }
            }
            Section {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    StatTile(title: L("时长"), value: L("%@ 分钟", week.reduce(0) { $0 + $1.durationMinutes }.fmt(0)))
                    StatTile(title: L("距离"), value: "\(week.reduce(0) { $0 + $1.distanceKm }.fmt(1)) km", color: .blue)
                    StatTile(title: L("有氧次数"), value: "\(week.count)", color: .green)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            } header: { Text("本周有氧") }

            Section {
                weeklyChart
            } header: { Text("最近 8 周") }

            Section {
                Button { connectHealth() } label: { Label("连接 Apple Health", systemImage: "heart.fill") }
                Button { importFromHealth() } label: { Label(importing ? "导入中…" : "从健康 App 导入最近 90 天运动", systemImage: "square.and.arrow.down") }.disabled(importing)
                if let healthStatus { Text(healthStatus).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Apple Watch 与 Fitness") } footer: {
                Text("Start cardio to choose an indoor or outdoor activity. Outdoor workouts show your private route while LiftRank is open. End saves elapsed time.")
            }

            Section(sessions.isEmpty ? "记录" : "记录 · \(sessions.count) 次") {
                if sessions.isEmpty { Text("还没有有氧记录。").font(.footnote).foregroundStyle(.secondary) }
                ForEach(sessions) { s in
                    Button { if s.sourceRaw == "timer", let record = workouts.first(where: { TrainingHealthManager.syncIdentifier($0.id) == s.externalID }) { activeWorkout = record } else { editor = .existing(s) } } label: {
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
                    }.deleteDisabled(s.sourceRaw == "timer")
                }
                .onDelete { idx in idx.map { sessions[$0] }.filter { $0.sourceRaw != "timer" }.forEach(context.delete); try? context.save() }
            }
        }
        .fullScreenCover(item: $activeWorkout) { ActiveWorkoutView(workout: $0, profile: profile) }
        .sheet(item: $editor) { target in
            switch target {
            case .existing(let session):
                CardioEditor(profile: profile, session: session)
            case .planned(let planned):
                CardioEditor(profile: profile, session: nil, suggested: planned)
            }
        }
    }

    private var weeklyChart: some View {
        let buckets = weekly
        let peak = buckets.map(\.minutes).max() ?? 0
        let step = max(20, (peak / 100).rounded(.up) * 20)
        let ticks = (0...5).map { Double($0) * step }
        let labelIndices = dynamicTypeSize.isAccessibilitySize ? [0, 7] : [0, 2, 4, 7]
        let dateLabels = Dictionary(uniqueKeysWithValues: labelIndices.map { index in
            let bucket = buckets[index]
            let date = bucket.start.formatted(.dateTime.month(.defaultDigits).day().locale(AppLanguage.current.locale))
            return (bucket.id, date)
        })

        return VStack(alignment: .leading, spacing: 10) {
            Text("每周有氧时长（分钟）").font(.subheadline.bold())
            Chart(buckets) { bucket in
                BarMark(x: .value(L("周"), bucket.id), y: .value(L("分钟"), bucket.minutes))
                    .foregroundStyle(Color.accentColor.gradient)
                    .accessibilityLabel(bucket.start.shortString)
                    .accessibilityValue(L("%@ 分钟", bucket.minutes.fmt(0)))
            }
            .chartXScale(domain: buckets.map(\.id))
            .chartYScale(domain: 0...(step * 5), range: .plotDimension(startPadding: 0, endPadding: 9))
            .chartYAxis {
                AxisMarks(values: ticks) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: buckets.map(\.id).filter { dateLabels[$0] != nil }) { value in
                    if let id = value.as(String.self), let date = dateLabels[id] {
                        AxisValueLabel { Text(date).font(.caption2).fixedSize() }
                    }
                }
            }
            .frame(height: 168)
            .accessibilityIdentifier("weeklyCardioChart")
            Text("每根柱代表从该日期开始的一周内累计的有氧分钟数。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    private func detail(_ s: CardioSession) -> String {
        var parts = [s.sourceRaw == "timer" ? (s.durationMinutes * 60).clockString : L("%@ 分钟", s.durationMinutes.fmt(0))]
        if s.distanceKm > 0 { parts.append("\(s.distanceKm.fmt(2)) km") }
        if s.distanceKm > 0 && s.durationMinutes > 0 && s.type.usesDistance { parts.append(L("配速 %@/km", (s.durationMinutes / s.distanceKm).paceString)) }
        if s.calories > 0 { parts.append("\(s.calories.fmt(0)) kcal") }
        if s.avgHeartRate > 0 { parts.append("♥ \(s.avgHeartRate.fmt(0))") }
        return parts.joined(separator: " · ")
    }

    private func connectHealth() {
        Task {
            do { try await HealthKitManager.shared.requestAuthorization(); healthStatus = L("已请求授权。若未弹出窗口，请到「设置 → 健康 → 数据访问与设备」中开启。") }
            catch { healthStatus = L("无法连接：%@", error.localizedDescription) }
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
                    s.notes = L("来自 %@", i.sourceName)
                    s.writtenToHealth = true
                    context.insert(s)
                    added += 1
                }
                try? context.save()
                healthStatus = added > 0 ? L("已导入 %lld 条运动记录。", added) : L("没有新的运动记录（共找到 %lld 条）。", imports.count)
            } catch {
                healthStatus = L("导入失败：%@", error.localizedDescription)
            }
        }
    }
}

struct CardioEditor: View {
    let profile: UserProfile
    let session: CardioSession?
    var suggested: AIProgram.Cardio? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var type: CardioType = .running
    @State private var date = Date()
    @State private var minutes = "30"
    @State private var distance = ""
    @State private var calories = ""
    @State private var heartRate = ""
    @State private var notes = ""
    @State private var saveFailed = false

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
                    numField(L("时长（分钟）"), $minutes)
                    if type.usesDistance { numField(L("距离（km）"), $distance) }
                    numField(L("消耗（kcal）"), $calories)
                    numField(L("平均心率"), $heartRate)
                    Button("按体重估算消耗：\(estimatedKcal.fmt(0)) kcal") { calories = estimatedKcal.fmt(0) }.font(.subheadline)
                }
                Section("备注") { TextField("感受、路线、器械…", text: $notes, axis: .vertical).lineLimit(2...5) }
            }
            .navigationTitle(session == nil ? "记录有氧" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled((Double(minutes) ?? 0) <= 0)
                }
            }
            .alert("无法保存有氧记录，请重试。", isPresented: $saveFailed) { Button("OK") {} }
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

    private func save() {
        guard let duration = Double(minutes), duration.isFinite, duration > 0 else { return }
        let record = session ?? CardioSession(date: date, type: type, durationMinutes: duration)
        let previous = (record.type, record.date, record.durationMinutes, record.distanceKm,
                        record.calories, record.avgHeartRate, record.notes)
        record.type = type
        record.date = date
        record.durationMinutes = duration
        record.distanceKm = type.usesDistance ? (Double(distance) ?? 0) : 0
        record.calories = Double(calories) ?? 0
        record.avgHeartRate = Double(heartRate) ?? 0
        record.notes = notes
        if session == nil { context.insert(record) }
        do {
            try context.save()
            dismiss()
        } catch {
            if session == nil {
                context.delete(record)
            } else {
                (record.type, record.date, record.durationMinutes, record.distanceKm,
                 record.calories, record.avgHeartRate, record.notes) = previous
            }
            saveFailed = true
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
