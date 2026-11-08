import SwiftUI
import PhotosUI

struct GymAvatarEditor: View {
    @ObservedObject var store: GymStore
    @Environment(\.dismiss) private var dismiss
    @State private var appearance = AvatarAppearance()
    @State private var prompt = "A friendly athletic game character, clean cartoon style"
    @State private var pickerItem: PhotosPickerItem?
    @State private var selfie: AvatarPreview?
    @State private var preview: AvatarPreview?
    @State private var uploadConsent = false
    @State private var busy = false
    @State private var error: String?
    @State private var usePreset = false
    @State private var loadingPhoto = false
    private var displayProfile: SocialProfile? {
        guard var me = store.me else { return nil }; me.avatar = appearance; return me
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        GymAvatarView(profile: displayProfile, image: usePreset ? nil : preview?.image ?? store.portraits[store.uid], size: 112)
                        Text(preview == nil ? "Your gym character" : "Preview · not published yet").font(.headline)
                        Text("Your character head joins an animated body in the gym.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                Section("Character style") {
                    Picker("Preset", selection: $appearance.preset) { Text("Bolt").tag("bolt"); Text("Leaf").tag("leaf"); Text("Star").tag("star") }
                        .onChange(of: appearance.preset) { _, _ in usePreset = true; preview = nil }
                    Picker("Outfit color", selection: $appearance.color) { Text("Orange").tag("orange"); Text("Blue").tag("blue"); Text("Purple").tag("purple"); Text("Green").tag("green") }
                    Button("Use preset head") { usePreset = true; preview = nil }
                }
                Section("Create with AI") {
                    TextField("Describe your character", text: $prompt, axis: .vertical).lineLimit(2...4)
                    PhotosPicker(selection: $pickerItem, matching: .images) { Label(selfie == nil ? "Add a selfie (optional)" : "Change selfie", systemImage: "photo") }
                    if loadingPhoto { ProgressView("Preparing photo…") }
                    if let image = selfie?.image {
                        HStack { Image(uiImage: image).resizable().scaledToFill().frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 8)); Text("Used only as an appearance reference").font(.caption); Spacer(); Button("Remove") { selfie = nil; pickerItem = nil } }
                    }
                    Toggle("Send my description and selected photo to the AI service", isOn: $uploadConsent).font(.subheadline)
                    Text("The source photo is processed for this request and is not stored by LiftRank. Only the character you approve is saved. You can also generate from text alone. Up to 3 generations per guest per day.").font(.caption).foregroundStyle(.secondary)
                    Button { generate() } label: { Label("Generate preview", systemImage: "sparkles") }
                        .disabled(busy || loadingPhoto || !uploadConsent || store.offlineSample || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if store.offlineSample { Text("AI generation needs a cloud connection. Presets work in the sample.").font(.caption).foregroundStyle(.secondary) }
                }
                if busy { Section { ProgressView("Creating your character…") } }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
                Section {
                    Button { save() } label: { Text(preview == nil ? "Save appearance" : "Approve & publish avatar").frame(maxWidth: .infinity).bold() }.disabled(busy || loadingPhoto)
                }
            }
            .navigationTitle("Your avatar").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .onAppear { appearance = store.me?.avatar ?? AvatarAppearance() }
            .onChange(of: pickerItem) { _, item in
                selfie = nil; loadingPhoto = true
                Task {
                    defer { loadingPhoto = false }
                    do {
                        guard let data = try await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                        let scale = min(1, 1024 / max(image.size.width, image.size.height))
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        let format = UIGraphicsImageRendererFormat(); format.scale = 1
                        let reduced = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                        guard let jpeg = reduced.jpegData(compressionQuality: 0.85), jpeg.count <= 4 * 1024 * 1024 else { throw GymFailure.message("Choose a smaller photo.") }
                        selfie = AvatarPreview(data: jpeg.base64EncodedString(), mimeType: "image/jpeg")
                    } catch { self.error = error.localizedDescription }
                }
            }
        }
    }
    private func generate() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { preview = try await store.api?.generate(prompt: prompt, selfie: selfie); usePreset = false }
            catch { self.error = error.localizedDescription }
        }
    }
    private func save() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                // Publish the generated image first. A provider failure preserves the old avatar.
                if let preview { try await store.api?.approve(preview) }
                try await store.saveAppearance(appearance, reset: usePreset)
                selfie = nil; dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
