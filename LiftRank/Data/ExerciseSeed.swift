import Foundation
import SwiftData

/// Built-in exercise catalogue. Standards are e1RM / bodyweight ratios reaching scores 200/400/600/800/1000 (male);
/// female standards default to 72% of male unless given.
enum ExerciseSeed {
    static func seed(into context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }
        for e in all { context.insert(e) }
        try? context.save()
    }

    static var all: [Exercise] {
        var list: [Exercise] = []
        func add(_ key: String, _ name: String, _ en: String, _ m: MuscleGroup, _ sec: [MuscleGroup] = [], _ eq: Equipment,
                 bw: Double = 0, std: [Double] = [], stdF: [Double] = [], cardio: Bool = false, tip: String = "") {
            list.append(Exercise(key: key, name: name, nameEn: en, muscle: m, secondary: sec, equipment: eq, isCardio: cardio,
                                 isRanked: !std.isEmpty, bodyweightFactor: bw, standardsMale: std, standardsFemale: stdF, instructions: tip))
        }
        // Chest
        add("bench_press", "杠铃卧推", "Barbell Bench Press", .chest, [.triceps, .shoulders], .barbell, std: [0.5, 0.85, 1.2, 1.6, 2.0], stdF: [0.3, 0.5, 0.75, 1.0, 1.3], tip: "肩胛收紧下沉，杠铃触碰胸部下缘，脚踩实地面。")
        add("incline_bench", "上斜杠铃卧推", "Incline Bench Press", .chest, [.shoulders, .triceps], .barbell, std: [0.4, 0.7, 1.0, 1.35, 1.7])
        add("db_bench", "哑铃卧推", "Dumbbell Bench Press", .chest, [.triceps], .dumbbell, std: [0.2, 0.35, 0.5, 0.65, 0.8], tip: "单只哑铃重量；下放时肘部约 45°。")
        add("incline_db_bench", "上斜哑铃卧推", "Incline Dumbbell Press", .chest, [.shoulders], .dumbbell, std: [0.18, 0.3, 0.45, 0.6, 0.75])
        add("dips", "双杠臂屈伸", "Dips", .chest, [.triceps], .bodyweight, bw: 1.0, std: [0.9, 1.15, 1.4, 1.7, 2.0], tip: "重量栏填写额外负重。")
        add("pushup", "俯卧撑", "Push-Up", .chest, [.triceps, .abs], .bodyweight, bw: 0.64, std: [0.5, 0.75, 0.95, 1.2, 1.45])
        add("chest_fly_machine", "器械夹胸", "Machine Chest Fly", .chest, [], .machine, std: [0.4, 0.7, 1.0, 1.3, 1.6])
        add("cable_fly", "绳索夹胸", "Cable Fly", .chest, [], .cable)
        // Back
        add("deadlift", "杠铃硬拉", "Deadlift", .back, [.hamstrings, .glutes, .lowerBack], .barbell, std: [0.8, 1.3, 1.8, 2.3, 2.8], stdF: [0.5, 0.9, 1.3, 1.7, 2.1], tip: "杠铃贴近小腿，背部中立，髋膝同步伸展。")
        add("pullup", "引体向上", "Pull-Up", .back, [.biceps], .bodyweight, bw: 1.0, std: [0.9, 1.1, 1.3, 1.55, 1.8], tip: "重量栏填写额外负重；完成一次计 1 次。")
        add("chinup", "反手引体", "Chin-Up", .back, [.biceps], .bodyweight, bw: 1.0, std: [0.9, 1.12, 1.35, 1.6, 1.85])
        add("barbell_row", "杠铃划船", "Barbell Row", .back, [.biceps, .lowerBack], .barbell, std: [0.45, 0.75, 1.05, 1.4, 1.75])
        add("db_row", "单臂哑铃划船", "Dumbbell Row", .back, [.biceps], .dumbbell, std: [0.2, 0.35, 0.5, 0.7, 0.9])
        add("lat_pulldown", "高位下拉", "Lat Pulldown", .back, [.biceps], .cable, std: [0.5, 0.8, 1.1, 1.4, 1.7])
        add("seated_row", "坐姿划船", "Seated Cable Row", .back, [.biceps], .cable, std: [0.5, 0.8, 1.1, 1.4, 1.7])
        add("tbar_row", "T 杠划船", "T-Bar Row", .back, [.biceps], .barbell, std: [0.4, 0.7, 1.0, 1.3, 1.6])
        add("rack_pull", "架上硬拉", "Rack Pull", .back, [.traps, .glutes], .barbell, std: [0.9, 1.4, 1.9, 2.4, 3.0])
        // Shoulders
        add("ohp", "站姿杠铃推举", "Overhead Press", .shoulders, [.triceps], .barbell, std: [0.35, 0.55, 0.8, 1.05, 1.3], stdF: [0.2, 0.35, 0.5, 0.7, 0.9])
        add("db_shoulder_press", "哑铃推举", "Dumbbell Shoulder Press", .shoulders, [.triceps], .dumbbell, std: [0.15, 0.25, 0.38, 0.5, 0.62])
        add("lateral_raise", "哑铃侧平举", "Lateral Raise", .shoulders, [], .dumbbell, std: [0.06, 0.11, 0.17, 0.24, 0.3])
        add("face_pull", "面拉", "Face Pull", .shoulders, [.back], .cable)
        add("rear_delt_fly", "俯身飞鸟", "Rear Delt Fly", .shoulders, [], .dumbbell)
        add("arnold_press", "阿诺德推举", "Arnold Press", .shoulders, [.triceps], .dumbbell, std: [0.14, 0.24, 0.35, 0.47, 0.6])
        add("upright_row", "直立划船", "Upright Row", .traps, [.shoulders], .barbell, std: [0.3, 0.5, 0.7, 0.9, 1.1])
        add("barbell_shrug", "杠铃耸肩", "Barbell Shrug", .traps, [], .barbell, std: [0.6, 1.0, 1.4, 1.8, 2.2])
        add("db_shrug", "哑铃耸肩", "Dumbbell Shrug", .traps, [], .dumbbell, std: [0.25, 0.4, 0.6, 0.8, 1.0])
        // Arms
        add("barbell_curl", "杠铃弯举", "Barbell Curl", .biceps, [.forearms], .barbell, std: [0.25, 0.4, 0.6, 0.8, 1.0])
        add("db_curl", "哑铃弯举", "Dumbbell Curl", .biceps, [.forearms], .dumbbell, std: [0.1, 0.18, 0.28, 0.38, 0.5])
        add("hammer_curl", "锤式弯举", "Hammer Curl", .biceps, [.forearms], .dumbbell, std: [0.1, 0.19, 0.3, 0.4, 0.52])
        add("preacher_curl", "牧师凳弯举", "Preacher Curl", .biceps, [], .barbell, std: [0.2, 0.35, 0.5, 0.7, 0.9])
        add("cable_curl", "绳索弯举", "Cable Curl", .biceps, [], .cable, std: [0.25, 0.4, 0.6, 0.8, 1.0])
        add("close_grip_bench", "窄握卧推", "Close-Grip Bench Press", .triceps, [.chest], .barbell, std: [0.45, 0.75, 1.05, 1.4, 1.75])
        add("skullcrusher", "仰卧臂屈伸", "Skullcrusher", .triceps, [], .barbell, std: [0.25, 0.4, 0.6, 0.8, 1.0])
        add("tricep_pushdown", "绳索下压", "Tricep Pushdown", .triceps, [], .cable, std: [0.3, 0.5, 0.7, 0.9, 1.15])
        add("overhead_tricep_ext", "过头臂屈伸", "Overhead Tricep Extension", .triceps, [], .dumbbell, std: [0.15, 0.28, 0.42, 0.56, 0.7])
        add("bench_dips", "凳上臂屈伸", "Bench Dips", .triceps, [], .bodyweight, bw: 0.6)
        add("wrist_curl", "腕弯举", "Wrist Curl", .forearms, [], .barbell, std: [0.2, 0.35, 0.5, 0.65, 0.8])
        add("reverse_curl", "反握弯举", "Reverse Curl", .forearms, [.biceps], .barbell, std: [0.15, 0.28, 0.42, 0.58, 0.75])
        add("farmers_walk", "农夫行走", "Farmer's Walk", .forearms, [.traps], .dumbbell, std: [0.3, 0.5, 0.7, 0.9, 1.1], tip: "单手重量；次数栏填写步数。")
        // Legs
        add("squat", "杠铃深蹲", "Back Squat", .quads, [.glutes, .hamstrings], .barbell, std: [0.7, 1.1, 1.5, 1.95, 2.4], stdF: [0.45, 0.75, 1.05, 1.4, 1.75], tip: "脚尖略外展，膝盖跟随脚尖方向，蹲至大腿平行或更低。")
        add("front_squat", "前蹲", "Front Squat", .quads, [.glutes, .abs], .barbell, std: [0.55, 0.9, 1.25, 1.6, 2.0])
        add("leg_press", "腿举", "Leg Press", .quads, [.glutes], .machine, std: [1.2, 2.0, 2.8, 3.6, 4.5])
        add("hack_squat", "哈克深蹲", "Hack Squat", .quads, [.glutes], .machine, std: [0.8, 1.3, 1.8, 2.3, 2.9])
        add("leg_extension", "腿屈伸", "Leg Extension", .quads, [], .machine, std: [0.5, 0.8, 1.1, 1.45, 1.8])
        add("goblet_squat", "高脚杯深蹲", "Goblet Squat", .quads, [.glutes], .dumbbell, std: [0.25, 0.4, 0.6, 0.8, 1.0])
        add("bulgarian_split_squat", "保加利亚分腿蹲", "Bulgarian Split Squat", .quads, [.glutes], .dumbbell, std: [0.15, 0.3, 0.45, 0.6, 0.8], tip: "单手哑铃重量。")
        add("lunge", "哑铃箭步蹲", "Dumbbell Lunge", .quads, [.glutes], .dumbbell, std: [0.15, 0.28, 0.42, 0.58, 0.75])
        add("bodyweight_squat", "自重深蹲", "Bodyweight Squat", .quads, [.glutes], .bodyweight, bw: 0.75)
        add("rdl", "罗马尼亚硬拉", "Romanian Deadlift", .hamstrings, [.glutes, .lowerBack], .barbell, std: [0.6, 1.0, 1.4, 1.8, 2.2])
        add("leg_curl", "腿弯举", "Leg Curl", .hamstrings, [], .machine, std: [0.35, 0.6, 0.85, 1.1, 1.4])
        add("good_morning", "早安式", "Good Morning", .hamstrings, [.lowerBack], .barbell, std: [0.3, 0.55, 0.8, 1.05, 1.3])
        add("nordic_curl", "北欧腿弯举", "Nordic Curl", .hamstrings, [], .bodyweight, bw: 0.7)
        add("hip_thrust", "臀推", "Hip Thrust", .glutes, [.hamstrings], .barbell, std: [0.8, 1.3, 1.8, 2.3, 2.9], stdF: [0.7, 1.1, 1.5, 1.95, 2.4])
        add("sumo_deadlift", "相扑硬拉", "Sumo Deadlift", .glutes, [.quads, .back], .barbell, std: [0.8, 1.3, 1.8, 2.3, 2.8])
        add("glute_bridge", "臀桥", "Glute Bridge", .glutes, [], .bodyweight, bw: 0.5)
        add("cable_kickback", "绳索后踢", "Cable Kickback", .glutes, [], .cable)
        add("hyperextension", "山羊挺身", "Back Extension", .lowerBack, [.glutes], .bodyweight, bw: 0.5, std: [0.55, 0.7, 0.85, 1.0, 1.2])
        add("standing_calf_raise", "站姿提踵", "Standing Calf Raise", .calves, [], .machine, std: [0.8, 1.3, 1.8, 2.3, 2.8])
        add("seated_calf_raise", "坐姿提踵", "Seated Calf Raise", .calves, [], .machine, std: [0.4, 0.7, 1.0, 1.3, 1.6])
        // Core
        add("plank", "平板支撑", "Plank", .abs, [], .bodyweight, tip: "次数栏填写秒数。")
        add("hanging_leg_raise", "悬垂举腿", "Hanging Leg Raise", .abs, [], .bodyweight, bw: 0.35, std: [0.3, 0.38, 0.46, 0.55, 0.65])
        add("cable_crunch", "绳索卷腹", "Cable Crunch", .abs, [], .cable, std: [0.35, 0.6, 0.85, 1.1, 1.4])
        add("ab_wheel", "健腹轮", "Ab Wheel Rollout", .abs, [], .other)
        add("russian_twist", "俄罗斯转体", "Russian Twist", .abs, [], .bodyweight)
        add("crunch", "卷腹", "Crunch", .abs, [], .bodyweight)
        add("kb_swing", "壶铃摆荡", "Kettlebell Swing", .glutes, [.hamstrings, .abs], .kettlebell, std: [0.2, 0.3, 0.42, 0.55, 0.7])
        add("clean_and_press", "高翻推举", "Clean and Press", .fullBody, [.shoulders, .quads], .barbell, std: [0.4, 0.65, 0.9, 1.15, 1.4])
        // Cardio (reps = minutes, weight = distance km)
        add("running", "跑步", "Running", .cardio, [], .cardio, cardio: true)
        add("cycling", "骑行", "Cycling", .cardio, [], .cardio, cardio: true)
        add("rowing", "划船机", "Rowing", .cardio, [], .cardio, cardio: true)
        add("swimming", "游泳", "Swimming", .cardio, [], .cardio, cardio: true)
        add("walking", "步行", "Walking", .cardio, [], .cardio, cardio: true)
        add("stair_climb", "爬楼", "Stair Climbing", .cardio, [], .cardio, cardio: true)
        add("hiit", "HIIT", "HIIT", .cardio, [], .cardio, cardio: true)
        add("jump_rope", "跳绳", "Jump Rope", .cardio, [], .cardio, cardio: true)
        return list
    }
}
