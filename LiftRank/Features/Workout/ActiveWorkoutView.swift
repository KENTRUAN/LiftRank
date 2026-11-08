import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Bindable var workout: Workout
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query private var exercises: [Exercise]

    @State private var showPicker = false
    @State private var showFinish = false
    @State private var showStartOptions = false
    @State private var showSet = false
    @State private var confirmDiscard = false
    @State private var plateWeight: PlateTarget?
    @State private var showChecklist = true
    @State private var prep: Set<String> = []
    private var prepItems: [String] { [L("热身 5–10 分钟"), L("补水与装备就绪"), L("确认今日体重")] }

    private var exerciseByKey: [String: Exercise] { Dictionary(uniqueKeysWithValues: exercises.map { ($0.key, $0) }) }

    var body: some View {
        if workout.activity != .strength { TimedCardioWorkoutView(workout: workout, profile: profile) }
        else { strengthBody }
    }
    private var strengthBody: some View {
        NavigationStack {
            List {
                Section {
                    TextField("训练名称", text: $workout.title).font(.headline)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack {
                            Label(workout.duration.clockString, systemImage: "timer").monospacedDigit()
                            Spacer()
                            Text("\(workout.completedSets.count) 组 · \(profile.unit.fromKg(workout.totalVolumeKg).fmt(0)) \(profile.unit.label)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    TextField("备注", text: $workout.notes, axis: .vertical)
                }

                if workout.isOutdoor && workout.activity != .strength { Section { OutdoorWorkoutMap(workout: workout) } }
                if workout.hasChecklist { checklistSection }
                Section {
                    WorkoutSetControl(workout: workout, profile: profile, onStart: { showSet = true }, onLog: { showSet = true })
                    TrainingHealthStatusView(workout: workout)
                    if workout.exercises.isEmpty && !workout.hasPendingSet {
                        Button("Choose an optional preset") { showStartOptions = true }
                    }
                }

                if !workout.isPublished {
                  ForEach(workout.sortedExercises) { we in
                    ExerciseSection(we: we, exercise: exerciseByKey[we.exerciseKey], profile: profile,
                                    previous: WorkoutPublisher.lastSets(for: we.exerciseKey, workouts: workouts, excluding: workout),
                                    onComplete: { startRest(we.restSeconds) },
                                    onPlates: { plateWeight = PlateTarget(kg: $0) },
                                    onDelete: { if !we.sets.contains(where: \.isCompleted) { context.delete(we); try? context.save() } })
                  }
                }

                Section {
                    Button { showPicker = true } label: { Label("添加动作", systemImage: "plus") }
                    Button(role: .destructive) { confirmDiscard = true } label: { Label("Discard empty workout", systemImage: "trash") }.disabled(!workout.completedSets.isEmpty)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("进行中")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("收起") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showFinish = true }.bold().disabled(workout.hasPendingSet)
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView { ex in addExercise(ex) }
            }
            .sheet(isPresented: $showStartOptions) { WorkoutStartOptionsView(workout: workout, profile: profile) }
            .sheet(isPresented: $showSet) { GymEquipmentSheet(workout: workout, profile: profile, station: "all") { _, _ in } }
            .task {
                if !workout.startOptionsChosen && workout.exercises.isEmpty { showStartOptions = true }
                else { workout.startOptionsChosen = true; await TrainingHealthManager.shared.start(workout, context: context) }
            }
            .sheet(isPresented: $showFinish) {
                FinishWorkoutSheet(workout: workout, profile: profile, onPublished: { dismiss() })
            }
            .sheet(item: $plateWeight) { w in PlateCalculatorView(targetKg: w.kg, unit: profile.unit) }
            .confirmationDialog("放弃本次训练？所有记录将删除。", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃训练", role: .destructive) {
                    guard workout.completedSets.isEmpty else { return }
                    TrainingHealthManager.shared.discard(workout)
                    context.delete(workout)
                    try? context.save()
                    dismiss()
                }
            }
        }
    }

    private var checklistSection: some View {
        let exercises = workout.sortedExercises
        let total = exercises.reduce(0) { $0 + $1.sets.count }
        let done = workout.completedSets.count
        return Section {
            if showChecklist {
                ForEach(prepItems, id: \.self) { item in
                    Button {
                        if prep.contains(item) { prep.remove(item) } else { prep.insert(item) }
                    } label: {
                        HStack {
                            Image(systemName: prep.contains(item) ? "checkmark.circle.fill" : "circle").foregroundStyle(prep.contains(item) ? .green : .secondary)
                            Text(item).foregroundStyle(.primary).strikethrough(prep.contains(item), color: .secondary)
                        }.font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(exercises) { we in
                    let finished = we.sets.filter { $0.isCompleted }.count
                    let all = !we.sets.isEmpty && finished == we.sets.count
                    HStack {
                        Image(systemName: all ? "checkmark.circle.fill" : finished > 0 ? "circle.lefthalf.filled" : "circle")
                            .foregroundStyle(all ? .green : finished > 0 ? Color.accentColor : .secondary)
                        Text(ExerciseNames.display(we.exerciseName)).strikethrough(all, color: .secondary)
                        Spacer()
                        Text("\(finished)/\(we.sets.count) 组").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.font(.subheadline)
                }
                if exercises.isEmpty { Text("还没有动作，点下方「添加动作」。").font(.caption).foregroundStyle(.secondary) }
            }
        } header: {
            Button { withAnimation { showChecklist.toggle() } } label: {
                HStack {
                    Label("训练清单 \(done)/\(total) 组", systemImage: "checklist").font(.subheadline.bold()).textCase(nil)
                    Spacer()
                    ProgressView(value: total > 0 ? Double(done) / Double(total) : 0).frame(width: 80)
                    Image(systemName: showChecklist ? "chevron.up" : "chevron.down").font(.caption)
                }
            }.buttonStyle(.plain)
        }
    }

    private func addExercise(_ ex: Exercise) {
        let we = WorkoutExercise(order: (workout.exercises.map(\.order).max() ?? -1) + 1, exercise: ex, restSeconds: profile.defaultRestSeconds)
        let prev = WorkoutPublisher.lastSets(for: ex.key, workouts: workouts, excluding: workout)
        let count = max(1, min(prev.count, 5))
        for i in 0..<count {
            we.sets.append(WorkoutSet(order: i, weightKg: prev.indices.contains(i) ? prev[i].weightKg : 0, reps: prev.indices.contains(i) ? prev[i].reps : 0))
        }
        workout.exercises.append(we)
        try? context.save()
    }

    private func startRest(_ seconds: Int) {
        guard seconds > 0 else { return }
        workout.restUntil = Date().addingTimeInterval(TimeInterval(seconds))
        try? context.save()
    }
}

struct PlateTarget: Identifiable { let id = UUID(); let kg: Double }

private struct ExerciseSection: View {
    @Bindable var we: WorkoutExercise
    let exercise: Exercise?
    let profile: UserProfile
    let previous: [WorkoutSet]
    let onComplete: () -> Void
    let onPlates: (Double) -> Void
    let onDelete: () -> Void
    @Environment(\.modelContext) private var context
    @State private var showNotes = false

    var body: some View {
        Section {
            HStack {
                Text(we.isCardio ? "组" : "组").frame(width: 28)
                Text("上次").frame(width: 76, alignment: .leading)
                Text(we.isCardio ? "距离 km" : profile.unit.label).frame(maxWidth: .infinity)
                Text(we.isCardio ? "分钟" : "次数").frame(maxWidth: .infinity)
                Text("RPE").frame(width: 44)
                Image(systemName: "checkmark").frame(width: 32)
            }
            .font(.caption2).foregroundStyle(.secondary)
            .listRowSeparator(.hidden)

            ForEach(we.sortedSets) { s in
                SetRowView(set: s, exercise: exercise, profile: profile, bodyweightKg: we.workout?.bodyweightKg ?? profile.bodyweightKg,
                           previous: previous.indices.contains(s.order) ? previous[s.order] : nil, onComplete: onComplete)
                    .deleteDisabled(s.isCompleted)
                    .contextMenu {
                        if !s.isCompleted { ForEach(SetType.allCases) { t in Button(t.name) { s.type = t } } }
                        if !we.isCardio { Button("杠铃片配重") { onPlates(s.weightKg) } }
                        if !s.isCompleted { Button("删除本组", role: .destructive) { context.delete(s) } }
                    }
            }
            .onDelete { idx in
                let sets = we.sortedSets
                idx.map { sets[$0] }.filter { !$0.isCompleted }.forEach(context.delete)
                renumber()
            }

            Button {
                let last = we.sortedSets.last
                we.sets.append(WorkoutSet(order: (last?.order ?? -1) + 1, weightKg: last?.weightKg ?? 0, reps: last?.reps ?? 0))
            } label: { Label("添加一组", systemImage: "plus").font(.subheadline) }

            if showNotes || !we.notes.isEmpty {
                TextField("动作备注", text: $we.notes, axis: .vertical).font(.footnote)
            }
        } header: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ExerciseNames.display(we.exerciseName)).font(.headline).foregroundStyle(.primary).textCase(nil)
                    HStack(spacing: 6) {
                        Text(we.muscleGroup.name)
                        if let ex = exercise, ex.isRanked { Text("· 支持段位") }
                        if we.supersetGroup > 0 { Text("· 超级组 \(we.supersetGroup)") }
                        Text("· 休息 \(we.restSeconds)s")
                    }.font(.caption).textCase(nil)
                }
                Spacer()
                Menu {
                    Menu("组间休息") {
                        ForEach([0, 45, 60, 90, 120, 150, 180, 240], id: \.self) { s in Button(s == 0 ? "不计时" : "\(s) 秒") { we.restSeconds = s } }
                    }
                    Menu("超级组") {
                        Button("取消超级组") { we.supersetGroup = 0 }
                        ForEach(1...3, id: \.self) { g in Button("超级组 \(g)") { we.supersetGroup = g } }
                    }
                    Button("添加备注") { showNotes = true }
                    if let ex = exercise, !ex.instructions.isEmpty { Button("动作要点") { showNotes = true; if we.notes.isEmpty { we.notes = L("要点：") + L(ex.instructions) } } }
                    Button("移除动作", role: .destructive, action: onDelete).disabled(we.sets.contains(where: \.isCompleted))
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
            }
        }
    }

    private func renumber() {
        for (i, s) in we.sortedSets.enumerated() { s.order = i }
    }
}

