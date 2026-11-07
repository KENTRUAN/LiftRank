import AppIntents

/// Siri / Shortcuts entry points. They open the app and hand the action to AppState.
struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "开始今日训练"
    static var description = IntentDescription("打开段位健身并开始今天自动发布的训练。")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.perform(.startTodayWorkout)
        return .result()
    }
}

struct LogBodyweightIntent: AppIntent {
    static var title: LocalizedStringResource = "记录体重"
    static var description = IntentDescription("记录一条体重数据（公斤）。")
    static var openAppWhenRun = true

    @Parameter(title: "体重（公斤）")
    var weightKg: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppState.shared.perform(.logBodyweight(kg: weightKg))
        return .result(dialog: "已记录体重 \(weightKg.fmt(1)) 公斤")
    }
}

struct OpenCoachIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 AI 训练助手"
    static var description = IntentDescription("用语音或文字修改今日训练。")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.perform(.openCoach)
        return .result()
    }
}

struct LogCardioIntent: AppIntent {
    static var title: LocalizedStringResource = "记录有氧"
    static var description = IntentDescription("打开有氧记录页面。")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.perform(.openCardio)
        return .result()
    }
}

struct LiftRankShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartWorkoutIntent(), phrases: ["在\(.applicationName)开始训练", "用\(.applicationName)开始今日训练"],
                    shortTitle: "开始训练", systemImageName: "play.fill")
        AppShortcut(intent: LogBodyweightIntent(), phrases: ["用\(.applicationName)记录体重"],
                    shortTitle: "记录体重", systemImageName: "scalemass")
        AppShortcut(intent: OpenCoachIntent(), phrases: ["打开\(.applicationName)训练助手", "让\(.applicationName)修改训练"],
                    shortTitle: "AI 助手", systemImageName: "sparkles")
        AppShortcut(intent: LogCardioIntent(), phrases: ["用\(.applicationName)记录有氧"],
                    shortTitle: "记录有氧", systemImageName: "figure.run")
    }
}
