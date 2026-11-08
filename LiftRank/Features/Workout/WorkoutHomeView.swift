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
    @State private var sessionError: String?

    private var unpublished: Workout? { workouts.first { !$0.isPublished } }
    private var history: [Workout] { workouts.filter { $0.isPublished && $0.activity == .strength } }
    private var todayPlan: DailyPlan? { plans.first { $0.dayKey == Date().dayKey && ($0.requestedByUser || $0.sourceRaw == "ai") } }

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            VStack(spacing: 10) {
                TrainerWelcomeView(workout: unpublished, plan: todayPlan).padding(.horizontal)
                Button {
                    app.prefersCardioStart = mode == 1
                    app.perform(.startTodayWorkout)
                } label: {
                    Label(unpublished == nil ? "Start workout" : "Continue workout", systemImage: "play.circle.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).tint(.teal).padding(.horizontal).accessibilityIdentifier("openSocialGym")
                Group { if mode == 0 { strengthList } else { CardioView(profile: profile) } }
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
            .onAppear { if DemoData.autoOpenActive, activeWorkout == nil { activeWorkout = unpublished }; openRequestedWorkout() }
            .onChange(of: app.pending) { _, action in
                if action == .openCardio { mode = 1; app.pending = nil }; openRequestedWorkout()
            }
            .alert("Could not start workout", isPresented: Binding(get: { sessionError != nil }, set: { if !$0 { sessionError = nil } })) {
                Button("OK") { sessionError = nil }
            } message: { Text(sessionError ?? "") }
        }
    }

    private func openRequestedWorkout() {
        guard case .openWorkout(let id) = app.pending else { return }
        if activeWorkout?.id == id { app.pending = nil; return }
        mode = 0 // Dismiss a Cardio-tab presentation before opening the shared workout view.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard app.pending == .openWorkout(id) else { return }
            if let workout = workouts.first(where: { $0.id == id }) { activeWorkout = workout }
            app.pending = nil
        }
    }

    // MARK: - Strength

    private var strengthList: some View {
        List {
            if let p = todayPlan {
                Section("Today") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.title).font(.headline)
                            Text(p.items.isEmpty ? "Rest day" : "\(p.items.count) exercises").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { app.showCoach = true } label: { Image(systemName: "sparkles") }
                        Button { setup = SetupTarget(plan: p) } label: { Image(systemName: "slider.horizontal.3") }
                    }
                }
            }

            Section {
              DisclosureGroup("Training plans") {
                NavigationLink("Plan with AI trainer") { AIStrengthPlanView(profile: profile) }
                if plans.contains(where: { $0.requestedByUser || $0.sourceRaw == "ai" }) {
                    NavigationLink("Requested schedule") { TrainerScheduleView() }
                }
                if let program = AIProgram.load(strength) {
                    NavigationLink("Saved strength plan · \(program.title)") { strengthSchedule(program) }
                }
                if let program = AIProgram.load(combined) {
                    NavigationLink("Saved combined plan · strength") { strengthSchedule(program) }
                }
              }
              DisclosureGroup("Routines") {
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
              }
            }

            Section(history.isEmpty ? "历史" : "历史 · \(history.count) 次") {
                if history.isEmpty {
                    Text("No workouts yet.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(history) { w in
                    NavigationLink { WorkoutDetailView(workout: w, profile: profile) } label: { WorkoutRow(workout: w, unit: profile.unit) }
                }

            }
        }
    }

    private func strengthSchedule(_ program: AIProgram) -> some View {
        AIProgramView(program: program, focus: .strength, exercises: exercises)
    }

    private func startToday() {
        app.prefersCardioStart = false
        app.perform(.startTodayWorkout)
    }

    private func start(title: String, items: [TemplateExercise]) {
        // Every entry starts blank; selecting a preset is a separate explicit step.
        startToday()
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
        return h < 11 ? L("晨间训练") : h < 17 ? L("午后训练") : L("夜间训练")
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
