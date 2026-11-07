import SwiftUI
import SwiftData

struct NutritionView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query private var customMeals: [CustomMeal]
    @State private var mode = 0
    @State private var day = Date()
    @State private var editor: MealType?
    @State private var alert: String?

    private var targets: MacroTargets {
        let tdee = NutritionEngine.tdee(sex: profile.sex, weightKg: profile.bodyweightKg, heightCm: profile.heightCm, age: profile.age, activity: profile.activityLevel)
        return NutritionEngine.targets(tdee: tdee, weightKg: profile.bodyweightKg, goal: profile.nutritionGoal)
    }
    private var todays: [FoodEntry] { foods.filter { $0.date.dayKey == day.dayKey } }

    var body: some View {
        NavigationStack {
            Group {
                if mode == 0 { foodLog } else { BodyLogView(profile: profile) }
            }
            .navigationTitle(mode == 0 ? "饮食" : "身体数据")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $mode) { Text("饮食").tag(0); Text("身体").tag(1) }.pickerStyle(.segmented).frame(width: 180)
                }
            }
        }
    }

    private var foodLog: some View {
        let t = targets
        let kcal = todays.reduce(0) { $0 + $1.kcal }
        let p = todays.reduce(0) { $0 + $1.protein }
        let f = todays.reduce(0) { $0 + $1.fat }
        let c = todays.reduce(0) { $0 + $1.carbs }
        return List {
            Section {
                DatePicker("日期", selection: $day, displayedComponents: .date)
                HStack(spacing: 16) {
                    MacroRing(title: "热量", value: kcal, target: t.kcal, unit: "kcal", color: .orange)
                    MacroRing(title: "蛋白", value: p, target: t.protein, unit: "g", color: .red)
                    MacroRing(title: "脂肪", value: f, target: t.fat, unit: "g", color: .yellow)
                    MacroRing(title: "碳水", value: c, target: t.carbs, unit: "g", color: .blue)
                }.padding(.vertical, 6)
                NavigationLink { NutritionGoalsView(profile: profile) } label: {
                    Label("目标：\(profile.nutritionGoal.name) · \(t.kcal.fmt(0)) kcal", systemImage: "target")
                }
            }
            Section("添加") {
                Button { alert = "条码录入需要相机与食品数据库服务，当前版本未接入。可先用手动录入或自定义餐食。" } label: { Label("扫描条码", systemImage: "barcode.viewfinder") }
                Button { alert = profile.isPro ? "AI 拍照记餐需要联网的识别服务，当前版本未接入后端。" : "AI 拍照记餐属于 Pro 功能，且需要联网。" } label: {
                    HStack { Label("AI 拍照记餐", systemImage: "camera.fill"); Spacer(); Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                }
            }
            ForEach(MealType.allCases) { meal in
                Section {
                    let items = todays.filter { $0.meal == meal }
                    ForEach(items) { e in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(e.name)
                                Text("P \(e.protein.fmt(0)) · F \(e.fat.fmt(0)) · C \(e.carbs.fmt(0))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(e.kcal.fmt(0)) kcal").font(.subheadline.monospacedDigit())
                        }
                    }
                    .onDelete { idx in idx.map { items[$0] }.forEach(context.delete); try? context.save() }
                    Button { editor = meal } label: { Label("添加到\(meal.name)", systemImage: "plus").font(.subheadline) }
                } header: {
                    HStack { Text(meal.name); Spacer(); Text("\(todays.filter { $0.meal == meal }.reduce(0) { $0 + $1.kcal }.fmt(0)) kcal") }
                }
            }
        }
        .sheet(item: $editor) { meal in FoodEntryEditor(meal: meal, date: day, customMeals: customMeals) }
        .alert("提示", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) { Button("好") {} } message: { Text(alert ?? "") }
    }
}

