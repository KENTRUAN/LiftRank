import ActivityKit
import SwiftUI
import SwiftData

@MainActor
final class CardioLiveActivityManager: ObservableObject {
    static let shared = CardioLiveActivityManager()
    @Published private(set) var error: String?
    private var context: ModelContext?
    private var pending: Task<Void, Never>?
    private var lastMetricsRefresh = Date.distantPast
    private let requestedKey = "cardio.liveActivity.requestedWorkoutID"

    func bind(context: ModelContext) { self.context = context }
    func refresh() {
        let previous = pending
        pending = Task { await previous?.value; await reconcile() }
    }
    func refreshMetrics() {
        guard Date().timeIntervalSince(lastMetricsRefresh) >= 5 else { return }
        lastMetricsRefresh = Date()
        refresh()
    }
    func retry() {
        UserDefaults.standard.removeObject(forKey: requestedKey)
        refresh()
    }
    func setPaused(_ paused: Bool, workoutID: String) async throws {
        let context = try context ?? StoreLoader.shared.requireContext()
        guard let workout = try context.fetch(FetchDescriptor<Workout>()).first(where: { $0.id.uuidString == workoutID }) else {
            throw GymFailure.message(L("Open LiftRank to restore this workout."))
        }
        let changed = try CardioWorkoutSession.setPaused(paused, workout: workout, context: context)
        // Update the system timer immediately; Health tracking follows the same desired state.
        refresh()
        await pending?.value
        if changed { await TrainingHealthManager.shared.updateCardioPause(workout) }
    }
    private func reconcile() async {
        guard let context else { return }
        let records: [Workout]
        do { records = try context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\Workout.startedAt, order: .reverse)])) }
        catch { self.error = L("Could not refresh your Live Activity. Open LiftRank to retry."); return }
        let workout = records.first { !$0.isPublished && $0.endedAt == nil && ($0.cardioTimerStartedAt != nil || ($0.activity == .strength && $0.startOptionsChosen)) }
        for activity in Activity<CardioActivityAttributes>.activities where activity.attributes.workoutID != workout?.id.uuidString {
            let ended = records.first { $0.id.uuidString == activity.attributes.workoutID }
            let final = ended.map { ActivityContent(state: WorkoutActivitySnapshot(workout: $0).state, staleDate: nil) }
            await activity.end(final, dismissalPolicy: .immediate)
        }
        guard let workout else { error = nil; return }
        let snapshot = WorkoutActivitySnapshot(workout: workout, reading: TrainingHealthManager.shared.heartRateReading)
        let content = ActivityContent(state: snapshot.state, staleDate: snapshot.state.heartRate == nil ? nil : snapshot.state.heartRateAt?.addingTimeInterval(30))
        let existing = Activity<CardioActivityAttributes>.activities.filter { $0.attributes.workoutID == workout.id.uuidString && $0.activityState != .dismissed && $0.activityState != .ended }
        if let activity = existing.first {
            await activity.update(content)
            for duplicate in existing.dropFirst() { await duplicate.end(nil, dismissalPolicy: .immediate) }
            error = nil; return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { error = L("Live Activities are off. Enable them in iPhone Settings → LiftRank. Your timer still runs."); return }
        guard UIApplication.shared.applicationState == .active else { return }
        // Respect a Live Activity dismissed by the user or ended by iOS; Retry is explicit.
        guard UserDefaults.standard.string(forKey: requestedKey) != workout.id.uuidString else { return }
        do {
            _ = try Activity.request(attributes: snapshot.attributes, content: content, pushType: nil)
            UserDefaults.standard.set(workout.id.uuidString, forKey: requestedKey)
            error = nil
        } catch { self.error = L("Live Activity unavailable: %@. Your workout timer continues.", error.localizedDescription) }
    }
}

struct WorkoutLiveActivityStatusView: View {
    @ObservedObject private var manager = CardioLiveActivityManager.shared
    var body: some View {
        if let error = manager.error {
            Text(error).font(.caption).foregroundStyle(.secondary)
            Button("Retry Live Activity") { manager.retry() }
        }
    }
}
