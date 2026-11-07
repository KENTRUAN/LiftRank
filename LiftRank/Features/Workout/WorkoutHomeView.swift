import SwiftUI
import SwiftData

struct WorkoutHomeView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse) private var templates: [WorkoutTemplate]
    @Query private var exercises: [Exercise]
    @State private var activeWorkout: Workout?
    @State private var showGenerator = false

    private var unpublished: Workout? { workouts.first { !$0.isPublished } }
    private var history: [Workout] { workouts.filter { $0.isPublished } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let w = unpublished {
                        Button { activeWorkout = w } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("继续训练：\(w.title)").bold()
                                    Text("已进行 \(w.duration.clockString) · \(w.completedSets.count) 组已完成").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.green)
                            }
                        }
                    } else {
                        Button { startEmpty() } label: {
                            Label("开始空白训练", systemImage: "plus.circle.fill").font(.headline)
                        }
                    }
                    Button { showGenerator = true } label: {
                        Label("按目标生成训练 / 多周计划", systemImage: "wand.and.stars")
                    }
                }

                if !templates.isEmpty {
                    Section("预设") {
                        ForEach(templates) { t in
                            Button { start(from: t) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name).foregroundStyle(.primary)
                                    Text(t.planName.isEmpty ? "\(t.items.count) 个动作" : "\(t.planName) · \(t.items.count) 个动作")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .disabled(unpublished != nil)
                        }
                        .onDelete { idx in idx.map { templates[$0] }.forEach(context.delete) }
                    }
                }

                Section(history.isEmpty ? "历史" : "历史 · \(history.count) 次") {
                    if history.isEmpty {
                        Text("还没有发布的训练。开始一次训练，完成后发布即可获得评分、XP 与 Eggs。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(history) { w in
                        NavigationLink { WorkoutDetailView(workout: w, profile: profile) } label: { WorkoutRow(workout: w, unit: profile.unit) }
                    }
                    .onDelete { idx in
                        idx.map { history[$0] }.forEach(context.delete)
                        try? context.save()
                    }
                }
            }
            .navigationTitle("训练")
            .fullScreenCover(item: $activeWorkout) { w in
                ActiveWorkoutView(workout: w, profile: profile)
            }
            .sheet(isPresented: $showGenerator) { WorkoutGeneratorView(profile: profile) }
            .onAppear { if DemoData.autoOpenActive, activeWorkout == nil { activeWorkout = unpublished } }
        }
    }

    private func startEmpty() {
        let w = Workout(title: defaultTitle(), bodyweightKg: profile.bodyweightKg)
        context.insert(w)
        try? context.save()
        activeWorkout = w
    }

    private func start(from template: WorkoutTemplate) {
        let w = Workout(title: template.name, bodyweightKg: profile.bodyweightKg)
        context.insert(w)
        let byKey = Dictionary(uniqueKeysWithValues: exercises.map { ($0.key, $0) })
        for (i, item) in template.items.enumerated() {
            guard let ex = byKey[item.exerciseKey] else { continue }
            let we = WorkoutExercise(order: i, exercise: ex, restSeconds: item.restSeconds)
            let prev = WorkoutPublisher.lastSets(for: ex.key, workouts: workouts, excluding: nil)
            for s in 0..<item.sets {
                let set = WorkoutSet(order: s, weightKg: prev.indices.contains(s) ? prev[s].weightKg : (prev.last?.weightKg ?? 0), reps: item.repsLow)
                we.sets.append(set)
            }
            w.exercises.append(we)
        }
        try? context.save()
        activeWorkout = w
    }

    private func defaultTitle() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 11 ? "晨间训练" : h < 17 ? "午后训练" : "夜间训练"
    }
}

struct WorkoutRow: View {
    let workout: Workout
    let unit: WeightUnit
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.title).bold()
                Text("\((workout.publishedAt ?? workout.startedAt).shortString) · \(workout.duration.clockString) · \(workout.exercises.count) 动作 · \(unit.fromKg(workout.totalVolumeKg).fmt(0)) \(unit.label)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if workout.strengthScore > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(workout.strengthScore)").font(.subheadline.bold().monospacedDigit())
                    TierBadge(tier: RankTier.tier(for: workout.strengthScore), compact: true)
                }
            }
        }
    }
}
