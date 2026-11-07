import SwiftUI
import SwiftData

struct RankCalculatorView: View {
    let profile: UserProfile
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var exerciseKey = "bench_press"
    @State private var weightText = "60"
    @State private var reps = 5
    @State private var rir = 0
    @State private var bodyweightText = ""
    @State private var sex: Sex = .male

    private var exercise: Exercise? { exercises.first { $0.key == exerciseKey } }
    private var ranked: [Exercise] { exercises.filter { $0.isRanked } }

    var body: some View {
        let unit = profile.unit
        let bw = unit.toKg(Double(bodyweightText) ?? 0)
        let w = unit.toKg(Double(weightText) ?? 0)
        Form {
            Section("输入") {
                InputRow("动作") {
                    Picker("动作", selection: $exerciseKey) { ForEach(ranked) { Text($0.name).tag($0.key) } }
                        .labelsHidden().pickerStyle(.menu)
                }
                InputRow("重量 (\(unit.label))") {
                    TextField("重量", text: $weightText).keyboardType(.decimalPad).formInputStyle()
                }
                InputStepper(title: "次数", value: $reps, range: 1...30)
                InputStepper(title: "RIR（剩余次数）", value: $rir, range: 0...6)
                InputRow("体重 (\(unit.label))") {
                    TextField("体重", text: $bodyweightText).keyboardType(.decimalPad).formInputStyle()
                }
                InputRow("评分曲线") {
                    Picker("评分曲线", selection: $sex) { ForEach(Sex.allCases) { Text($0.label).tag($0) } }
                        .labelsHidden().pickerStyle(.segmented)
                }
            }
            if let ex = exercise, bw > 0 {
                let load = StrengthScoring.effectiveLoad(exercise: ex, weightKg: w, bodyweightKg: bw)
                let e1 = StrengthScoring.epley(weightKg: load, reps: reps, rir: rir)
                let score = StrengthScoring.score(e1RM: e1, bodyweightKg: bw, anchors: ex.standards(for: sex))
                Section("结果") {
                    HStack { Spacer(); ScoreGauge(score: score); Spacer() }
                    LabeledContent("估算 1RM (Epley)", value: "\(unit.fromKg(e1).fmt(1)) \(unit.label)")
                    LabeledContent("相对力量", value: "\((e1 / bw).fmt(2)) × 体重")
                    LabeledContent("段位进度", value: "\(RankTier.lp(for: score)) LP")
                }
                Section("各段位所需重量（\(reps) 次）") {
                    ForEach(RankTier.allCases) { t in
                        let ratio = StrengthScoring.ratio(forScore: t.minScore, anchors: ex.standards(for: sex))
                        let e1Needed = ratio * bw
                        let loadNeeded = e1Needed / (reps == 1 ? 1 : (1 + Double(min(reps + rir, 30)) / 30))
                        let external = loadNeeded - ex.bodyweightFactor * bw
                        HStack {
                            TierBadge(tier: t)
                            Spacer()
                            Text(external <= 0 && ex.bodyweightFactor > 0 ? "自重即可" : "\(unit.fromKg(max(0, external)).fmt(1)) \(unit.label)")
                                .monospacedDigit().foregroundStyle(score >= t.minScore ? .green : .primary)
                        }
                    }
                }
            }
            Section {
                Text("估算 1RM = 重量 × (1 + 次数 ÷ 30)，次数上限 30，RIR 会加到次数上。自重动作按体重系数折算等效负重。评分按体重比值在动作标准曲线上插值得到，1–1000。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("评分计算器")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { bodyweightText = unit.fromKg(profile.bodyweightKg).fmt(1); sex = profile.sex }
    }
}
