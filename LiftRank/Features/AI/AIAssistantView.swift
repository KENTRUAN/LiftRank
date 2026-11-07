import SwiftUI
import SwiftData

/// "AI 助手" settings: the assistant's character plus the status of the developer-provided backend.
struct AIAssistantView: View {
    @Bindable var profile: UserProfile
    @State private var status: String?
    @State private var testing = false
    @State private var showAvatar = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AvatarFigureView(spec: profile.coachAvatar, bust: true).frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.coachName).font(.headline)
                        Text(profile.coachIntro.isEmpty ? "用一句话描述，就能定义助手的样子。" : profile.coachIntro)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer()
                }
                Button { showAvatar = true } label: { Label("定义助手形象", systemImage: "wand.and.stars") }
                Button { AppState.shared.perform(.openCoach) } label: { Label("和 \(profile.coachName) 聊天 / 语音指令", systemImage: "bubble.left.and.bubble.right.fill") }
            } header: {
                Text("助手形象")
            }
            Section {
                LabeledContent("服务", value: AIBackend.displayName)
                LabeledContent("状态", value: AIBackend.isConfigured ? "已开通" : "未开通")
                Button(testing ? "测试中…" : "测试连接") { testConnection() }.disabled(testing || !AIBackend.isConfigured)
                if let status { Text(status).font(.footnote).foregroundStyle(status.contains("失败") ? .red : .secondary) }
            } header: {
                Text("服务状态")
            } footer: {
                Text(AIBackend.isConfigured ? "AI 能力由开发者统一提供，无需填写 API Key。" : AIBackend.unavailableHint)
            }
            Section("用途") {
                Label("身体综合数据分析（饮食 → 身体）", systemImage: "waveform.path.ecg")
                Label("用自然语言修改今日训练（训练页 ✨）", systemImage: "sparkles")
                Label("语音助手：说出指令即可开始训练、记录体重", systemImage: "mic.fill")
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
                status = "连接成功：\(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))"
            } catch {
                status = "连接失败：\(error.localizedDescription)"
            }
            testing = false
        }
    }
}
