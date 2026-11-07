import SwiftUI
import SwiftData

@main
struct LiftRankApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([UserProfile.self, Exercise.self, Workout.self, WorkoutExercise.self, WorkoutSet.self,
                             BodyMeasurement.self, FoodEntry.self, CustomMeal.self, QuestClaim.self, RewardEvent.self, WorkoutTemplate.self])
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            // Schema changed during development: start over with a fresh store.
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: url)
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        }
        let context = container.mainContext
        ExerciseSeed.seed(into: context)
        if ((try? context.fetchCount(FetchDescriptor<UserProfile>())) ?? 0) == 0 {
            context.insert(UserProfile())
            try? context.save()
        }
        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            DemoData.seedIfNeeded(context: context, profile: profile)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .background(KeyboardDismissal())
        }
        .modelContainer(container)
    }
}
