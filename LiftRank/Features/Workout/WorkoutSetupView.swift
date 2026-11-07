import SwiftUI
import SwiftData

/// "设置训练": plan the exercises, sets, reps and rest before starting. Used for templates and the daily plan.
struct WorkoutSetupView: View {
    let isNew: Bool
    let onSave: (String, [TemplateExercise]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var items: [TemplateExercise]
    @State private var showPicker = false
    @State private var expanded: UUID?

    init(title: String, items: [TemplateExercise], isNew: Bool, onSave: @escaping (String, [TemplateExercise]) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _name = State(initialValue: title)
        _items = State(initialValue: items)
    }

    private var totalSets: Int { items.reduce(0) { $0 + $1.sets } }

    var body: some View {
        NavigationStack {
            Form {
                Section("计划") {
                    TextField("训练名称，如：推力日", text: $name)
                    LabeledContent("动作 / 组数", value: "\(items.count) 个 · \(totalSets) 组")
                }
                Section {
                    ForEach($items) { $item in
                        DisclosureGroup(isExpanded: Binding(get: { expanded == item.id }, set: { expanded = $0 ? item.id : nil })) {
                            Stepper("组数 \(item.sets)", value: $item.sets, in: 1...10)
                            Stepper("最少次数 \(item.repsLow)", value: $item.repsLow, in: 1...50)
                                .onChange(of: item.repsLow) { _, v in if item.repsHigh < v { item.repsHigh = v } }
                            Stepper("最多次数 \(item.repsHigh)", value: $item.repsHigh, in: 1...50)
                                .onChange(of: item.repsHigh) { _, v in if item.repsLow > v { item.repsLow = v } }
                            Picker("组间休息", selection: $item.restSeconds) {
                                ForEach([30, 45, 60, 90, 120, 150, 180, 240], id: \.self) { Text("\($0) 秒").tag($0) }
                            }
                        } label: {
                            HStack {
                                Text(item.exerciseName)
                                Spacer()
                                Text("\(item.sets) × \(item.repsLow)–\(item.repsHigh) · 休 \(item.restSeconds)s").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    Button { showPicker = true } label: { Label("添加动作", systemImage: "plus") }
                } header: {
                    Text("动作")
                } footer: {
                    Text("点动作可调整组数、次数与休息；左滑删除，右上角「编辑」可排序。开始训练时会按这里的安排生成清单。")
                }
            }
            .navigationTitle(isNew ? "新建训练" : "设置训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name.trimmingCharacters(in: .whitespaces).isEmpty ? "训练" : name, items)
                        dismiss()
                    }.bold().disabled(items.isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView { ex in
                    items.append(TemplateExercise(exerciseKey: ex.key, exerciseName: ex.name, sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 90))
                }
            }
        }
    }
}
