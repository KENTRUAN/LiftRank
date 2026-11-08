import SwiftUI
import SwiftData

/// "AI 助手" settings: the assistant's character plus the status of the developer-provided backend.
struct AIAssistantView: View {
    @Bindable var profile: UserProfile
    @State private var status: String?
    @State private var testing = false
    @State private var testFailed = false
    @State private var showAvatar = false
    @AppStorage(CoachHistory.key) private var previousConversation = Data()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    CoachFace(spec: profile.coachAvatar, size: 76).clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.coachName).font(.headline)
                        Text(profile.coachIntro.isEmpty ? "用一句话描述，就能定义助手的样子。" : profile.coachIntro)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer()
                }
                Button { showAvatar = true } label: { Label("定义助手形象", systemImage: "wand.and.stars") }
                Button { AppState.shared.perform(.openCoach) } label: { Label("Open private workout trainer", systemImage: "bubble.left.and.bubble.right.fill") }
            } header: {
                Text("助手形象")
            }
            Section {
                LabeledContent("服务", value: AIBackend.displayName)
                LabeledContent("状态", value: AIBackend.isConfigured ? L("已开通") : L("未开通"))
                Button(testing ? "测试中…" : "测试连接") { testConnection() }.disabled(testing || !AIBackend.isConfigured)
                if let status { Text(status).font(.footnote).foregroundStyle(testFailed ? .red : .secondary) }
            } header: {
                Text("General AI service")
            } footer: {
                Text(AIBackend.isConfigured ? "AI 能力由开发者统一提供，无需填写 API Key。" : AIBackend.unavailableHint)
            }
            Section("Workout trainer") {
                Text("Tinker handles workout plans and remaining sets. Its service is configured separately from general AI.")
                    .font(.footnote)
                Button("Open trainer") { AppState.shared.perform(.openCoach) }
            }
            if !CoachHistory.messages(from: previousConversation).isEmpty {
                Section {
                    NavigationLink("Previous assistant conversations") {
                        List(CoachHistory.messages(from: previousConversation)) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.role == .user ? "You" : "Assistant").font(.caption).foregroundStyle(.secondary)
                                Text(message.text)
                            }
                        }.navigationTitle("Saved conversation")
                    }
                }
            }
            Section("用途") {
                Label("身体综合数据分析（饮食 → 身体）", systemImage: "waveform.path.ecg")
                Label("用自然语言修改今日训练（训练页 ✨）", systemImage: "sparkles")
                Label("Dictate trainer messages; review before sending", systemImage: "mic.fill")
                Label("周 / 月 / 季 / 年总结点评", systemImage: "chart.xyaxis.line")
                Label("用一句话改变助手的外观", systemImage: "person.crop.square")
            }
            .font(.subheadline)
        }
        .navigationTitle("AI 助手")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAvatar) { CoachAvatarView(profile: profile) }
    }

    private func testConnection() {
        guard let config = AIBackend.config else { status = AIError.notConfigured.localizedDescription; return }
        testing = true
        Task {
            do {
                let reply = try await AIService.test(config: config)
                testFailed = false; status = L("连接成功：%@", String(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)))
            } catch {
                testFailed = true; status = L("连接失败：%@", error.localizedDescription)
            }
            testing = false
        }
    }
}
