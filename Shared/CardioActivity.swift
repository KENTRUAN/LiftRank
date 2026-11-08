#if os(iOS)
import ActivityKit
import AppIntents
import SwiftUI

struct CardioActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsed: Double
        var updatedAt: Date
        var isPaused: Bool
        var isFinished: Bool = false
        var timerStart: Date { updatedAt.addingTimeInterval(-elapsed) }
    }
    var workoutID: String
    var activityName: String
    var outdoor: Bool
}

struct CardioActivityClock: View {
    let state: CardioActivityAttributes.ContentState
    var body: some View {
        Group {
            if state.isPaused || state.isFinished { Text(CardioClock.display(state.elapsed)) }
            else { Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false) }
        }.monospacedDigit()
    }
}

/// ActivityKit executes LiveActivityIntent in the containing app, which owns SwiftData.
struct CardioPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume cardio"
    static var isDiscoverable = false
    @Parameter(title: "Workout") var workoutID: String
    @Parameter(title: "Pause") var paused: Bool
    init() {}
    init(workoutID: String, paused: Bool) { self.workoutID = workoutID; self.paused = paused }
    @MainActor func perform() async throws -> some IntentResult {
        #if LIFTRANK_WIDGET
        throw NSError(domain: "LiftRank", code: 1, userInfo: [NSLocalizedDescriptionKey: "Open LiftRank to control your workout."])
        #else
        try await CardioLiveActivityManager.shared.setPaused(paused, workoutID: workoutID)
        #endif
        return .result()
    }
}
#endif
