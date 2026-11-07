import Foundation
import SwiftUI

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }
    var label: String { rawValue }
    func fromKg(_ kg: Double) -> Double { self == .kg ? kg : kg * 2.20462 }
    func toKg(_ value: Double) -> Double { self == .kg ? value : value / 2.20462 }
}

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "男" : "女" }
}

extension Double {
    func fmt(_ digits: Int = 1) -> String {
        if self == self.rounded() && digits <= 1 { return String(Int(self.rounded())) }
        return String(format: "%.\(digits)f", self)
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func daysSince(_ other: Date) -> Int {
        Calendar.current.dateComponents([.day], from: other.startOfDay, to: self.startOfDay).day ?? 0
    }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self) ?? self }
    var shortString: String {
        let f = DateFormatter(); f.dateFormat = "M月d日"; return f.string(from: self)
    }
    var mediumString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy年M月d日 HH:mm"; return f.string(from: self)
    }
    var weekKey: String {
        let c = Calendar(identifier: .iso8601)
        let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return "W\(comps.yearForWeekOfYear ?? 0)-\(comps.weekOfYear ?? 0)"
    }
    var dayKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: self)
    }
}

extension TimeInterval {
    var clockString: String {
        let s = Int(self)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
