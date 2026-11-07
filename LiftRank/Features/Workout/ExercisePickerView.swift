import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    let onSelect: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var group: MuscleGroup?
    @State private var showCreate = false

    private var filtered: [Exercise] {
        exercises.filter { e in
            (group == nil || e.muscleGroup == group) &&
            (search.isEmpty || e.name.localizedCaseInsensitiveContains(search) || e.nameEn.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip(nil, "全部")
                        ForEach(MuscleGroup.allCases) { g in chip(g, g.name) }
                    }.padding(.horizontal).padding(.vertical, 8)
                }
                List(filtered) { e in
                    Button { onSelect(e); dismiss() } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name).foregroundStyle(.primary)
                                Text("\(e.muscleGroup.name) · \(e.equipment.name)\(e.isCustom ? " · 自定义" : "")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if e.isRanked { Image(systemName: "chart.bar.fill").foregroundStyle(Color.accentColor).font(.caption) }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $search, prompt: "搜索动作（中文或英文）")
            }
            .navigationTitle("选择动作 · \(exercises.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { showCreate = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showCreate) { CustomExerciseView() }
        }
    }

    private func chip(_ g: MuscleGroup?, _ title: String) -> some View {
        Button(title) { group = g }
            .font(.caption.bold())
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(group == g ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(group == g ? .white : .primary)
    }
}

struct CustomExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var group: MuscleGroup = .chest
    @State private var equipment: Equipment = .dumbbell
    @State private var instructions = ""
    @State private var photo: UIImage?
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            Form {
                Section("动作") {
                    InputRow("名称") {
                        TextField("名称", text: $name).formInputStyle(maxWidth: .infinity)
                    }
                    InputRow("目标肌群") {
                        Picker("目标肌群", selection: $group) { ForEach(MuscleGroup.allCases) { Text($0.name).tag($0) } }
                            .labelsHidden().pickerStyle(.menu)
                    }
                    InputRow("器械") {
                        Picker("器械", selection: $equipment) { ForEach(Equipment.allCases) { Text($0.name).tag($0) } }
                            .labelsHidden().pickerStyle(.menu)
                    }
                }
                Section("说明") {
                    InputRow("动作说明") {
                        TextField("动作要点、注意事项", text: $instructions, axis: .vertical)
                            .lineLimit(3...6)
                            .formInputStyle(maxWidth: .infinity)
                    }
                }
                Section("图片") {
                    if let photo { Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 180) }
                    Button(photo == nil ? "拍摄或选择图片" : "重新选择") { showCamera = true }
                }
                Section { Text("自定义动作不参与段位评分，但会计入训练量、组数与任务进度。").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("自定义动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let key = "custom_\(UUID().uuidString.prefix(8))"
                        let e = Exercise(key: key, name: name.trimmingCharacters(in: .whitespaces), nameEn: "", muscle: group, equipment: equipment,
                                         isCardio: group == .cardio, isCustom: true, isRanked: false, instructions: instructions)
                        e.imageData = photo?.jpegData(compressionQuality: 0.7)
                        context.insert(e)
                        try? context.save()
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showCamera) { ImagePicker(image: $photo) }
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
