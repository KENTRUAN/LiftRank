import SwiftUI
import SwiftData

/// Define the assistant's look with a sentence ("粉色长发、戴墨镜、穿黑色连帽衫"), then fine-tune part by part.
struct CoachAvatarView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechRecognizer()
    @State private var ids: [String] = AvatarSpec.defaultCoachIDs
    @State private var name = ""
    @State private var intro = ""
    @State private var text = ""
    @State private var generating = false
    @State private var note: String?
    @State private var front = true
    @State private var portraitDraft: Data?
    @State private var savedPortrait: UIImage?
    @State private var usePortrait = true
    @AppStorage(CoachPortraitFile.enabledKey) private var portraitEnabled = true
    @AppStorage(CoachPortraitFile.revisionKey) private var portraitRevision = 0

    private var preview: UIImage? {
        guard usePortrait else { return nil }
        return portraitDraft.flatMap { UIImage(data: $0) } ?? savedPortrait
    }

    private var spec: AvatarSpec { AvatarSpec(ids: ids) }
    private var examples: [String] { [L("粉色长发、戴墨镜、穿黑色连帽衫的女生，叫小粉"), L("寸头、小麦肤色、穿红色背心的教练，表情坚定"), L("蓝色卷发，戴王冠，穿金色长袍，站在星空下"), L("银白马尾、戴眼镜、灰色 T 恤，背景是健身房")] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        if let preview {
                            Image(uiImage: preview).resizable().scaledToFit().frame(height: 240)
                            Button("使用可编辑的小人") { usePortrait = false }
                                .font(.caption)
                        } else {
                            AvatarFigureView(spec: spec, front: front)
                                .frame(height: 240).frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture { withAnimation { front.toggle() } }
                            Text(front ? "点击小人查看背面" : "点击小人查看正面").font(.caption2).foregroundStyle(.secondary)
                            if portraitDraft != nil || savedPortrait != nil {
                                Button("使用 AI 肖像") { usePortrait = true }.font(.caption)
                            }
                        }
                        TextField("助手名字", text: $name).multilineTextAlignment(.center).font(.headline)
                            .padding(8).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10)).frame(maxWidth: 200)
                    }.card()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("用一句话描述外观").font(.headline)
                        HStack(spacing: 8) {
                            Button { speech.isRecording ? speech.stop() : speech.start() } label: {
                                Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill").font(.system(size: 28))
                                    .foregroundStyle(speech.isRecording ? .red : Color.accentColor)
                            }
                            TextField(speech.isRecording ? "正在聆听…" : "例如：粉色长发、戴墨镜、穿黑色连帽衫", text: $text, axis: .vertical).lineLimit(1...3)
                                .padding(8).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                        Button { generate() } label: {
                            Label(generating ? "生成中…" : "生成形象", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).disabled(generating || text.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button { generatePortrait() } label: {
                            Label("生成 AI 肖像", systemImage: "photo").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).disabled(generating || AIBackend.portraitConfig == nil ||
                            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("每次生成一张。保存后会用在小段聊天和助手资料。").font(.caption2).foregroundStyle(.secondary)
                        if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                        if let e = speech.error { Text(e).font(.caption).foregroundStyle(.red) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(examples, id: \.self) { s in
                                    Button { text = s } label: {
                                        Text(s).font(.caption).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        Text(AIBackend.isConfigured ? "描述会先按关键词解析，再交给 AI 理解更复杂的说法。" : "当前按关键词解析；AI 服务开通后可以理解更自由的描述。").font(.caption2).foregroundStyle(.secondary)
                    }.card()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("逐项微调").font(.headline)
                        ForEach(CosmeticSlot.avatarSlots) { slot in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(slot.name).font(.caption).foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(CosmeticCatalog.items(for: slot)) { item in chip(item) }
                                    }
                                }
                            }
                        }
                        Text("助手的形象不需要购买，所有部件都可以使用。").font(.caption2).foregroundStyle(.secondary)
                    }.card()
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("助手形象")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { speech.stop(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.bold().disabled(generating) }
            }
            .onAppear {
                ids = profile.coachAvatarIDs.isEmpty ? AvatarSpec.defaultCoachIDs : profile.coachAvatarIDs
                name = profile.coachName
                intro = profile.coachIntro
                savedPortrait = CoachPortraitFile.image()
                usePortrait = portraitEnabled
            }
            .onChange(of: speech.transcript) { _, t in if !t.isEmpty { text = t } }
            .onDisappear { speech.stop() }
        }
    }

    private func chip(_ item: Cosmetic) -> some View {
        let selected = ids.contains(item.id)
        let colored = [.skin, .hairColor, .outfitColor, .backdrop].contains(item.slot)
        return Button {
            ids = AvatarDescriber.replacing(ids, slot: item.slot, key: item.optionKey)
        } label: {
            HStack(spacing: 5) {
                if colored { Circle().fill(item.primaryColor).frame(width: 12, height: 12).overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 0.5)) }
                Text(item.name).font(.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(selected ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemGroupedBackground), in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }

    private func generate() {
        speech.stop()
        generating = true
        note = nil
        let description = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let result = await AvatarDescriber.describe(description, base: ids)
            withAnimation { ids = result.ids }
            if let n = result.name { name = n }
            intro = description
            note = result.usedAI ? L("已由 AI 解析描述，可继续逐项微调。") : (AIBackend.isConfigured ? L("AI 暂时不可用，已按关键词解析。") : L("已按关键词解析，可继续逐项微调。"))
            generating = false
        }
    }

    private func generatePortrait() {
        guard !generating, let config = AIBackend.portraitConfig else { return }
        let description = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        guard !description.isEmpty else { return }
        speech.stop()
        generating = true
        note = nil
        Task {
            defer { generating = false }
            do {
                let data = try await AIService.generatePortrait(description: description, config: config, subject: "virtual fitness coach")
                guard UIImage(data: data) != nil else { throw AIError.badResponse }
                portraitDraft = data
                usePortrait = true
                note = L("已生成肖像，点「保存」应用。")
            } catch { note = error.localizedDescription }
        }
    }

    private func save() {
        speech.stop()
        profile.coachAvatarIDs = ids
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.coachName = n.isEmpty ? "小段" : n
        profile.coachIntro = intro
        do {
            try context.save()
            if let portraitDraft {
                try CoachPortraitFile.save(portraitDraft)
                portraitRevision += 1
            }
            portraitEnabled = usePortrait
            dismiss()
        } catch { note = error.localizedDescription }
    }
}


enum CoachPortraitFile {
    static let revisionKey = "ai.coach.portraitRevision"
    static let enabledKey = "ai.coach.portraitEnabled"

    private static func url() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true).appendingPathComponent("coach-portrait.jpg")
    }

    static func image() -> UIImage? {
        guard let url = try? url() else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func save(_ data: Data) throws {
        try data.write(to: url(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }


}

struct CoachFace: View {
    let spec: AvatarSpec
    let size: CGFloat
    var showBackdrop = true
    @AppStorage(CoachPortraitFile.revisionKey) private var portraitRevision = 0
    @State private var portrait: UIImage?
    @AppStorage(CoachPortraitFile.enabledKey) private var portraitEnabled = true

    var body: some View {
        Group {
            if portraitEnabled, let portrait {
                Image(uiImage: portrait).resizable().scaledToFill()
            } else {
                AvatarFigureView(spec: spec, bust: true, showBackdrop: showBackdrop)
            }
        }
        .frame(width: size, height: size).clipped()
        .task(id: portraitRevision) { portrait = CoachPortraitFile.image() }
    }
}
