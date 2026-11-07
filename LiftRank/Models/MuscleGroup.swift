import SwiftUI

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, shoulders, biceps, triceps, forearms, abs, quads, calves
    case back, traps, glutes, hamstrings, lowerBack
    case cardio, fullBody

    var id: String { rawValue }

    var name: String {
        switch self {
        case .chest: "胸"
        case .shoulders: "肩"
        case .biceps: "二头"
        case .triceps: "三头"
        case .forearms: "前臂"
        case .abs: "核心"
        case .quads: "股四头"
        case .calves: "小腿"
        case .back: "背"
        case .traps: "斜方肌"
        case .glutes: "臀"
        case .hamstrings: "腘绳肌"
        case .lowerBack: "下背"
        case .cardio: "有氧"
        case .fullBody: "全身"
        }
    }

    /// Groups shown on the front silhouette.
    static let frontGroups: [MuscleGroup] = [.shoulders, .chest, .biceps, .forearms, .abs, .quads, .calves]
    /// Groups shown on the back silhouette.
    static let backGroups: [MuscleGroup] = [.traps, .back, .triceps, .lowerBack, .glutes, .hamstrings, .calves]
    static let rankable: [MuscleGroup] = [.chest, .shoulders, .biceps, .triceps, .forearms, .abs, .quads, .calves, .back, .traps, .glutes, .hamstrings, .lowerBack]
}

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, cardio, other
    var id: String { rawValue }
    var name: String {
        switch self {
        case .barbell: "杠铃"
        case .dumbbell: "哑铃"
        case .machine: "器械"
        case .cable: "绳索"
        case .bodyweight: "自重"
        case .kettlebell: "壶铃"
        case .band: "弹力带"
        case .cardio: "有氧"
        case .other: "其他"
        }
    }
}

enum SetType: String, Codable, CaseIterable, Identifiable {
    case normal, warmup, drop
    var id: String { rawValue }
    var tag: String {
        switch self {
        case .normal: ""
        case .warmup: "W"
        case .drop: "D"
        }
    }
    var name: String {
        switch self {
        case .normal: "正式组"
        case .warmup: "热身组"
        case .drop: "递减组"
        }
    }
}
