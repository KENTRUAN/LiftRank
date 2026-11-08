import Foundation
import HealthKit

enum TrainingActivity: String, Codable, CaseIterable, Identifiable {
    case strength, running, walking, cycling, rowing, elliptical, stairs, swimming, hiit
    var id: String { rawValue }
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
    var calories: Double?
    var distanceMeters: Double?
    var outdoor: Bool?
    var cardioPauses: [CardioPause]?
    var controlVersion: Int?
    var data: Data? { try? JSONEncoder().encode(self) }
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
