import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

struct MealEstimate: Codable {
    var name: String
    var kcal: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    let notes: String

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...10_000).contains(kcal)
            && [protein, fat, carbs].allSatisfy { (0...1000).contains($0) }
    }
}

struct MealPhotoView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var selected: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var takingPhoto = false
    @State private var notes = ""
    @State private var meal: MealType = .lunch
    @State private var estimate: MealEstimate?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 220)
                    }
                    Button("拍摄餐食") { openCamera() }.disabled(loading)
                    PhotosPicker("从照片图库选择", selection: $selected, matching: .images).disabled(loading)
                    TextField("分量、食材或用油（可选）", text: $notes, axis: .vertical)
                    Button(loading ? "正在识别…" : "发送照片并估算") { analyze() }
                        .disabled(loading || photo == nil || AIBackend.portraitConfig == nil)
                } footer: {
                    Text("点击估算才会将照片和备注发送给配置的 AI 服务。份量和营养值是估算，保存前可更正。")
                }
                if let estimateBinding = Binding($estimate) {
                    Section("确认后计入饮食记录") {
                        Picker("餐次", selection: $meal) { ForEach(MealType.allCases) { Text($0.name).tag($0) } }
                        TextField("餐食名称", text: estimateBinding.name)
                        amount(L("热量（kcal）"), estimateBinding.kcal)
                        amount(L("蛋白质（g）"), estimateBinding.protein)
                        amount(L("脂肪（g）"), estimateBinding.fat)
                        amount(L("碳水（g）"), estimateBinding.carbs)
                        Text(estimateBinding.wrappedValue.notes).font(.footnote).foregroundStyle(.secondary)
                        Button("保存这餐") { save(estimateBinding.wrappedValue) }
                            .disabled(loading || !estimateBinding.wrappedValue.isValid)
                    }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                if AIBackend.portraitConfig == nil { Text("需要配置支持图片的 OpenAI 接口。").font(.footnote) }
            }
            .navigationTitle("AI 拍照记餐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: $takingPhoto) { MealCamera { usePhoto($0) }.ignoresSafeArea() }
            .task(id: selected) {
                guard let item = selected else { return }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { throw AIError.badResponse }
                    if !Task.isCancelled && selected == item { usePhoto(image) }
                } catch {
                    if !Task.isCancelled && selected == item { self.error = L("无法打开这张照片。") }
                }
            }
        }
    }

    private func amount(_ title: String, _ value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }

    private func usePhoto(_ image: UIImage) {
        photo = image
        estimate = nil
        error = nil
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            error = L("此设备没有可用的相机，请从照片图库选择。")
            return
        }
        Task {
            if await AVCaptureDevice.requestAccess(for: .video) { takingPhoto = true }
            else { error = L("请在系统设置中允许相机，或从照片图库选择。") }
        }
    }

    private func analyze() {
        guard !loading, let photo, let config = AIBackend.portraitConfig else { return }
        guard let jpeg = Self.uploadJPEG(photo) else { error = L("无法处理这张照片。"); return }
        let description = String(notes.prefix(400))
        loading = true
        error = nil
        Task {
            defer { loading = false }
            do { estimate = try await AIService.estimateMeal(jpeg: jpeg, notes: description, config: config) }
            catch { self.error = error.localizedDescription }
        }
    }

    static func uploadJPEG(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 640 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.72, 0.55, 0.38, 0.22] {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= 155_000 { return data }
        }
        return nil
    }

    private func save(_ result: MealEstimate) {
        guard result.isValid else { return }
        let entry = FoodEntry(date: date, meal: meal, name: result.name, kcal: result.kcal,
                              protein: result.protein, fat: result.fat, carbs: result.carbs, source: "ai_photo")
        context.insert(entry)
        do { try context.save(); dismiss() }
        catch { context.delete(entry); self.error = L("保存失败，请重试。") }
    }
}

private struct MealCamera: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let view: MealCamera
        init(_ view: MealCamera) { self.view = view }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { view.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { view.onImage(image) }
            view.dismiss()
        }
    }
}
