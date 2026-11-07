import SwiftUI
import SwiftData

struct WorkoutGeneratorView: View {
    let profile: UserProfile
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

    var body: some View {
        NavigationStack {
            Form {
                Section("条件") {
                    Picker("目标", selection: $goal) { ForEach(WorkoutGoal.allCases) { Text($0.name).tag($0) } }
                    Stepper("每周 \(days) 天", value: $days, in: 1...6)
                    Picker("器械", selection: $equipment) { ForEach(EquipmentAccess.allCases) { Text($0.name).tag($0) } }
                    Picker("经验", selection: $experience) { ForEach(ExperienceLevel.allCases) { Text($0.name).tag($0) } }
                    Stepper(weeks == 1 ? "单次训练" : "\(weeks) 周计划", value: $weeks, in: 1...12)
                }
                Section {
                    Button { preview = WorkoutGenerator.generate(goal: goal, daysPerWeek: days, equipment: equipment, experience: experience, weeks: weeks, exercises: exercises); saved = false } label: {
                        Label("生成", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                    }
                } footer: { Text("生成采用确定性规则：按训练天数选择分化，按器械筛选动作，按目标决定组数、次数与休息；多周计划每周按比例加重。") }

                ForEach(preview) { t in
                    Section(t.name) {
                        ForEach(t.items) { item in
                            HStack {
                                Text(item.exerciseName)
                                Spacer()
                                Text("\(item.sets) × \(item.repsLow)–\(item.repsHigh) · 休 \(item.restSeconds)s").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if t.weeks > 1 { Text("每周加重约 \(t.items.first?.weekProgressionPercent.fmt(1) ?? "0")%").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if !preview.isEmpty {
                    Section {
                        Button(saved ? "已保存为预设" : "保存为预设") {
                            for t in preview { context.insert(t) }
                            try? context.save()
                            saved = true
                        }.disabled(saved)
                    } footer: { Text("保存后可在训练页「预设」中直接开始、编辑或重复使用。") }
                }
            }
            .navigationTitle("训练生成器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
