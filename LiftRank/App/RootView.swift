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
    @Query private var cardio: [CardioSession]
    @State private var app = AppState.shared
    @StateObject private var gym = GymStore()

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            WorkoutHomeView(profile: profile)
                .tabItem { Label("训练", systemImage: "dumbbell.fill") }.tag(0)
            RanksView(profile: profile)
                .tabItem { Label("段位", systemImage: "chart.bar.fill") }.tag(1)
            GymHubView(profile: profile)
                .tabItem { Label("Community", systemImage: "person.2.wave.2.fill") }.tag(AppState.communityTab)
                .badge(gym.inboxCount > 0 ? "" : nil)
            NutritionView(profile: profile)
                .tabItem { Label("饮食", systemImage: "fork.knife") }.tag(3)
            ProfileView(profile: profile)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(4)
        }
        .tint(profile.accentColor)
        .environment(app)
        .environmentObject(gym)
        .toast($app.toast)
        .sheet(isPresented: $app.showRewards) { RewardsView(profile: profile) }
        .onAppear {
            TrainingHealthManager.shared.bind(context: context)
            refreshDailyPlan()
            if app.tab == 2 { app.perform(.openTab(2)) }
            #if DEBUG
            if ProcessInfo.processInfo.environment["LIFTRANK_GYM"] != nil { app.tab = AppState.communityTab }
            #endif
        }
        .onOpenURL { url in
            guard url.scheme == "liftrank", url.host == "cardio", let id = UUID(uuidString: url.lastPathComponent) else { return }
            app.perform(.openWorkout(id))
        }
        .task(id: workouts.first(where: { !$0.isPublished })?.cardioClockRevision) { CardioLiveActivityManager.shared.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshDailyPlan(); handlePending(); CardioLiveActivityManager.shared.refresh() }
            if phase == .background { if gym.room?.isLocal != true { gym.suspend() }; OutdoorWorkoutTracker.shared.follow(nil, foreground: false) }
        }
        .task(id: sharedProfileRevision) { await syncSharedProfile() }
        .task(id: gym.connected) {
            guard gym.connected else { return }
            while !Task.isCancelled {
                if scenePhase == .active { await gym.refreshSpaceInbox() }
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .onChange(of: app.pending) { _, _ in handlePending() }
        .onReceive(TrainingPulse.shared.$now) { now in
            let active = workouts.first(where: { !$0.isPublished })
            gym.setTrainingState(active?.trainingState(at: now) ?? "Ready")
            OutdoorWorkoutTracker.shared.follow(active, foreground: scenePhase == .active)
            if let completed = active?.completedSets.compactMap(\.completedAt).max(), now.timeIntervalSince(completed) < 8 { gym.recordSetCompletion(completed) }
        }
    }

    private var sharedProfileRevision: String {
        [gym.connected.description, gym.uid, gym.sharesRank.description,
         workouts.filter(\.isPublished).map { "\($0.id):\($0.completedSets.count):\($0.strengthScore)" }.sorted().joined(),
         cardio.map { "\($0.id):\($0.durationMinutes)" }.sorted().joined(),
         templates.filter(\.isPublic).map { "\($0.id):\($0.name):\((try? JSONEncoder().encode($0.items).base64EncodedString()) ?? "")" }.sorted().joined(),
         profile.sharedCosmeticIDs.joined(), profile.name, Date().dayKey].joined(separator: "|")
    }
    private func syncSharedProfile() async {
        guard gym.connected, !gym.offlineSample, let me = gym.me else { return }
        let ranks = GymProfileSnapshot.ranks(profile: profile, workouts: workouts, exercises: exercises)
        let total = RankAggregator.overall(muscleScores: Dictionary(uniqueKeysWithValues: ranks.compactMap { key, value in MuscleGroup(rawValue: key).map { ($0, value) } }))
        do {
            // A nickname edited in 我的 is an identity change, which only a full update may publish.
            try await gym.updateProfile(name: profile.name, interests: me.interests, shareRank: gym.sharesRank, gsr: total, cosmetics: profile.sharedCosmeticIDs,
                muscleRanks: ranks, shareActivity: me.shareActivity,
                highlights: me.shareActivity ? GymProfileSnapshot.highlights(profile: profile, workouts: workouts, exercises: exercises, cardio: cardio) : nil,
                routines: GymProfileSnapshot.routines(templates, exercises: exercises), snapshotOnly: me.name == profile.name)
        } catch { gym.error = L("Could not refresh your shared profile. %@", error.localizedDescription) }
    }

    private func refreshDailyPlan() {
        // Training schedules are created only after an explicit trainer request.
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
            app.flash(L("已记录体重 %@ %@", profile.unit.fromKg(kg).fmt(1), profile.unit.label))
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
