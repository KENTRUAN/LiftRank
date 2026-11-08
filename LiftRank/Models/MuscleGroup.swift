import SwiftUI

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, shoulders, biceps, triceps, forearms, abs, quads, calves
    case back, traps, glutes, hamstrings, lowerBack
    case cardio, fullBody

    var id: String { rawValue }

    var name: String {
        switch self {
        case .chest: L("胸")
        case .shoulders: L("肩")
        case .biceps: L("二头")
        case .triceps: L("三头")
        case .forearms: L("前臂")
        case .abs: L("核心")
        case .quads: L("股四头")
        case .calves: L("小腿")
        case .back: L("背")
        case .traps: L("斜方肌")
        case .glutes: L("臀")
        case .hamstrings: L("腘绳肌")
        case .lowerBack: L("下背")
        case .cardio: L("有氧")
        case .fullBody: L("全身")
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
            [.init(L("上胸"), ["incline_bench", "incline_db_bench"]),
             .init(L("中胸"), ["bench_press", "db_bench", "pushup", "chest_fly_machine"]),
             .init(L("下胸"), ["dips"]), .init(L("左胸")), .init(L("右胸"))]
        case .shoulders:
            [.init(L("三角肌前束"), ["ohp", "db_shoulder_press", "arnold_press"]),
             .init(L("三角肌中束"), ["lateral_raise", "upright_row"]),
             .init(L("三角肌后束"), ["rear_delt_fly", "face_pull"])]
        case .biceps:
            [.init(L("肱二头肌长头")), .init(L("肱二头肌短头")), .init(L("肱肌"), ["hammer_curl"])]
        case .triceps:
            [.init(L("肱三头肌长头"), ["overhead_tricep_ext", "skullcrusher"]),
             .init(L("肱三头肌外侧头"), ["tricep_pushdown"]), .init(L("肱三头肌内侧头"))]
        case .forearms:
            [.init(L("腕屈肌群"), ["wrist_curl"]), .init(L("腕伸肌群")),
             .init(L("肱桡肌"), ["reverse_curl", "hammer_curl"])]
        case .abs:
            [.init(L("腹直肌"), ["cable_crunch", "hanging_leg_raise"]), .init(L("腹斜肌"), ["russian_twist"])]
        case .quads:
            [.init(L("股直肌"), ["leg_extension"]), .init(L("股内侧肌")), .init(L("股外侧肌")), .init(L("股中间肌"))]
        case .calves:
            [.init(L("腓肠肌"), ["standing_calf_raise"]), .init(L("比目鱼肌"), ["seated_calf_raise"])]
        case .back:
            [.init(L("背阔肌"), ["pullup", "chinup", "lat_pulldown"]),
             .init(L("上背中部"), ["barbell_row", "db_row", "seated_row", "tbar_row"])]
        case .traps:
            [.init(L("斜方肌上束"), ["barbell_shrug", "db_shrug", "upright_row"]),
             .init(L("斜方肌中束"), ["seated_row", "tbar_row"]), .init(L("斜方肌下束"))]
        case .glutes:
            [.init(L("臀大肌"), ["hip_thrust", "sumo_deadlift", "kb_swing"]), .init(L("臀中肌")), .init(L("臀小肌"))]
        case .hamstrings:
            [.init(L("屈膝动作"), ["leg_curl", "nordic_curl"]), .init(L("伸髋动作"), ["rdl", "good_morning"])]
        case .lowerBack:
            [.init(L("竖脊肌"), ["hyperextension", "good_morning"]), .init(L("多裂肌"))]
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
        case .barbell: L("杠铃")
        case .dumbbell: L("哑铃")
        case .machine: L("器械")
        case .cable: L("绳索")
        case .bodyweight: L("自重")
        case .kettlebell: L("壶铃")
        case .band: L("弹力带")
        case .cardio: L("有氧")
        case .other: L("其他")
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
        case .normal: L("正式组")
        case .warmup: L("热身组")
        case .drop: L("递减组")
        }
    }
}
