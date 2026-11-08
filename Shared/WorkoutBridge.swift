import Foundation
import HealthKit

enum TrainingActivity: String, Codable, CaseIterable, Identifiable {
    case strength, running, walking, cycling, rowing, elliptical, stairs, swimming, hiit
    var id: String { rawValue }
    /// These activities represent machines in LiftRank, not outdoor routes.
    var supportsOutdoor: Bool {
        switch self {
        case .running, .walking, .cycling, .swimming, .hiit: true
        case .strength, .rowing, .elliptical, .stairs: false
        }
    }
    static func cardioActivities(outdoor: Bool, requiresEquipment: Bool = false) -> [TrainingActivity] {
        allCases.filter { $0 != .strength && (!outdoor || $0.supportsOutdoor) && (!requiresEquipment || $0 != .swimming) }
    }
    var name: String {
        switch self {
        case .strength: "Traditional strength training"
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .stairs: "Stair climbing"
        case .swimming: "Swimming"
        case .hiit: "High intensity intervals"
        }
    }
    var healthType: HKWorkoutActivityType {
        switch self {
        case .strength: .traditionalStrengthTraining
        case .running: .running
        case .walking: .walking
        case .cycling: .cycling
        case .rowing: .rowing
        case .elliptical: .elliptical
        case .stairs: .stairClimbing
        case .swimming: .swimming
        case .hiit: .highIntensityIntervalTraining
        }
    }
    var configuration: HKWorkoutConfiguration { configuration(outdoor: false) }
    func configuration(outdoor: Bool) -> HKWorkoutConfiguration {
        let result = HKWorkoutConfiguration()
        result.activityType = healthType; result.locationType = outdoor ? .outdoor : .indoor
        return result
    }
}

/// Only session control/metrics cross devices. Social profiles and chats never do.
struct WorkoutBridgeMessage: Codable {
    var action: String
    var workoutID: String?
    var activity: String?
    var startedAt: Date?
    var endedAt: Date?
    var healthID: String?
    var error: String?
    var heartRate: Double?
    var metricsAt: Date?
    var calories: Double?
    var distanceMeters: Double?
    var outdoor: Bool?
    var cardioPauses: [CardioPause]?
    var controlVersion: Int?
    var requestID: String?
    var data: Data? { try? JSONEncoder().encode(self) }
}

enum WorkoutBridgeRules {
    static func pauses(_ pauses: [CardioPause], endingAt stop: Date) -> [CardioPause] {
        pauses.filter { $0.startedAt <= stop }.map { pause in
            var pause = pause
            if let resumed = pause.endedAt, resumed > stop { pause.endedAt = nil }
            return pause
        }
    }
    static func version(_ pauses: [CardioPause]) -> Int {
        pauses.count * 2 - (pauses.last?.endedAt == nil && !pauses.isEmpty ? 1 : 0)
    }
    static func acceptsPauseRequest(_ message: WorkoutBridgeMessage, workoutID: String, pauses: [CardioPause]) -> Bool {
        ["pauseRequest", "resumeRequest"].contains(message.action) && message.workoutID == workoutID
            && message.requestID != nil && message.controlVersion == version(pauses)
    }
    static func acceptsSnapshot(_ message: WorkoutBridgeMessage, current: WorkoutBridgeMessage) -> Bool {
        message.workoutID == current.workoutID && (message.controlVersion ?? 0) >= (current.controlVersion ?? 0)
    }
}


extension CardioClock {
    static func healthEvents(_ pauses: [CardioPause]) -> [HKWorkoutEvent] {
        pauses.flatMap { pause in
            var events = [HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pause.startedAt, duration: 0), metadata: nil)]
            if let resumed = pause.endedAt { events.append(HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: resumed, duration: 0), metadata: nil)) }
            return events
        }
    }
}
