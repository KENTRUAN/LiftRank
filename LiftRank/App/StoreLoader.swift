import Combine
import SwiftData

@MainActor
final class StoreLoader: ObservableObject {
    /// UI, Live Activity intents and background Watch delivery open the same store.
    static let shared = StoreLoader {
        let schema = Schema([UserProfile.self, Exercise.self, Workout.self, WorkoutExercise.self, WorkoutSet.self,
                             BodyMeasurement.self, FoodEntry.self, CustomMeal.self, QuestClaim.self, RewardEvent.self, WorkoutTemplate.self,
                             CardioSession.self, DailyPlan.self, Friend.self, TrainerMessage.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        let context = container.mainContext
        ExerciseSeed.seed(into: context)
        if try context.fetchCount(FetchDescriptor<UserProfile>()) == 0 {
            context.insert(UserProfile()); try context.save()
        }
        if let profile = try context.fetch(FetchDescriptor<UserProfile>()).first {
            DemoData.seedIfNeeded(context: context, profile: profile)
        }
        TrainingHealthManager.shared.bind(context: context)
        CardioLiveActivityManager.shared.bind(context: context)
        return container
    }

    func requireContext() throws -> ModelContext {
        retry()
        guard let container else { throw GymFailure.message(L("Open LiftRank to restore your workout data, then retry.")) }
        return container.mainContext
    }
    @Published private(set) var container: ModelContainer?
    private let makeContainer: () throws -> ModelContainer

    init(makeContainer: @escaping () throws -> ModelContainer) {
        self.makeContainer = makeContainer
        retry()
    }

    func retry() {
        guard container == nil else { return }
        do {
            container = try makeContainer()
        } catch {
            // Leave the existing store untouched so a later attempt can recover it.
            container = nil
        }
    }
}
