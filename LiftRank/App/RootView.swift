import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        if let profile = profiles.first {
            if profile.hasOnboarded {
                RootTabView(profile: profile)
            } else {
                OnboardingView(profile: profile)
            }
        } else {
            ProgressView()
        }
    }
}

struct RootTabView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var templates: [WorkoutTemplate]
    @Query private var exercises: [Exercise]
    @Query private var workouts: [Workout]
    @Query private var plans: [DailyPlan]
    @State private var app = AppState.shared

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            WorkoutHomeView(profile: profile)
                .tabItem { Label("训练", systemImage: "dumbbell.fill") }.tag(0)
            RanksView(profile: profile)
                .tabItem { Label("段位", systemImage: "chart.bar.fill") }.tag(1)
            RewardsView(profile: profile)
                .tabItem { Label("奖励", systemImage: "gift.fill") }.tag(2)
            NutritionView(profile: profile)
                .tabItem { Label("饮食", systemImage: "fork.knife") }.tag(3)
            ProfileView(profile: profile)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(4)
        }
        .tint(profile.accentColor)
        .environment(app)
        .toast($app.toast)
        .onAppear(perform: refreshDailyPlan)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshDailyPlan(); handlePending() } }
        .onChange(of: app.pending) { _, _ in handlePending() }
    }

    private func refreshDailyPlan() {
        if profile.friendCode.isEmpty { profile.friendCode = String(UUID().uuidString.prefix(8)) }
        DailyPlanEngine.ensureToday(profile: profile, templates: templates, exercises: exercises, workouts: workouts, plans: plans, context: context)
    }

    private func handlePending() {
        guard let action = app.pending else { return }
        switch action {
        case .logBodyweight(let kg):
            guard kg > 20, kg < 400 else { break }
            context.insert(BodyMeasurement(date: Date(), metric: .weight, value: kg))
            profile.bodyweightKg = kg
            try? context.save()
            app.pending = nil
            app.flash("已记录体重 \(profile.unit.fromKg(kg).fmt(1)) \(profile.unit.label)")
        default:
            break
        }
    }
}

struct OnboardingView: View {
    private enum Field { case nickname, height, weight }

    @Bindable var profile: UserProfile
    @State private var nickname: String
    @State private var weightText: String
    @State private var draftWeightKg: Double
    @State private var heightText: String
    @FocusState private var focusedField: Field?

    init(profile: UserProfile) {
        self.profile = profile
        _nickname = State(initialValue: profile.name)
        _weightText = State(initialValue: profile.unit.inputText(kg: profile.bodyweightKg))
        _draftWeightKg = State(initialValue: profile.bodyweightKg)
        _heightText = State(initialValue: profile.heightCm.formatted(.number))
    }

    private var enteredWeightKg: Double {
        let unit = profile.unit
        guard weightText != unit.inputText(kg: draftWeightKg),
              let value = try? Double(weightText, format: .number), value.isFinite,
              unit.toKg(value) > 30 else {
            return draftWeightKg
        }
        return unit.toKg(value)
    }

    private var unitSelection: Binding<WeightUnit> {
        Binding {
            profile.unit
        } set: { unit in
            guard unit != profile.unit else { return }
            draftWeightKg = enteredWeightKg
            focusedField = nil
            profile.unit = unit
            weightText = unit.inputText(kg: draftWeightKg)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("把力量训练变成段位进阶").font(.title2.bold())
                        Text("填写基础信息后，系统会把你每组的重量与次数换算为力量评分，并映射到 Wood 到 Olympian 的九个段位。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    LabeledContent("昵称") {
                        TextField("昵称", text: $nickname)
                            .focused($focusedField, equals: .nickname)
                            .submitLabel(.done)
                            .formInputStyle()
                    }
                    Picker("性别", selection: $profile.sex) { ForEach(Sex.allCases) { Text($0.label).tag($0) } }
                    BirthdayField(profile: profile) { focusedField = nil }
                    LabeledContent("身高 (cm)") {
                        TextField("身高", text: $heightText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .height)
                            .formInputStyle()
                    }
                    HStack {
                        Text("体重")
                        Spacer()
                        TextField("体重", text: $weightText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .weight)
                            .formInputStyle()
                            .frame(maxWidth: 110)
                        Picker("单位", selection: unitSelection) { ForEach(WeightUnit.allCases) { Text($0.label).tag($0) } }
                            .pickerStyle(.segmented)
                            .frame(width: 96)
                            .labelsHidden()
                    }
                } header: {
                    Text("基础信息")
                } footer: {
                    Text("重量单位可随时在「我的」中切换；输入会自动换算。")
                }
                Section {
                    Button {
                        focusedField = nil
                        if let h = try? Double(heightText, format: .number), h.isFinite, h > 100 { profile.heightCm = h }
                        profile.bodyweightKg = enteredWeightKg
                        profile.completeOnboarding(name: nickname)
                    } label: { Text("开始训练").frame(maxWidth: .infinity).bold() }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onSubmit { focusedField = nil }
            .navigationTitle("欢迎")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
        }
    }
}
