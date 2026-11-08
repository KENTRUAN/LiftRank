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
        _store = StateObject(wrappedValue: StoreLoader {
            let schema = Schema([UserProfile.self, Exercise.self, Workout.self, WorkoutExercise.self, WorkoutSet.self,
                                 BodyMeasurement.self, FoodEntry.self, CustomMeal.self, QuestClaim.self, RewardEvent.self, WorkoutTemplate.self,
                                 CardioSession.self, DailyPlan.self, Friend.self, TrainerMessage.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
            let context = container.mainContext
            ExerciseSeed.seed(into: context)
            if ((try? context.fetchCount(FetchDescriptor<UserProfile>())) ?? 0) == 0 {
                context.insert(UserProfile())
                try? context.save()
            }
            if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
                DemoData.seedIfNeeded(context: context, profile: profile)
            }
            TrainingHealthManager.shared.bind(context: context)
            CardioLiveActivityManager.shared.bind(context: context)
            return container
        })
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
