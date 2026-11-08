import SwiftUI
import SwiftData
import Charts

struct ExerciseProgressView: View {
    let exerciseKey: String
    let profile: UserProfile
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]

    private var exercise: Exercise? { exercises.first { $0.key == exerciseKey } }

    private struct Point: Identifiable { let id = UUID(); let date: Date; let e1RM: Double; let volume: Double; let bestSet: WorkoutSet?; let score: Int; let isPR: Bool }

    private var points: [Point] {
        guard let ex = exercise else { return [] }
        var best = 0.0
        return workouts.filter { $0.isPublished }
            .sorted { ($0.publishedAt ?? $0.startedAt) < ($1.publishedAt ?? $1.startedAt) }
            .compactMap { w in
                guard let we = w.exercises.first(where: { $0.exerciseKey == exerciseKey }) else { return nil }
                let sets = we.sets.filter { $0.isCompleted && $0.type != .warmup }
                guard !sets.isEmpty else { return nil }
                let top = sets.max { StrengthScoring.e1RM(set: $0, exercise: ex, bodyweightKg: w.bodyweightKg) < StrengthScoring.e1RM(set: $1, exercise: ex, bodyweightKg: w.bodyweightKg) }!
                let e = StrengthScoring.e1RM(set: top, exercise: ex, bodyweightKg: w.bodyweightKg)
                let isPR = e > best + 0.01
                best = max(best, e)
                return Point(date: w.publishedAt ?? w.startedAt, e1RM: e, volume: sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }, bestSet: top,
                             score: StrengthScoring.score(set: top, exercise: ex, bodyweightKg: w.bodyweightKg, sex: profile.sex), isPR: isPR)
            }
    }

    var body: some View {
        let pts = points
        let unit = profile.unit
        ScrollView {
            VStack(spacing: 16) {
                if let ex = exercise {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppLanguage.current.isEnglish ? ex.name : ex.nameEn).font(.caption).foregroundStyle(.secondary)
                            Text("\(ex.muscleGroup.name) · \(ex.equipment.name)").font(.caption).foregroundStyle(.secondary)
                            if !ex.instructions.isEmpty { Text(L(ex.instructions)).font(.footnote) }
                        }
                        Spacer()
                        if let best = pts.map(\.score).max() { ScoreGauge(score: best, size: 90) }
                    }.card()
                }
                if pts.isEmpty {
                    Text("暂无记录。").foregroundStyle(.secondary).padding()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("估算 1RM 趋势").font(.headline)
                        Chart(pts) { p in
                            LineMark(x: .value("日期", p.date), y: .value("e1RM", unit.fromKg(p.e1RM))).interpolationMethod(.monotone)
                            PointMark(x: .value("日期", p.date), y: .value("e1RM", unit.fromKg(p.e1RM)))
                                .foregroundStyle(p.isPR ? Color.orange : Color.accentColor)
                                .symbolSize(p.isPR ? 80 : 40)
                        }
                        .frame(height: 200)
                        .chartYAxisLabel(unit.label)
                        Text("橙色点为个人纪录 PR。").font(.caption2).foregroundStyle(.secondary)
                    }.card()

                    HStack {
                        StatTile(title: L("最佳 e1RM"), value: "\(unit.fromKg(pts.map(\.e1RM).max() ?? 0).fmt(1)) \(unit.label)")
                        StatTile(title: L("最佳单组"), value: bestSetLabel(pts, unit), color: .orange)
                        StatTile(title: L("PR 次数"), value: "\(pts.filter(\.isPR).count)", color: .green)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("训练量（\(unit.label)）").font(.headline)
                        Chart(pts) { p in BarMark(x: .value("日期", p.date, unit: .day), y: .value(L("训练量"), unit.fromKg(p.volume))) }
                            .chartYAxisLabel(unit.label)
                            .frame(height: 160)
                    }.card()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("历史").font(.headline)
                        ForEach(pts.reversed()) { p in
                            HStack {
                                Text(p.date.shortString).frame(width: 60, alignment: .leading)
                                if let s = p.bestSet { Text("\(unit.fromKg(s.weightKg).fmt(1)) × \(s.reps)") }
                                Spacer()
                                if p.isPR { Image(systemName: "trophy.fill").foregroundStyle(.orange).font(.caption) }
                                Text("\(p.score)").foregroundStyle(RankTier.tier(for: p.score).color).bold()
                            }.font(.subheadline)
                        }
                    }.card()
                }
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(exercise?.displayName ?? L("动作"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bestSetLabel(_ pts: [Point], _ unit: WeightUnit) -> String {
        guard let s = pts.max(by: { $0.e1RM < $1.e1RM })?.bestSet else { return "—" }
        return "\(unit.fromKg(s.weightKg).fmt(1))×\(s.reps)"
    }
}
