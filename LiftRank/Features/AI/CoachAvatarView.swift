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

    private var spec: AvatarSpec { AvatarSpec(ids: ids) }
    private let examples = ["粉色长发、戴墨镜、穿黑色连帽衫的女生，叫小粉", "寸头、小麦肤色、穿红色背心的教练，表情坚定", "蓝色卷发，戴王冠，穿金色长袍，站在星空下", "银白马尾、戴眼镜、灰色 T 恤，背景是健身房"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        AvatarFigureView(spec: spec, front: front)
                            .frame(height: 240).frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation { front.toggle() } }
                        Text(front ? "点击小人查看背面" : "点击小人查看正面").font(.caption2).foregroundStyle(.secondary)
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
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.bold() }
            }
            .onAppear {
                ids = profile.coachAvatarIDs.isEmpty ? AvatarSpec.defaultCoachIDs : profile.coachAvatarIDs
                name = profile.coachName
                intro = profile.coachIntro
            }
            .onChange(of: speech.transcript) { _, t in if speech.isRecording { text = t } }
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
            note = result.usedAI ? "已由 AI 解析描述，可继续逐项微调。" : (AIBackend.isConfigured ? "AI 暂时不可用，已按关键词解析。" : "已按关键词解析，可继续逐项微调。")
            generating = false
        }
    }

    private func save() {
        speech.stop()
        profile.coachAvatarIDs = ids
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.coachName = n.isEmpty ? "小段" : n
        profile.coachIntro = intro
        try? context.save()
        dismiss()
    }
}
