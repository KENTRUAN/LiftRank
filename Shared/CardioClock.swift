import Foundation

struct CardioPause: Codable, Hashable, Sendable {
    var startedAt: Date
    var endedAt: Date?
}

/// Elapsed time comes from persisted dates, not foreground timer ticks.
enum CardioClock {
    static func elapsed(start: Date, pauses: [CardioPause], at end: Date) -> TimeInterval {
        let paused = pauses.reduce(0.0) { total, pause in
            total + max(0, min(pause.endedAt ?? end, end).timeIntervalSince(max(pause.startedAt, start)))
        }
        return max(0, end.timeIntervalSince(start) - paused)
    }
    static func display(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