struct MacroRing: View {
    let title: String; let value: Double; let target: Double; let unit: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 6)
                Circle().trim(from: 0, to: target > 0 ? CGFloat(min(1, value / target)) : 0).stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(value.fmt(0)).font(.caption.bold().monospacedDigit())
            }.frame(width: 58, height: 58)
            Text(title).font(.caption2)
            Text("/ \(target.fmt(0)) \(unit)").font(.system(size: 9)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

struct FoodEntryEditor: View {
    let meal: MealType
    let date: Date
    let customMeals: [CustomMeal]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    @State private var saveAsCustom = false
    @State private var search = ""

    private var presets: [(String, Double, Double, Double, Double)] {
        [("鸡胸肉 100g", 165, 31, 3.6, 0), ("白米饭 1 碗", 230, 4.5, 0.5, 50), ("全蛋 1 个", 72, 6.3, 4.8, 0.4), ("牛奶 250ml", 150, 8, 8, 12),
         ("燕麦 50g", 190, 6.5, 3.5, 33), ("香蕉 1 根", 105, 1.3, 0.4, 27), ("乳清蛋白 1 勺", 120, 24, 1.5, 3), ("牛肉 100g", 250, 26, 15, 0),
         ("三文鱼 100g", 208, 20, 13, 0), ("红薯 150g", 130, 2.4, 0.2, 30), ("花生酱 1 勺", 95, 4, 8, 3), ("希腊酸奶 170g", 100, 17, 0.7, 6)]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("快速选择") {
                    TextField("搜索食品", text: $search)
                    ForEach(customMeals.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { m in
                        Button { fill(m.name, m.kcal, m.protein, m.fat, m.carbs) } label: { row(m.name, m.kcal, custom: true) }
                    }
                    ForEach(presets.filter { search.isEmpty || $0.0.localizedCaseInsensitiveContains(search) }, id: \.0) { p in
                        Button { fill(p.0, p.1, p.2, p.3, p.4) } label: { row(p.0, p.1, custom: false) }
                    }
                }
                Section("\(meal.name) · 手动录入") {
                    TextField("名称", text: $name)
                    numField("热量 kcal", $kcal); numField("蛋白质 g", $protein); numField("脂肪 g", $fat); numField("碳水 g", $carbs)
                    Toggle("保存为自定义餐食", isOn: $saveAsCustom)
                }
            }
            .navigationTitle("记录饮食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let k = Double(kcal) ?? 0, p = Double(protein) ?? 0, f = Double(fat) ?? 0, c = Double(carbs) ?? 0
                        context.insert(FoodEntry(date: date, meal: meal, name: name, kcal: k, protein: p, fat: f, carbs: c, source: saveAsCustom ? "custom" : "manual"))
                        if saveAsCustom { context.insert(CustomMeal(name: name, kcal: k, protein: p, fat: f, carbs: c)) }
                        try? context.save()
                        dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }

    private func row(_ n: String, _ k: Double, custom: Bool) -> some View {
        HStack { Text(n).foregroundStyle(.primary); if custom { Text("自定义").font(.caption2).foregroundStyle(.secondary) }; Spacer(); Text("\(k.fmt(0)) kcal").foregroundStyle(.secondary) }
    }
    private func numField(_ label: String, _ b: Binding<String>) -> some View {
        HStack { Text(label); Spacer(); TextField("0", text: b).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
    }
    private func fill(_ n: String, _ k: Double, _ p: Double, _ f: Double, _ c: Double) {
        name = n; kcal = k.fmt(0); protein = p.fmt(1); fat = f.fmt(1); carbs = c.fmt(1)
    }
}

struct NutritionGoalsView: View {
    @Bindable var profile: UserProfile
    var body: some View {
        let bmr = NutritionEngine.bmr(sex: profile.sex, weightKg: profile.bodyweightKg, heightCm: profile.heightCm, age: profile.age)
        let tdee = bmr * profile.activityLevel.multiplier
        let t = NutritionEngine.targets(tdee: tdee, weightKg: profile.bodyweightKg, goal: profile.nutritionGoal)
        Form {
            Section("输入（来自个人资料）") {
                LabeledContent("性别 / 年龄", value: "\(profile.sex.label) / \(profile.age)")
                LabeledContent("身高 / 体重", value: "\(profile.heightCm.fmt(0)) cm / \(profile.unit.fromKg(profile.bodyweightKg).fmt(1)) \(profile.unit.label)")
                Picker("活动水平", selection: $profile.activityLevel) { ForEach(ActivityLevel.allCases) { Text($0.name).tag($0) } }
                Picker("目标", selection: $profile.nutritionGoal) { ForEach(NutritionGoal.allCases) { Text($0.name).tag($0) } }.pickerStyle(.segmented)
            }
            Section("能量") {
                LabeledContent("基础代谢 BMR (Mifflin–St Jeor)", value: "\(bmr.fmt(0)) kcal")
                LabeledContent("每日消耗 TDEE", value: "\(tdee.fmt(0)) kcal")
                LabeledContent("目标热量", value: "\(t.kcal.fmt(0)) kcal")
            }
            Section("每日营养目标") {
                LabeledContent("蛋白质（2.2 g/kg）", value: "\(t.protein.fmt(0)) g")
                LabeledContent("脂肪（1 g/kg）", value: "\(t.fat.fmt(0)) g")
                LabeledContent("碳水（剩余热量，≥20%）", value: "\(t.carbs.fmt(0)) g")
            }
            Section { Text("减脂为维持热量 −500 kcal，增肌为 +300 kcal。热量较低时会按比例缩放蛋白质与脂肪，为碳水保留至少 20% 热量。").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("营养目标")
        .navigationBarTitleDisplayMode(.inline)
    }
}