struct SetRowView: View {
    @Bindable var set: WorkoutSet
    let exercise: Exercise?
    let profile: UserProfile
    let bodyweightKg: Double
    let previous: WorkoutSet?
    let onComplete: () -> Void
    @Environment(\.modelContext) private var context
    @State private var saveError: String?
    @State private var weightText = ""
    @State private var repsText = ""
    @FocusState private var focus: Field?
    enum Field { case weight, reps }

    private var unit: WeightUnit { profile.unit }
    private var isCardio: Bool { exercise?.isCardio ?? false }
    private var displayedWeight: String {
        if set.weightKg == 0 { return "" }
        return isCardio ? set.weightKg.fmt(2) : unit.fromKg(set.weightKg).fmt(1)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                let all = SetType.allCases
                set.type = all[(all.firstIndex(of: set.type)! + 1) % all.count]
            } label: {
                Text(set.type == .normal ? "\(set.order + 1)" : set.type.tag)
                    .font(.caption.bold())
                    .frame(width: 26, height: 26)
                    .background(set.type == .warmup ? Color.orange.opacity(0.2) : set.type == .drop ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)

            Text(previousLabel).font(.caption2).foregroundStyle(.secondary).frame(width: 76, alignment: .leading).lineLimit(1)

            TextField(isCardio ? "km" : unit.label, text: $weightText)
                .keyboardType(.decimalPad).multilineTextAlignment(.center).focused($focus, equals: .weight)
                .padding(6).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: weightText) { _, v in
                    guard !set.isCompleted, v != displayedWeight else { return }
                    let raw = Double(v.replacingOccurrences(of: ",", with: ".")) ?? 0
                    set.weightKg = isCardio ? raw : unit.toKg(raw)
                }
            TextField(isCardio ? "分" : "次", text: $repsText)
                .keyboardType(.numberPad).multilineTextAlignment(.center).focused($focus, equals: .reps)
                .padding(6).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: repsText) { _, v in if !set.isCompleted { set.reps = Int(v) ?? 0 } }

            Menu {
                Button("—") { set.rpe = nil; set.rir = nil }
                ForEach([6.0, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10], id: \.self) { r in
                    Button("RPE \(r.fmt(1))") { set.rpe = r; set.rir = max(0, Int((10 - r).rounded())) }
                }
            } label: {
                Text(set.rpe.map { $0.fmt(1) } ?? "—").font(.caption.monospacedDigit()).frame(width: 44)
            }

            Button {
                guard !set.isCompleted, set.reps > 0, set.weightKg.isFinite, set.weightKg >= 0 else { return }
                set.isCompleted = true; set.completedAt = Date()
                do { try context.save(); onComplete(); focus = nil }
                catch { set.isCompleted = false; set.completedAt = nil; saveError = error.localizedDescription }
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(set.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain).frame(width: 32)
        }
        .disabled(set.isCompleted)
        .alert("Could not save set", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) { Button("OK") { saveError = nil } } message: { Text(saveError ?? "") }
        .listRowBackground(set.isCompleted ? Color.green.opacity(0.08) : nil)
        .onAppear {
            weightText = displayedWeight
            repsText = set.reps == 0 ? "" : "\(set.reps)"
        }
        .onChange(of: set.weightKg) { _, v in
            // Keep text in sync when the model changes from elsewhere (e.g. a template prefill).
            let shown = Double(weightText) ?? -1
            let model = isCardio ? v : unit.fromKg(v)
            if abs(shown - model) > 0.051 && !(v == 0 && weightText.isEmpty) { weightText = displayedWeight }
        }
        .onChange(of: unit) { _, _ in weightText = displayedWeight }
        .overlay(alignment: .bottomTrailing) {
            if let ex = exercise, ex.isRanked, set.reps > 0, set.weightKg > 0 || ex.bodyweightFactor > 0 {
                let score = StrengthScoring.score(set: set, exercise: ex, bodyweightKg: bodyweightKg, sex: profile.sex)
                if score > 0 {
                    Text("\(score)").font(.system(size: 9, weight: .bold)).foregroundStyle(RankTier.tier(for: score).color).offset(x: -2, y: 2)
                }
            }
        }
    }

    private var previousLabel: String {
        guard let p = previous else { return "—" }
        if isCardio { return L("%@km×%lld分", p.weightKg.fmt(1), p.reps) }
        return "\(unit.fromKg(p.weightKg).fmt(1))×\(p.reps)"
    }
}

