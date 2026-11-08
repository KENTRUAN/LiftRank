import SwiftUI
import Observation

/// Actions handed to the UI from Siri shortcuts or the AI assistant.
enum PendingAction: Equatable {
    case startTodayWorkout
    case logBodyweight(kg: Double)
    case openCoach
    case openCardio
    case openWorkout(UUID)
    case openTab(Int)
}

/// Cross-tab navigation state shared by the tab bar, intents and the AI coach.
@Observable
final class AppState {
    static let shared = AppState()
    static let communityTab = 5

    var tab: Int = DemoData.initialTab
    var pending: PendingAction?
    /// Incremented when something outside the workout tab asks it to start today's plan.
    var startTodayRequest = 0
    var showCoach = false
    var showRewards = false
    var communitySection = 0
    var prefersCardioStart = false
    var toast: String?

    func perform(_ action: PendingAction) {
        switch action {
        case .startTodayWorkout:
            communitySection = 0
            tab = Self.communityTab
            startTodayRequest += 1
        case .openCoach:
            tab = 0
            showCoach = true
        case .openCardio, .openWorkout:
            tab = 0
            pending = action
        case .openTab(let t):
            // Keep legacy Rewards links (tab 2) working after its move to Profile.
            tab = t == 2 ? 4 : t
            if t == 2 { showRewards = true }
        case .logBodyweight:
            pending = action
        }
    }

    func flash(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }
}
