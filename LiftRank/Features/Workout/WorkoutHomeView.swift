import SwiftUI
import SwiftData

struct WorkoutHomeView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse) private var templates: [WorkoutTemplate]
    @Query private var exercises: [Exercise]
    @Query private var plans: [DailyPlan]
    @AppStorage(AIProgram.combinedKey) private var combined = Data()
    @AppStorage(AIProgram.strengthKey) private var strength = Data()
    @State private var mode = 0
    @State private var activeWorkout: Workout?
    @State private var showGenerator = false
    @State private var showSummary = false
    @State private var setup: SetupTarget?
    @State private var confirmDeleteTemplate: WorkoutTemplate?

    private var unpublished: Workout? { workouts.first { !$0.isPublished } }
    private var history: [Workout] { workouts.filter { $0.isPublished } }
    private var todayPlan: DailyPlan? { plans.first { $0.dayKey == Date().dayKey } }

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Group {
                if mode == 0 { strengthList } else { CardioView(profile: profile) }
            }
            .navigationTitle(mode == 0 ? "训练" : "有氧")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $mode) { Text("力量").tag(0); Text("有氧").tag(1) }.pickerStyle(.segmented).frame(width: 160)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showSummary = true } label: { Image(systemName: "chart.xyaxis.line") }
                    Button { app.showCoach = true } label: { Image(systemName: "sparkles") }
                }
            }
            .fullScreenCover(item: $activeWorkout) { w in
                ActiveWorkoutView(workout: w, profile: profile)
            }
            .sheet(isPresented: $showGenerator) { WorkoutGeneratorView(profile: profile) }
            .sheet(isPresented: $showSummary) { NavigationStack { SummaryView(profile: profile) } }
            .sheet(isPresented: $app.showCoach) { CoachChatView(profile: profile) }
            .sheet(item: $setup) { target in
                WorkoutSetupView(title: target.title, items: target.items, isNew: target.isNew) { name, items in save(target, name: name, items: items) }
            }
            .onAppear { if DemoData.autoOpenActive, activeWorkout == nil { activeWorkout = unpublished } }
            .onChange(of: app.startTodayRequest) { _, _ in startToday() }
            .onChange(of: app.pending) { _, action in
                if action == .openCardio { mode = 1; app.pending = nil }
            }
        }
    }

    // MARK: - Strength

    private var strengthList: some View {
        List {
            if let w = unpublished {
                Section {
                    Button { activeWorkout = w } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("继续训练：\(w.title)").bold()
                                Text("已进行 \(w.duration.clockString) · \(w.completedSets.count) 组已完成").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.green)
                        }
                    }
                }
            }

            Section {
                if let p = todayPlan {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(p.title).font(.headline)
                            Spacer()
                            Text(p.sourceRaw == "ai" ? "AI 调整" : p.sourceRaw == "manual" ? "手动" : "自动发布").font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        ForEach(p.items) { item in
                            HStack {
                                Text(item.exerciseName).font(.subheadline)
                                Spacer()
                                Text("\(item.sets) × \(item.repsLow)–\(item.repsHigh) · 休 \(item.restSeconds)s").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if p.items.isEmpty { Text("今日没有安排动作，点「调整」添加。").font(.caption).foregroundStyle(.secondary) }
                    }
                    HStack {
                        Button { startToday() } label: { Label("开始训练", systemImage: "play.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).disabled(unpublished != nil || p.items.isEmpty)
                        Button { setup = SetupTarget(plan: p) } label: { Label("调整", systemImage: "slider.horizontal.3") }.buttonStyle(.bordered)
                        Button { app.showCoach = true } label: { Label("AI", systemImage: "sparkles") }.buttonStyle(.bordered)
                    }
                    .buttonStyle(.plain)
                    Button {
                        DailyPlanEngine.regenerate(plan: p, profile: profile, templates: templates, exercises: exercises, workouts: workouts)
                        try? context.save()
                    } label: { Label("换一个安排", systemImage: "arrow.triangle.2.circlepath").font(.subheadline) }
                } else {
                    Text("每天会根据你的计划或偏好自动发布一项训练。").font(.footnote).foregroundStyle(.secondary)
                    Button {
                        profile.autoPublishDailyPlan = true
                        DailyPlanEngine.ensureToday(profile: profile, templates: templates, exercises: exercises, workouts: workouts, plans: plans, context: context)
                    } label: { Label("发布今日训练", systemImage: "calendar.badge.plus") }
                }
            } header: {
                Text("今日训练 · \(Date().shortString)")
            } footer: {
                if unpublished != nil { Text("先完成或放弃进行中的训练，再开始新的训练。") }
            }

            Section("AI 训练方案") {
                NavigationLink {
                    AIStrengthPlanView(profile: profile)
                } label: { Label("AI 单独生成力量计划", systemImage: "sparkles") }
                if let program = AIProgram.load(strength) {
                    NavigationLink("独立力量 · \(program.title)") { strengthSchedule(program) }
                }
                if let program = AIProgram.load(combined) {
                    NavigationLink("综合方案 · 力量安排") { strengthSchedule(program) }
                }
            }

            Section("设置训练") {
                Button { setup = SetupTarget.newTemplate() } label: { Label("新建训练计划", systemImage: "plus.circle") }
                Button { showGenerator = true } label: { Label("按目标生成训练 / 多周计划", systemImage: "wand.and.stars") }
                ForEach(templates) { t in
                    HStack {
                        Button { setup = SetupTarget(template: t) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).foregroundStyle(.primary)
                                Text(t.planName.isEmpty ? "\(t.items.count) 个动作" : "\(t.planName) · \(t.items.count) 个动作")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button { start(title: t.name, items: t.items) } label: { Image(systemName: "play.circle").font(.title2) }
                            .buttonStyle(.plain).foregroundStyle(unpublished == nil ? Color.accentColor : .secondary).disabled(unpublished != nil)
                    }
                    .swipeActions {
                        Button(role: .destructive) { context.delete(t); try? context.save() } label: { Label("删除", systemImage: "trash") }
                        Button { setup = SetupTarget(template: t) } label: { Label("编辑", systemImage: "pencil") }.tint(.orange)
                    }
                }
                Button { start(title: defaultTitle(), items: []) } label: { Label("开始空白训练", systemImage: "square.dashed") }.disabled(unpublished != nil)
            }

            Section(history.isEmpty ? "历史" : "历史 · \(history.count) 次") {
                if history.isEmpty {
                    Text("还没有发布的训练。完成今日训练并发布即可获得评分与 Eggs。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(history) { w in
                    NavigationLink { WorkoutDetailView(workout: w, profile: profile) } label: { WorkoutRow(workout: w, unit: profile.unit) }
                }
                .onDelete { idx in
                    idx.map { history[$0] }.forEach(context.delete)
                    try? context.save()
                }
            }
        }
    }

    private func strengthSchedule(_ program: AIProgram) -> some View {
        AIProgramView(program: program, focus: .strength, exercises: exercises,
                      onStrength: unpublished == nil ? { day in
                          let items = day.resolved(using: exercises)
                          if items.count == day.items.count { start(title: day.title, items: items) }
                      } : nil)
    }

    private func startToday() {
        guard unpublished == nil else { activeWorkout = unpublished; return }
        guard let p = todayPlan, !p.items.isEmpty else { return }
        let w = WorkoutPublisher.makeWorkout(title: p.title, items: p.items, profile: profile, exercises: exercises, workouts: workouts, context: context)
        p.workoutID = w.id
        try? context.save()
        mode = 0
        activeWorkout = w
    }

    private func start(title: String, items: [TemplateExercise]) {
        guard unpublished == nil else { return }
        activeWorkout = WorkoutPublisher.makeWorkout(title: title, items: items, profile: profile, exercises: exercises, workouts: workouts, context: context)
    }

    private func save(_ target: SetupTarget, name: String, items: [TemplateExercise]) {
        switch target.kind {
        case .newTemplate:
            context.insert(WorkoutTemplate(name: name, items: items))
        case .template(let t):
            t.name = name; t.items = items
        case .plan(let p):
            p.title = name; p.items = items; p.sourceRaw = "manual"
        }
        try? context.save()
    }

    private func defaultTitle() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 11 ? "晨间训练" : h < 17 ? "午后训练" : "夜间训练"
    }
}

