import SwiftUI
import SwiftData

struct ProfileView: View {
    private enum Field { case height, weight }

    @Bindable var profile: UserProfile
    @Query private var workouts: [Workout]
    @State private var nicknameDraft = ""
    @State private var showNicknameEditor = false
    @State private var weightText = ""
    @State private var heightText = ""
    @State private var info: String?
    @FocusState private var focusedField: Field?

    private var unitSelection: Binding<WeightUnit> {
        Binding {
            profile.unit
        } set: { unit in
            saveMeasurement(focusedField)
            focusedField = nil
            profile.unit = unit
            weightText = unit.inputText(kg: profile.bodyweightKg)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("个人资料") {
                    nicknameRow
                    Picker("性别（评分曲线）", selection: $profile.sex) { ForEach(Sex.allCases) { Text($0.label).tag($0) } }
                    BirthdayField(profile: profile) { focusedField = nil }
                    LabeledContent("身高 (cm)") {
                        TextField("身高", text: $heightText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .height)
                            .formInputStyle()
                    }
                    LabeledContent("体重 (\(profile.unit.label))") {
                        TextField("体重", text: $weightText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .weight)
                            .formInputStyle()
                    }
                }
                Section("偏好") {
                    Picker("重量单位", selection: unitSelection) { ForEach(WeightUnit.allCases) { Text($0.label).tag($0) } }
                    Picker("默认组间休息", selection: $profile.defaultRestSeconds) { ForEach([45, 60, 90, 120, 150, 180], id: \.self) { Text("\($0) 秒").tag($0) } }
                }
                Section("Pro") {
                    Toggle("Pro 会员（本地模拟）", isOn: $profile.isPro)
                    Text("Pro 包含 AI 拍照记餐、更丰富的段位分析与更长时间范围图表、肌肉恢复追踪。实际订阅需接入 App Store 内购；此开关仅用于开发预览。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("计算工具") {
                    NavigationLink("1RM 计算器（Epley / Brzycki）") { OneRMCalculatorView(unit: profile.unit) }
                    NavigationLink("评分计算器") { RankCalculatorView(profile: profile) }
                    NavigationLink("杠铃片计算") { PlateCalculatorView(targetKg: 100, unit: profile.unit) }
                    NavigationLink("TDEE 与营养目标") { NutritionGoalsView(profile: profile) }
                    NavigationLink("体脂计算器") { BodyFatCalculatorView(profile: profile) }
                }
                Section("连接与数据") {
                    Button { info = "Apple Health 集成（读取步数、热量、身体测量，写入训练）将在下一版本接入 HealthKit。" } label: { Label("Apple Health", systemImage: "heart.fill") }
                    Button { info = "Strava 授权需通过 Strava 的 OAuth 权限页完成；发布为单向（本软件 → Strava），不导入跑步/骑行记录。当前版本尚未接入。" } label: { Label("连接 Strava 账号", systemImage: "figure.run") }
                    Button { info = "从 Strong / Hevy 导出的 CSV 导入训练历史与个人纪录，将在下一版本提供。" } label: { Label("从 Strong / Hevy 导入", systemImage: "square.and.arrow.down") }
                    Button { info = "好友动态、发现页、点赞评论与好友/全球/地区排行榜需要账号与云端服务，当前为本地离线版本。" } label: { Label("好友与排行榜", systemImage: "person.2.fill") }
                }
                Section("统计") {
                    LabeledContent("已发布训练", value: "\(workouts.filter { $0.isPublished }.count)")
                    LabeledContent("累计训练量", value: "\(profile.unit.fromKg(workouts.filter { $0.isPublished }.reduce(0) { $0 + $1.totalVolumeKg }).fmt(0)) \(profile.unit.label)")
                    LabeledContent("累计 XP / Eggs", value: "\(profile.totalXP) / \(profile.eggs)")
                }
                Section("关于评分") {
                    Text("估算 1RM = 重量 × (1 + 次数 ÷ 30)，次数上限 30；填写 RPE 时按剩余次数（RIR）调整；自重动作使用等效负重模型。评分结合体重与男/女曲线，范围 1–1000，对应 Wood 到 Olympian 九个段位。肌群段位由该肌群动作的最佳评分加权得到，总体评分 GSR 中更强的肌群占更高权重。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("我的")
            .scrollDismissesKeyboard(.interactively)
            .onSubmit { focusedField = nil }
            .onChange(of: focusedField) { previous, _ in saveMeasurement(previous) }
            .onAppear {
                weightText = profile.unit.inputText(kg: profile.bodyweightKg)
                heightText = profile.heightCm.formatted(.number)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
            .alert("说明", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) { Button("好") {} } message: { Text(info ?? "") }
        }
    }

    private var nicknameRow: some View {
        let nickname = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = nickname.isEmpty ? "设置昵称" : nickname
        return Button {
            focusedField = nil
            nicknameDraft = nickname
            showNicknameEditor = true
        } label: {
            LabeledContent("昵称") {
                Text(displayName).foregroundStyle(Color.accentColor)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("昵称")
        .accessibilityValue(displayName)
        .alert("编辑昵称", isPresented: $showNicknameEditor) {
            TextField("输入昵称", text: $nicknameDraft)
            Button("取消", role: .cancel) {}
            Button("保存") { profile.updateNickname(nicknameDraft) }
                .disabled(nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func saveMeasurement(_ field: Field?) {
        switch field {
        case .height:
            if let value = try? Double(heightText, format: .number), value.isFinite, value > 0 {
                profile.heightCm = value
            } else {
                heightText = profile.heightCm.formatted(.number)
            }
        case .weight:
            let savedText = profile.unit.inputText(kg: profile.bodyweightKg)
            guard weightText != savedText else { return }
            if let value = try? Double(weightText, format: .number), value.isFinite, value > 0 {
                profile.bodyweightKg = profile.unit.toKg(value)
            } else {
                weightText = savedText
            }
        case nil:
            break
        }
    }
}

struct OneRMCalculatorView: View {
    let unit: WeightUnit
    @State private var weight = "100"
    @State private var reps = 5
    var body: some View {
        let w = Double(weight) ?? 0
        let epley = StrengthScoring.epley(weightKg: w, reps: reps)
        let brzycki = StrengthScoring.brzycki(weightKg: w, reps: reps)
        Form {
            Section("输入") {
                LabeledContent("重量 (\(unit.label))") {
                    TextField("重量", text: $weight).keyboardType(.decimalPad).formInputStyle()
                }
                Stepper("次数 \(reps)", value: $reps, in: 1...30)
            }
            Section("估算 1RM") {
                LabeledContent("Epley", value: "\(epley.fmt(1)) \(unit.label)")
                LabeledContent("Brzycki", value: "\(brzycki.fmt(1)) \(unit.label)")
            }
            Section("训练强度对照（Epley）") {
                ForEach([(100, 1), (95, 2), (90, 4), (85, 6), (80, 8), (75, 10), (70, 12), (65, 15), (60, 20)], id: \.0) { pct, r in
                    HStack { Text("\(pct)%"); Spacer(); Text("\((epley * Double(pct) / 100).fmt(1)) \(unit.label)").monospacedDigit(); Text("≈ \(r) 次").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing) }
                }
            }
        }
        .navigationTitle("1RM 计算器")
        .navigationBarTitleDisplayMode(.inline)
    }
}
