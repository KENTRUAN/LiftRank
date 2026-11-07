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
    static let backGroups: [MuscleGroup] = [.traps, .shoulders, .back, .triceps, .forearms, .lowerBack, .glutes, .hamstrings, .calves]
    static let rankable: [MuscleGroup] = [.chest, .shoulders, .biceps, .triceps, .forearms, .abs, .quads, .calves, .back, .traps, .glutes, .hamstrings, .lowerBack]

    var regions: [MuscleRegion] {
        switch self {
        case .chest:
            [.init("上胸", ["incline_bench", "incline_db_bench"]),
             .init("中胸", ["bench_press", "db_bench", "pushup", "chest_fly_machine"]),
             .init("下胸", ["dips"]), .init("左胸"), .init("右胸")]
        case .shoulders:
            [.init("三角肌前束", ["ohp", "db_shoulder_press", "arnold_press"]),
             .init("三角肌中束", ["lateral_raise", "upright_row"]),
             .init("三角肌后束", ["rear_delt_fly", "face_pull"])]
        case .biceps:
            [.init("肱二头肌长头"), .init("肱二头肌短头"), .init("肱肌", ["hammer_curl"])]
        case .triceps:
            [.init("肱三头肌长头", ["overhead_tricep_ext", "skullcrusher"]),
             .init("肱三头肌外侧头", ["tricep_pushdown"]), .init("肱三头肌内侧头")]
        case .forearms:
            [.init("腕屈肌群", ["wrist_curl"]), .init("腕伸肌群"),
             .init("肱桡肌", ["reverse_curl", "hammer_curl"])]
        case .abs:
            [.init("腹直肌", ["cable_crunch", "hanging_leg_raise"]), .init("腹斜肌", ["russian_twist"])]
        case .quads:
            [.init("股直肌", ["leg_extension"]), .init("股内侧肌"), .init("股外侧肌"), .init("股中间肌")]
        case .calves:
            [.init("腓肠肌", ["standing_calf_raise"]), .init("比目鱼肌", ["seated_calf_raise"])]
        case .back:
            [.init("背阔肌", ["pullup", "chinup", "lat_pulldown"]),
             .init("上背中部", ["barbell_row", "db_row", "seated_row", "tbar_row"])]
        case .traps:
            [.init("斜方肌上束", ["barbell_shrug", "db_shrug", "upright_row"]),
             .init("斜方肌中束", ["seated_row", "tbar_row"]), .init("斜方肌下束")]
        case .glutes:
            [.init("臀大肌", ["hip_thrust", "sumo_deadlift", "kb_swing"]), .init("臀中肌"), .init("臀小肌")]
        case .hamstrings:
            [.init("屈膝动作", ["leg_curl", "nordic_curl"]), .init("伸髋动作", ["rdl", "good_morning"])]
        case .lowerBack:
            [.init("竖脊肌", ["hyperextension", "good_morning"]), .init("多裂肌")]
        case .cardio, .fullBody:
            []
        }
    }
}

struct MuscleRegion: Identifiable {
    let name: String
    let exerciseKeys: Set<String>
    var id: String { name }

    init(_ name: String, _ exerciseKeys: Set<String> = []) {
        self.name = name
        self.exerciseKeys = exerciseKeys
    }
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
