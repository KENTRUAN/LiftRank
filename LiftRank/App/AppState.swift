import SwiftUI
import Observation

/// Actions handed to the UI from Siri shortcuts or the AI assistant.
enum PendingAction: Equatable {
    case startTodayWorkout
    case logBodyweight(kg: Double)
    case openCoach
    case openCardio
    case openTab(Int)
}

/// Cross-tab navigation state shared by the tab bar, intents and the AI coach.
@Observable
final class AppState {
    static let shared = AppState()

    var tab: Int = DemoData.initialTab
    var pending: PendingAction?
    /// Incremented when something outside the workout tab asks it to start today's plan.
    var startTodayRequest = 0
    var showCoach = false
    var toast: String?

    func perform(_ action: PendingAction) {
        switch action {
        case .startTodayWorkout:
            tab = 0
            startTodayRequest += 1
        case .openCoach:
            tab = 0
            showCoach = true
        case .openCardio:
            tab = 0
            pending = action
        case .openTab(let t):
            tab = t
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