struct SetupTarget: Identifiable {
    enum Kind { case newTemplate, template(WorkoutTemplate), plan(DailyPlan) }
    let id = UUID()
    let kind: Kind
    let title: String
    let items: [TemplateExercise]
    var isNew: Bool { if case .newTemplate = kind { return true } else { return false } }

    static func newTemplate() -> SetupTarget { SetupTarget(kind: .newTemplate, title: "", items: []) }
    init(kind: Kind, title: String, items: [TemplateExercise]) { self.kind = kind; self.title = title; self.items = items }
    init(template: WorkoutTemplate) { self.init(kind: .template(template), title: template.name, items: template.items) }
    init(plan: DailyPlan) { self.init(kind: .plan(plan), title: plan.title, items: plan.items) }
}

struct WorkoutRow: View {
    let workout: Workout
    let unit: WeightUnit
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.title).bold()
                Text("\((workout.publishedAt ?? workout.startedAt).shortString) · \(workout.duration.clockString) · \(workout.exercises.count) 动作 · \(unit.fromKg(workout.totalVolumeKg).fmt(0)) \(unit.label)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if workout.strengthScore > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(workout.strengthScore)").font(.subheadline.bold().monospacedDigit())
                    TierBadge(tier: RankTier.tier(for: workout.strengthScore), compact: true)
                }
            }
        }
    }
}