struct RestTimerBar: View {
    let endsAt: Date
    let total: Int
    let onSkip: () -> Void
    let onAdd: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let remaining = max(0, endsAt.timeIntervalSince(ctx.date))
            HStack(spacing: 12) {
                Image(systemName: "hourglass")
                VStack(alignment: .leading, spacing: 4) {
                    Text(remaining > 0 ? "休息 \(remaining.clockString)" : "休息结束，开始下一组").font(.subheadline.bold().monospacedDigit())
                    ProgressView(value: total > 0 ? 1 - remaining / Double(total) : 1).tint(remaining > 0 ? .accentColor : .green)
                }
                Button("+30s", action: onAdd).buttonStyle(.bordered).controlSize(.small)
                Button(remaining > 0 ? "跳过" : "关闭", action: onSkip).buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }
}

struct FinishWorkoutSheet: View {
    @Bindable var workout: Workout
    @Bindable var profile: UserProfile
    let onPublished: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    @Query private var workouts: [Workout]
    @Query private var cardio: [CardioSession]
    @Query private var claims: [QuestClaim]
    @State private var bodyweightText = ""
    @State private var summary: PublishSummary?

    var body: some View {
        NavigationStack {
            Form {
                Section { TrainingHealthStatusView(workout: workout) }
                if let s = summary {
                    Section {
                        VStack(spacing: 12) {
                            ScoreGauge(score: s.bestScore, size: 120)
                            Text(s.bestScore > 0 ? "本次最佳单组评分" : "本次没有支持段位的动作").font(.footnote).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                    Section("奖励") {
                        if s.firstOfDay {
                            LabeledContent("今日训练奖励") { EggAmount(amount: s.eggs, signed: true) }
                        } else {
                            LabeledContent("今日训练奖励", value: L("今天已领取"))
                        }
                        LabeledContent("总体评分 GSR") { HStack { Text("\(s.overallScore)"); TierBadge(tier: RankTier.tier(for: s.overallScore), compact: true) } }
                        LabeledContent("连续训练", value: L("%lld 天", s.streakDays))
                    }
                    if !s.prs.isEmpty {
                        Section("个人纪录 PR") { ForEach(s.prs, id: \.self) { Label($0, systemImage: "trophy.fill").foregroundStyle(.orange) } }
                    }
                    Section {
                        Button { dismiss(); onPublished() } label: { Text("完成").frame(maxWidth: .infinity).bold() }
                    }
                } else {
                    Section("本次训练") {
                        LabeledContent("时长", value: workout.duration.clockString)
                        LabeledContent("完成组数", value: "\(workout.completedSets.count)")
                        LabeledContent("训练量", value: "\(profile.unit.fromKg(workout.totalVolumeKg).fmt(0)) \(profile.unit.label)")
                    }
                    Section {
                        HStack {
                            Text("体重 (\(profile.unit.label))")
                            Spacer()
                            TextField("体重", text: $bodyweightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    } footer: { Text("体重用于把 e1RM 换算成相对力量评分。") }
                    Section {
                        Toggle("发布到 Strava", isOn: $workout.postToStrava).disabled(true)
                    } footer: { Text("Strava 连接需要在设置中授权，当前版本尚未接入。") }
                    Section {
                        Button {
                            let unit = profile.unit
                            if let bw = try? Double(bodyweightText, format: .number), bw.isFinite, unit.toKg(bw) > 30 {
                                if bodyweightText != unit.inputText(kg: workout.bodyweightKg) {
                                    workout.bodyweightKg = unit.toKg(bw)
                                }
                                profile.bodyweightKg = workout.bodyweightKg
                                context.insert(BodyMeasurement(date: Date(), metric: .weight, value: workout.bodyweightKg))
                            }
                            workout.endedAt = Date()
                            summary = WorkoutPublisher.publish(workout, profile: profile, exercises: exercises, workouts: workouts, cardio: cardio, claims: claims, context: context)
                        } label: { Text("发布训练").frame(maxWidth: .infinity).bold() }
                    }
                }
            }
            .navigationTitle(summary == nil ? "完成训练" : "训练已发布")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if summary == nil { ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } } } }
            .onAppear { bodyweightText = profile.unit.inputText(kg: workout.bodyweightKg) }
            .interactiveDismissDisabled(summary != nil)
        }
    }
}
