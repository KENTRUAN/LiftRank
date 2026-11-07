import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case anthropic, openai, deepseek, gemini
    var id: String { rawValue }
    var name: String {
        switch self {
        case .anthropic: "Claude（Anthropic）"
        case .openai: "GPT（OpenAI）"
        case .deepseek: "DeepSeek"
        case .gemini: "Gemini（Google）"
        }
    }
    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5-5"
        case .openai: "gpt-4o"
        case .deepseek: "deepseek-chat"
        case .gemini: "gemini-2.5-flash"
        }
    }
    var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com"
        case .openai: "https://api.openai.com/v1"
        case .deepseek: "https://api.deepseek.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com"
        }
    }
}

struct AIChatMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
}

struct AIConfig {
    let provider: AIProvider
    let model: String
    let baseURL: String
    let apiKey: String
}

enum AIError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case refusal
    case emptyResponse
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "AI 服务暂未开通：此构建没有配置开发者接口。"
        case .http(let code, let body): "请求失败（HTTP \(code)）：\(body.prefix(300))"
        case .refusal: "模型拒绝回答这个请求。"
        case .emptyResponse: "模型没有返回内容。"
        case .badResponse: "无法解析模型返回的数据。"
        }
    }
}

/// The AI backend is provided by the developer, not entered by users.
/// Values come from `Config/AI.xcconfig` (plus the git-ignored `Config/AI.local.xcconfig`) through Info.plist,
/// and can be overridden with `LIFTRANK_AI_*` environment variables when launching from Xcode or `simctl`.
/// Point `LIFTRANK_AI_BASE_URL` at your own relay server to keep the real provider key off the device.
enum AIBackend {
    static let displayName = "段位健身 AI"
    static let unavailableHint = "AI 能力由开发者统一提供，无需填写 Key。当前构建没有配置接口（Config/AI.local.xcconfig），所以暂时不可用。"

    static var config: AIConfig? {
        let env = ProcessInfo.processInfo.environment
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ plistKey: String, _ envKey: String) -> String {
            let raw = env[envKey] ?? (info[plistKey] as? String) ?? ""
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return v.hasPrefix("$(") ? "" : v
        }
        let key = value("LiftRankAIKey", "LIFTRANK_AI_KEY")
        guard !key.isEmpty else { return nil }
        let provider = AIProvider(rawValue: value("LiftRankAIProvider", "LIFTRANK_AI_PROVIDER")) ?? .anthropic
        let model = value("LiftRankAIModel", "LIFTRANK_AI_MODEL")
        let base = value("LiftRankAIBaseURL", "LIFTRANK_AI_BASE_URL")
        return AIConfig(provider: provider,
                        model: model.isEmpty ? provider.defaultModel : model,
                        baseURL: base.isEmpty ? provider.defaultBaseURL : base,
                        apiKey: key)
    }

    static var isConfigured: Bool { config != nil }
}

/// Raw HTTP clients for the supported providers (or a developer relay that speaks the same protocol).
enum AIService {
    static func complete(system: String, messages: [AIChatMessage], config: AIConfig, maxTokens: Int = 4096) async throws -> String {
        switch config.provider {
        case .anthropic: return try await anthropic(system: system, messages: messages, config: config, maxTokens: maxTokens)
        case .openai, .deepseek: return try await openAICompatible(system: system, messages: messages, config: config)
        case .gemini: return try await gemini(system: system, messages: messages, config: config)
        }
    }

    static func test(config: AIConfig) async throws -> String {
        try await complete(system: "你是一个健身助手。", messages: [AIChatMessage(role: .user, text: "请只回复两个字：连接成功")], config: config, maxTokens: 64)
    }

    // MARK: - Anthropic Messages API

    private static func anthropic(system: String, messages: [AIChatMessage], config: AIConfig, maxTokens: Int) async throws -> String {
        var req = URLRequest(url: URL(string: config.baseURL.trimmingSlash + "/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        // Server-side refusal fallbacks are available on the Claude 5 family.
        if ["claude-opus-5", "claude-fable-5", "claude-sonnet-5-5"].contains(where: { config.model.hasPrefix($0) }) {
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        let json = try await send(req, body: body)
        if let stop = json["stop_reason"] as? String, stop == "refusal" { throw AIError.refusal }
        guard let content = json["content"] as? [[String: Any]] else { throw AIError.badResponse }
        let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIError.emptyResponse }
        return text
    }

    // MARK: - OpenAI-compatible chat completions (OpenAI, DeepSeek)

    private static func openAICompatible(system: String, messages: [AIChatMessage], config: AIConfig) async throws -> String {
        var req = URLRequest(url: URL(string: config.baseURL.trimmingSlash + "/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "system", "content": system]] + messages.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        let json = try await send(req, body: body)
        guard let choices = json["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String, !text.isEmpty else { throw AIError.emptyResponse }
        return text
    }

    // MARK: - Gemini generateContent

    private static func gemini(system: String, messages: [AIChatMessage], config: AIConfig) async throws -> String {
        var req = URLRequest(url: URL(string: config.baseURL.trimmingSlash + "/v1beta/models/\(config.model):generateContent")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": messages.map { ["role": $0.role == .user ? "user" : "model", "parts": [["text": $0.text]]] },
        ]
        let json = try await send(req, body: body)
        guard let candidates = json["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { throw AIError.emptyResponse }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIError.emptyResponse }
        return text
    }

    private static func send(_ request: URLRequest, body: [String: Any]) async throws -> [String: Any] {
        var req = request
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AIError.http(status, String(data: data, encoding: .utf8) ?? "") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.badResponse }
        return json
    }
}

private extension String {
    var trimmingSlash: String { hasSuffix("/") ? String(dropLast()) : self }
}

/// Pulls the first JSON object out of a model reply that may be wrapped in prose or code fences.
enum AIJSON {
    static func extractObject(from text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        let slice = String(text[start...end])
        if let data = slice.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return obj }
        return nil
    }
}
