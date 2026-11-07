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
    @State private var tab = DemoData.initialTab

    var body: some View {
        TabView(selection: $tab) {
            WorkoutHomeView(profile: profile)
                .tabItem { Label("训练", systemImage: "dumbbell.fill") }.tag(0)
            RanksView(profile: profile)
                .tabItem { Label("段位", systemImage: "chart.bar.fill") }.tag(1)
            QuestsView(profile: profile)
                .tabItem { Label("任务", systemImage: "flame.fill") }.tag(2)
            NutritionView(profile: profile)
                .tabItem { Label("饮食", systemImage: "fork.knife") }.tag(3)
            ProfileView(profile: profile)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(4)
        }
    }
}

struct OnboardingView: View {
    private enum Field { case nickname, height, weight }

    @Bindable var profile: UserProfile
    @State private var weightText = ""
    @State private var heightText = ""
    @FocusState private var focusedField: Field?

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
                Section("基础信息") {
                    LabeledContent("昵称") {
                        TextField("昵称", text: $profile.name)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .nickname)
                            .submitLabel(.done)
                    }
                    Picker("性别", selection: $profile.sex) { ForEach(Sex.allCases) { Text($0.label).tag($0) } }
                    BirthdayField(profile: profile) { focusedField = nil }
                    LabeledContent("身高 (cm)") {
                        TextField("身高", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .height)
                    }
                    LabeledContent("体重 (kg)") {
                        TextField("体重", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .weight)
                    }
                }
                Section("单位") {
                    Picker("重量单位", selection: $profile.unit) { ForEach(WeightUnit.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented)
                }
                Section {
                    Button {
                        focusedField = nil
                        if let h = try? Double(heightText, format: .number), h.isFinite, h > 100 { profile.heightCm = h }
                        if let w = try? Double(weightText, format: .number), w.isFinite, w > 30 { profile.bodyweightKg = w }
                        profile.hasOnboarded = true
                    } label: { Text("开始训练").frame(maxWidth: .infinity).bold() }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focusedField = nil }
            .onSubmit { focusedField = nil }
            .navigationTitle("欢迎")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
            .onAppear {
                heightText = profile.heightCm.formatted(.number)
                weightText = profile.bodyweightKg.formatted(.number)
            }
        }
    }
}
