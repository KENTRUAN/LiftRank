import SwiftUI
import SwiftData

struct AISettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @State private var apiKey = ""
    @State private var status: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section("服务商") {
                Picker("模型服务", selection: $profile.aiProvider) { ForEach(AIProvider.allCases) { Text($0.name).tag($0) } }
                    .onChange(of: profile.aiProvider) { _, p in apiKey = Keychain.get(account: p.rawValue) ?? ""; status = nil }
                LabeledContent("模型") {
                    TextField(profile.aiProvider.defaultModel, text: $profile.aiModel).formInputStyle().autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                LabeledContent("接口地址") {
                    TextField(profile.aiProvider.defaultBaseURL, text: $profile.aiBaseURL).formInputStyle().autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                }
            }
            Section {
                SecureField(profile.aiProvider.keyPlaceholder, text: $apiKey).autocorrectionDisabled().textInputAutocapitalization(.never)
                HStack {
                    Button("保存 Key") { Keychain.set(apiKey, account: profile.aiProvider.rawValue); try? context.save(); status = apiKey.isEmpty ? "已清除 Key" : "已保存到本机钥匙串" }
                    Spacer()
                    Button(testing ? "测试中…" : "测试连接") { testConnection() }.disabled(testing || apiKey.isEmpty)
                }
                if let status { Text(status).font(.footnote).foregroundStyle(status.contains("失败") || status.contains("错误") ? .red : .secondary) }
            } header: {
                Text("API Key")
            } footer: {
                Text("Key 只保存在本机钥匙串，请求直接从手机发送到对应服务商，不经过第三方服务器。留空模型与地址将使用默认值；兼容 OpenAI 接口的服务（如 DeepSeek、代理）可修改接口地址。")
            }
            Section("用途") {
                Label("身体综合数据分析（饮食 → 身体）", systemImage: "waveform.path.ecg")
                Label("用自然语言修改今日训练（训练页 ✨）", systemImage: "sparkles")
                Label("语音助手：说出指令即可开始训练、记录体重", systemImage: "mic.fill")
                Label("周 / 月 / 季 / 年总结点评", systemImage: "chart.xyaxis.line")
            }
            .font(.subheadline)
        }
        .navigationTitle("AI 助手")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { apiKey = Keychain.get(account: profile.aiProvider.rawValue) ?? "" }
    }

    private func testConnection() {
        Keychain.set(apiKey, account: profile.aiProvider.rawValue)
        try? context.save()
        guard let config = profile.aiConfig else { status = "请先填写 Key"; return }
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
