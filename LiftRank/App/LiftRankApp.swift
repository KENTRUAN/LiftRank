import SwiftUI
import SwiftData

@main
@MainActor
struct LiftRankApp: App {
    @StateObject private var store: StoreLoader
    @StateObject private var gym = GymStore()
    @State private var languageSettings = LanguageSettings.shared

    init() {
        LanguageBundle.install()
        // Register workout mirroring immediately, including a background launch.
        _ = TrainingHealthManager.shared
        _store = StateObject(wrappedValue: StoreLoader.shared)
    }

    var body: some Scene {
        WindowGroup {
            if let container = store.container {
                RootView()
                    .background(KeyboardDismissal())
                    .modelContainer(container)
                    // Rebuild the whole interface in the selected language.
                    .id(languageSettings.language)
                    .environment(\.locale, languageSettings.language.locale)
                    .environmentObject(gym)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("暂时无法读取训练数据").font(.headline)
                    Text("现有记录会保留。请重试，或稍后重新打开应用。")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") { store.retry() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
    }
}
