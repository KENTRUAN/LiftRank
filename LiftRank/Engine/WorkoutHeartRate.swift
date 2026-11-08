import Foundation

struct WorkoutHeartRate {
    let workoutID: UUID
    let beatsPerMinute: Double
    let measuredAt: Date

    func value(for id: UUID, now: Date = Date()) -> Double? {
        guard id == workoutID, beatsPerMinute.isFinite, beatsPerMinute > 0, beatsPerMinute < 350,
              now.timeIntervalSince(measuredAt) >= -5, now.timeIntervalSince(measuredAt) <= 30 else { return nil }
        return beatsPerMinute
    }
}
