import SwiftUI
import Observation
import ObjectiveC

/// The interface language. The app ships a complete Chinese and a complete English interface;
/// the choice lives in UserDefaults and applies immediately without relaunching.
enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    static let defaultsKey = "appLanguage"
    var id: String { rawValue }
    /// Shown in its own language so either reader can find it.
    var nativeName: String { self == .chinese ? "中文" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }
    var isEnglish: Bool { self == .english }
    /// Appended to AI prompts so replies match the interface.
    var aiReplyInstruction: String { isEnglish ? "Reply in English." : "请用简体中文回复。" }

    static var current: AppLanguage {
        get { stored ?? systemDefault }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            // System-provided UI (alerts, pickers, Back) follows on the next launch.
            UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
            LanguageBundle.reload()
            LanguageSettings.shared.language = newValue
        }
    }
    static var stored: AppLanguage? { UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) }
    static var systemDefault: AppLanguage {
        (Locale.preferredLanguages.first ?? "").lowercased().hasPrefix("zh") ? .chinese : .english
    }
}

/// Observed by the root so every screen re-renders when the language changes.
@Observable
final class LanguageSettings {
    static let shared = LanguageSettings()
    var language: AppLanguage = AppLanguage.current
}

/// Routes `Bundle.main` lookups (SwiftUI `Text`, `String(localized:)`, `L()`) to the selected language.
enum LanguageBundle {
    fileprivate static var active: Bundle?
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        object_setClass(Bundle.main, LocalizedBundle.self)
        reload()
    }

    static func reload() {
        active = Bundle.main.path(forResource: AppLanguage.current.rawValue, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let bundle = LanguageBundle.active else { return super.localizedString(forKey: key, value: value, table: tableName) }
        return bundle.localizedString(forKey: key, value: value, table: tableName)
    }
}

/// Localized copy for `String` contexts (toasts, model names, alerts). Keys are the Chinese source text.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

/// Format-string variant: `L("已记录体重 %@ %@", weight, unit)`. Use `%lld` for `Int`, `%@` for `String`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: AppLanguage.current.locale, arguments: arguments)
}

extension Exercise {
    /// Catalogue name in the interface language; custom exercises keep whatever the user typed.
    var displayName: String {
        AppLanguage.current.isEnglish && !nameEn.isEmpty ? nameEn : name
    }
}

/// Resolves stored exercise names (set logs, templates, plans) to the interface language.
enum ExerciseNames {
    private static let pairs = ExerciseSeed.all.filter { !$0.nameEn.isEmpty }.map { ($0.name, $0.nameEn) }
    private static let english = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    private static let chinese = Dictionary(pairs.map { ($0.1, $0.0) }, uniquingKeysWith: { first, _ in first })

    static func display(_ name: String) -> String {
        (AppLanguage.current.isEnglish ? english[name] : chinese[name]) ?? name
    }
}

/// Recognizes the app's stock names and rule-based templates without rewriting saved text.
enum WorkoutLabels {
    private static let splits = ["全身 A", "全身 B", "全身 C", "上肢 A", "上肢 B", "下肢 A", "下肢 B",
                                 "推", "拉", "腿", "上肢", "下肢核心", "弱项补强"]
    private static let goals = ["力量", "增肌", "综合体能", "减脂"]
    private static let stock = ["训练", "今日训练", "晨间训练", "午后训练", "夜间训练", "推力日", "拉力日", "腿部日", "推拉日（进行中）"]

    private static let keys: [String: String] = {
        let bundles = AppLanguage.allCases.compactMap {
            Bundle.main.path(forResource: $0.rawValue, ofType: "lproj").flatMap(Bundle.init(path:))
        }
        let aliases = (stock + splits + goals).flatMap { key in
            [(key, key)] + bundles.map { ($0.localizedString(forKey: key, value: nil, table: nil), key) }
        }
        return Dictionary(aliases, uniquingKeysWith: { first, _ in first })
    }()

    static func title(_ saved: String) -> String {
        if let key = keys[saved], stock.contains(key) { return L(key) }
        let match = saved.wholeMatch(of: #/(?:Day ([1-6])|第 ([1-6]) 天) · (.+)/#)
        guard let (_, englishDay, chineseDay, split) = match?.output,
              let dayText = englishDay ?? chineseDay, let day = Int(dayText),
              let key = keys[String(split)], splits.contains(key) else { return saved }
        return L("第 %lld 天 · %@", day, L(key))
    }

    static func planSummary(_ saved: String) -> String {
        let match = saved.wholeMatch(of: #/(.+) · (?:([1-6]) days/week · ([0-9]{1,2}) weeks|每周 ([1-6]) 天 · ([0-9]{1,2}) 周)/#)
        guard let (_, goal, enDays, enWeeks, zhDays, zhWeeks) = match?.output,
              let dayText = enDays ?? zhDays, let days = Int(dayText),
              let weekText = enWeeks ?? zhWeeks, let weeks = Int(weekText), (1...12).contains(weeks),
              let key = keys[String(goal)], goals.contains(key) else { return saved }
        return L("%@ · 每周 %lld 天 · %lld 周", L(key), days, weeks)
    }
}

extension WorkoutTemplate {
    var displayName: String { planName.isEmpty ? name : WorkoutLabels.title(name) }
    var displayPlanName: String { WorkoutLabels.planSummary(planName) }
}

/// A picker for the interface language; the two options stay in their own scripts.
struct LanguagePicker: View {
    @State private var selection = AppLanguage.current
    var body: some View {
        Picker(selection: $selection) {
            ForEach(AppLanguage.allCases) { language in Text(verbatim: language.nativeName).tag(language) }
        } label: {
            Label("语言 / Language", systemImage: "globe")
        }
        .onChange(of: selection) { _, language in
            guard language != AppLanguage.current else { return }
            withAnimation { AppLanguage.current = language }
        }
    }
}
