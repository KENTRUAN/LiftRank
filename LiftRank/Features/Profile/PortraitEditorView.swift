import SwiftUI
import PhotosUI

/// The player's one AI portrait. It replaces the character head in 我的, on the ranks page and,
/// while the community profile is connected, for gym members. Generation uses the community
/// service when connected (text + optional selfie), otherwise the developer-configured image API.
struct PortraitEditorView: View {
    let profile: UserProfile
    @EnvironmentObject private var store: GymStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TrainingPortraitFile.revisionKey) private var portraitRevision = 0
    @State private var current: UIImage?
    @State private var preview: AvatarPreview?
    @State private var description = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var selfie: AvatarPreview?
    @State private var loadingPhoto = false
    @State private var consent = false
    @State private var busy = false
    @State private var error: String?

    private var prompt: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cloud: GymAPI? { store.connected && !store.offlineSample ? store.api : nil }
    private var local: AIConfig? { AIBackend.portraitConfig }
    private var available: Bool { cloud != nil || local != nil }
    private var canGenerate: Bool {
        !busy && !loadingPhoto && consent && !prompt.isEmpty && prompt.count <= 500 && (cloud != nil || (local != nil && selfie == nil))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Group {
                            if let image = preview?.image ?? current {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                AvatarFigureView(spec: profile.avatar, bust: true, showBackdrop: false)
                                    .padding(8).background(Color(.tertiarySystemGroupedBackground))
                            }
                        }
                        .frame(width: 150, height: 150).clipShape(Circle())
                        .overlay(Circle().stroke(preview == nil ? Color.secondary.opacity(0.25) : Color.accentColor, lineWidth: 3))
                        Text(preview != nil ? "预览 · 尚未应用" : current != nil ? "当前肖像" : "当前使用小人形象").font(.headline)
                        Text("肖像会出现在「我的」、段位页的训练化身，以及健身房里其他成员看到的你。")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                Section {
                    TextField("例如：蓝色短发、黑色背心、漫画风", text: $description, axis: .vertical).lineLimit(2...4)
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(selfie == nil ? "添加一张自拍（可选）" : "更换自拍", systemImage: "photo")
                    }.disabled(cloud == nil)
                    if cloud == nil { Text("自拍参考需要先连接社区资料；仅凭文字也可以生成。").font(.caption).foregroundStyle(.secondary) }
                    if loadingPhoto { ProgressView("正在处理照片…") }
                    if let image = selfie?.image {
                        HStack {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("仅作为外观参考，不会保存。").font(.caption)
                            Spacer()
                            Button("移除") { selfie = nil; pickerItem = nil }
                        }
                    }
                    Toggle("同意把描述和所选照片发送给 AI 服务", isOn: $consent).font(.subheadline)
                    Button { generate() } label: { Label(busy ? "正在生成…" : "生成肖像", systemImage: "sparkles") }.disabled(!canGenerate)
                    if prompt.count > 500 { Text("描述最多 500 个字。").font(.caption).foregroundStyle(.secondary) }
                    if !available { Text("当前构建没有可用的图片生成服务：连接社区资料，或由开发者配置 OpenAI 图片接口。").font(.caption).foregroundStyle(.orange) }
                } header: {
                    Text("描述你的形象")
                } footer: {
                    Text("原始照片只用于这一次请求，不会被保存。只有你应用的肖像会被保留；已连接社区时每天最多生成 3 次。")
                }
                if busy { Section { ProgressView("请稍候…") } }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
                Section {
                    if preview != nil {
                        Button { apply() } label: { Text("应用这张肖像").frame(maxWidth: .infinity).bold() }.disabled(busy)
                        Button("放弃预览", role: .cancel) { preview = nil }.disabled(busy)
                    }
                    if current != nil {
                        Button("移除肖像，改用小人形象", role: .destructive) { remove() }.disabled(busy)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("AI 肖像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .task {
                current = TrainingPortraitFile.image()
                // A portrait approved on another device is adopted locally on first sight.
                if current == nil, let remote = store.portraits[store.uid], let data = remote.jpegData(compressionQuality: 0.9) {
                    try? TrainingPortraitFile.save(data); portraitRevision += 1; current = remote
                }
            }
            .onChange(of: pickerItem) { _, item in loadSelfie(item) }
        }
    }

    private func loadSelfie(_ item: PhotosPickerItem?) {
        selfie = nil
        guard let item else { return }
        loadingPhoto = true
        Task {
            defer { loadingPhoto = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                let scale = min(1, 1024 / max(image.size.width, image.size.height))
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let reduced = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                guard let jpeg = reduced.jpegData(compressionQuality: 0.85), jpeg.count <= 4 * 1024 * 1024 else { throw GymFailure.message(L("请选择一张小一点的照片。")) }
                selfie = AvatarPreview(data: jpeg.base64EncodedString(), mimeType: "image/jpeg")
            } catch { self.error = error.localizedDescription }
        }
    }

    private func generate() {
        guard canGenerate else { return }
        busy = true; error = nil
        let requested = prompt
        Task {
            defer { busy = false }
            do {
                if let cloud, selfie != nil || local == nil {
                    preview = try await cloud.generate(prompt: requested, selfie: selfie)
                } else if let local {
                    let data = try await AIService.generatePortrait(description: requested, config: local)
                    guard UIImage(data: data) != nil else { throw AIError.badResponse }
                    let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
                    preview = AvatarPreview(data: data.base64EncodedString(), mimeType: png ? "image/png" : "image/jpeg")
                } else { throw AIError.notConfigured }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func apply() {
        guard let preview, let data = Data(base64Encoded: preview.data), UIImage(data: data) != nil else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                // Publish first: a failed upload keeps the previous portrait everywhere.
                if let cloud { try await cloud.approve(preview) }
                try TrainingPortraitFile.save(data)
                portraitRevision += 1
                current = UIImage(data: data)
                self.preview = nil; selfie = nil; pickerItem = nil
            } catch { self.error = error.localizedDescription }
        }
    }

    private func remove() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                if cloud != nil, let me = store.me { try await store.saveAppearance(me.avatar, reset: true) }
                try TrainingPortraitFile.remove()
                portraitRevision += 1
                current = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// The portrait file shared by 我的, the ranks page and the community profile.
enum TrainingPortraitFile {
    static let revisionKey = "trainingAvatar.portraitRevision"

    static func image() -> UIImage? {
        guard let url = try? url() else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func save(_ data: Data) throws {
        try data.write(to: url(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove() throws {
        let url = try url()
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private static func url() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("training-avatar-portrait.jpg")
    }
}
