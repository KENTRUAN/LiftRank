import SwiftUI
import SwiftData

struct WorkoutGeneratorView: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var exercises: [Exercise]
    @State private var goal: WorkoutGoal = .hypertrophy
    @State private var days = 3
    @State private var equipment: EquipmentAccess = .fullGym
    @State private var experience: ExperienceLevel = .beginner
    @State private var weeks = 4
    @State private var preview: [WorkoutTemplate] = []
    @State private var saved = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("条件") {
                    Picker("目标", selection: $goal) { ForEach(WorkoutGoal.allCases) { Text($0.name).tag($0) } }
                    Stepper("每周 \(days) 天", value: $days, in: 1...6)
                    Picker("器械", selection: $equipment) { ForEach(EquipmentAccess.allCases) { Text($0.name).tag($0) } }
                    Picker("经验", selection: $experience) { ForEach(ExperienceLevel.allCases) { Text($0.name).tag($0) } }
                    Stepper(value: $weeks, in: 1...12) {
                        Text(weeks == 1 ? L("单次训练") : L("%lld 周计划", weeks))
                    }
                }
                Section {
                    Button {
                        preview = WorkoutGenerator.generate(goal: goal, daysPerWeek: days, equipment: equipment, experience: experience, weeks: weeks, exercises: exercises); saved = false; saveError = nil
                        profile.planGoal = goal; profile.planDaysPerWeek = days; profile.planEquipment = equipment; profile.planExperience = experience
                    } label: {
                        Label("生成", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                    }
                } footer: { Text("生成采用确定性规则：按训练天数选择分化，按器械筛选动作，按目标决定组数、次数与休息；多周计划每周按比例加重。这里的条件也会作为每日自动发布训练的偏好。") }

                ForEach(preview) { t in
                    Section(t.displayName) {
                        ForEach(t.items) { item in
                            HStack {
                                Text(ExerciseNames.display(item.exerciseName))
                                Spacer()
                                Text("\(item.sets) × \(item.repsLow)–\(item.repsHigh) · 休 \(item.restSeconds)s").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if t.weeks > 1 { Text("每周加重约 \(t.items.first?.weekProgressionPercent.fmt(1) ?? "0")%").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if !preview.isEmpty {
                    Section {
                        Button(saved ? "已保存为预设" : "保存为预设") { saveTemplates() }
                            .disabled(saved)
                        if let saveError { Text(saveError).font(.footnote).foregroundStyle(.red) }
                    } footer: { Text("保存后可在训练页「设置训练」中编辑或直接开始；每日训练会按计划顺序自动轮换发布。") }
                }
            }
            .navigationTitle("训练生成器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func saveTemplates() {
        let templates = preview.map {
            WorkoutTemplate(name: $0.name, items: $0.items, weeks: $0.weeks, dayIndex: $0.dayIndex, planName: $0.planName)
        }
        for template in templates { context.insert(template) }
        do {
            try context.save()
            saved = true
            saveError = nil
        } catch {
            for template in templates { context.delete(template) }
            saveError = L("无法保存训练模板，请重试。")
        }
    }

}
