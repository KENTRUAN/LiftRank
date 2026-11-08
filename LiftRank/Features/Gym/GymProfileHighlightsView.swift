import SwiftUI
import Charts

struct GymProfileHighlightsView: View {
    let profile: SocialProfile
    @State private var front = true
    private func scores(_ values: [String: Int]) -> [MuscleGroup: Int] {
        Dictionary(uniqueKeysWithValues: values.compactMap { key, value in MuscleGroup(rawValue: key).map { ($0, value) } })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !profile.muscleRanks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Highest ranked body parts").font(.headline)
                    ForEach(scores(profile.muscleRanks).sorted { $0.value > $1.value }.prefix(3), id: \.key) { group, score in
                        HStack {
                            Text(group.gymName); Spacer()
                            Text("\(score)").monospacedDigit().bold()
                            TierBadge(tier: RankTier.tier(for: score), compact: true)
                        }
                    }
                }.card()
            }
            if profile.shareActivity, let highlights = profile.highlights {
                HStack {
                    metric("Workouts", highlights.workoutCount, "dumbbell.fill")
                    Spacer()
                    metric("Day streak", highlights.streakDays, "flame.fill")
                }.card()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Last 7 days · muscle map").font(.headline)
                    Text("Strength scores from logged workouts in the past seven days.").font(.caption).foregroundStyle(.secondary)
                    Picker("Body view", selection: $front) { Text("Front").tag(true); Text("Back").tag(false) }.pickerStyle(.segmented)
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            BodySilhouette().fill(Color.secondary.opacity(0.12))
                            ForEach(front ? MuscleGroup.frontGroups : MuscleGroup.backGroups) { group in
                                BodyRegion(group: group, front: front)
                                    .fill(highlights.weekMuscles[group.rawValue].map { RankTier.tier(for: $0).color } ?? Color.secondary.opacity(0.13))
                            }
                        }.frame(width: 130, height: 255).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(front ? MuscleGroup.frontGroups : MuscleGroup.backGroups) { group in
                                HStack {
                                    Text(group.gymName).font(.caption)
                                    Spacer(minLength: 2)
                                    Text(highlights.weekMuscles[group.rawValue].map(String.init) ?? "—").font(.caption.monospacedDigit())
                                }
                            }
                        }
                    }
                    if highlights.weekMuscles.isEmpty { Text("No strength sets shared for this week.").font(.caption).foregroundStyle(.secondary) }
                }.card()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Last 6 months · activity").font(.headline)
                    Chart(highlights.months) { month in
                        let date = Date(timeIntervalSince1970: month.month / 1000)
                        LineMark(x: .value("Month", date, unit: .month), y: .value("Workouts", month.sessions)).foregroundStyle(.teal)
                        PointMark(x: .value("Month", date, unit: .month), y: .value("Workouts", month.sessions)).foregroundStyle(.teal)
                    }
                    .chartYScale(domain: 0...max(1, highlights.months.map(\.sessions).max() ?? 1))
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                    .frame(height: 150)
                    Text("\(highlights.months.reduce(0) { $0 + $1.sessions }) workouts in this period").font(.caption).foregroundStyle(.secondary)
                }.card()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Memories · recent workouts").font(.headline)
                    if highlights.memories.isEmpty { Text("No completed workouts shared yet.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(highlights.memories) { memory in
                        HStack(alignment: .top) {
                            Image(systemName: "dumbbell.fill").foregroundStyle(.teal).padding(8).background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(memory.title).font(.subheadline.bold())
                                Text(Date(timeIntervalSince1970: memory.date / 1000), format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary)
                                Text("\(memory.minutes) min · \(memory.sets) sets").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if memory.score > 0 { Text("\(memory.score)").font(.subheadline.bold()).foregroundStyle(RankTier.tier(for: memory.score).color) }
                        }
                    }
                }.card()
            } else {
                Label("Workout activity is private", systemImage: "lock").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).card()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Public routines").font(.headline)
                if profile.routines.isEmpty { Text("No public routines yet.").font(.caption).foregroundStyle(.secondary) }
                ForEach(profile.routines) { routine in
                    DisclosureGroup(routine.name) {
                        ForEach(Array(routine.exercises.enumerated()), id: \.offset) { _, exercise in
                            HStack(alignment: .top) {
                                Text(exercise.name); Spacer()
                                Text("\(exercise.sets) × \(exercise.repsLow)–\(exercise.repsHigh)").monospacedDigit()
                            }.font(.caption).padding(.vertical, 4)
                        }
                    }
                }
            }.card()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func metric(_ label: String, _ value: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.title2.bold().monospacedDigit())
        }
    }
}

extension MuscleGroup {
    var gymName: String {
        switch self {
        case .chest: "Chest"; case .shoulders: "Shoulders"; case .biceps: "Biceps"; case .triceps: "Triceps"
        case .forearms: "Forearms"; case .abs: "Core"; case .quads: "Quads"; case .calves: "Calves"
        case .back: "Back"; case .traps: "Traps"; case .glutes: "Glutes"; case .hamstrings: "Hamstrings"
        case .lowerBack: "Lower back"; case .cardio: "Cardio"; case .fullBody: "Full body"
        }
    }
}
