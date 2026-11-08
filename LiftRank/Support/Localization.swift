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
    private static let english: [String: String] = Dictionary(ExerciseSeed.all.map { ($0.name, $0.nameEn) }, uniquingKeysWith: { first, _ in first })
    static func display(_ name: String) -> String {
        guard AppLanguage.current.isEnglish, let en = english[name], !en.isEmpty else { return name }
        return en
    }
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
