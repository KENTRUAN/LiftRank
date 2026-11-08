import SwiftUI
import SwiftData

/// Step two: the session already exists and is empty. A preset is optional.
struct WorkoutStartOptionsView: View {
    @Bindable var workout: Workout
    let profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var templates: [WorkoutTemplate]
    @Query private var plans: [DailyPlan]
    @Query private var exercises: [Exercise]
    @State private var choosingPreset = false
    @State private var error: String?
    @AppStorage("training.appleHealthEnabled") private var appleHealth = true
    @AppStorage(AIProgram.strengthKey) private var savedStrength = Data()
    @AppStorage(AIProgram.combinedKey) private var savedCombined = Data()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Your blank workout has started", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.teal)
                    Text("Keep it empty and add exercises as you go, or choose a preset in the next step.").font(.callout).foregroundStyle(.secondary)
                }
                Section("Apple workout tracking") {
                    Label("Traditional strength training", systemImage: "dumbbell.fill")
                    Toggle("Sync with Apple Health", isOn: $appleHealth)
                    Text("Uses the LiftRank Watch app when available, otherwise your iPhone. Health permission is requested only when needed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if choosingPreset {
                    Section("Optional preset") {
                        if let today = plans.first(where: { $0.dayKey == Date().dayKey && ($0.requestedByUser || $0.sourceRaw == "ai") }), !today.items.isEmpty {
                            Button("Today's plan · \(today.title)") { apply(today.title, today.items, plan: today) }
                        }
                        ForEach(templates) { preset in Button(preset.name) { apply(preset.name, preset.items, plan: nil) } }
                        if let program = AIProgram.load(savedStrength) { savedChoices(program) }
                        if let program = AIProgram.load(savedCombined) { savedChoices(program) }
                        if templates.isEmpty && savedStrength.isEmpty && savedCombined.isEmpty && !plans.contains(where: { $0.dayKey == Date().dayKey && ($0.requestedByUser || $0.sourceRaw == "ai") && !$0.items.isEmpty }) {
                            Text("No presets yet. You can create one on Home.")
                        }
                    }
                }
                Section {
                    Button("Keep workout blank") { finishSetup() }.accessibilityIdentifier("keepWorkoutBlank")
                    if !choosingPreset { Button("Choose a preset…") { choosingPreset = true }.accessibilityIdentifier("chooseWorkoutPreset") }
                }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle("Optional workout setup").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
    }
    private func savedChoices(_ program: AIProgram) -> some View {
        DisclosureGroup("Saved · \(program.title)") {
            ForEach(program.weeks) { week in
                ForEach(week.strength) { day in
                    Button("Week \(week.week) · \(day.title)") {
                        let items = day.resolved(using: exercises)
                        guard !items.isEmpty, items.count == day.items.count else {
                            error = L("Some exercises in this saved plan are unavailable. Your workout is unchanged.")
                            return
                        }
                        apply(day.title, items, plan: nil)
                    }
                }
            }
        }
    }
    private func apply(_ title: String, _ items: [TemplateExercise], plan: DailyPlan?) {
        do {
            try WorkoutSession.applyPreset(to: workout, title: title, items: items, exercises: exercises, context: context)
            plan?.workoutID = workout.id
            finishSetup()
        } catch { self.error = error.localizedDescription }
    }
    private func finishSetup() {
        workout.startOptionsChosen = true
        do {
            try context.save()
            dismiss()
            Task { await TrainingHealthManager.shared.start(workout, context: context) }
        } catch { workout.startOptionsChosen = false; self.error = error.localizedDescription }
    }
}

@MainActor
final class TrainingPulse: ObservableObject {
    static let shared = TrainingPulse()
    @Published var now = Date()
    private var task: Task<Void, Never>?
    private init() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// The same visible Start / End control is used on Home and in the social room.
struct WorkoutSetControl: View {
    @Bindable var workout: Workout
    let profile: UserProfile
    let onStart: () -> Void
    let onLog: () -> Void
    @Environment(\.modelContext) private var context
    @ObservedObject private var pulse = TrainingPulse.shared
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(workout.trainingState(at: pulse.now), systemImage: workout.trainingState(at: pulse.now) == "Training" ? "dumbbell.fill" : "timer")
                    .font(.headline).foregroundStyle(.teal)
                Spacer()
                if let started = workout.setStartedAt, workout.setEndedAt == nil { Text(started, style: .timer).monospacedDigit() }
                else if let until = workout.restUntil, until > pulse.now {
                    Text("Rest \(until.timeIntervalSince(pulse.now).clockString)").monospacedDigit()
                    Button("Skip") { workout.restUntil = nil; try? context.save() }
                }
            }
            if workout.setStartedAt != nil && workout.setEndedAt == nil {
                Button {
                    do {
                        let rest = workout.exercises.first { $0.exerciseKey == workout.currentExerciseKey }?.restSeconds ?? profile.defaultRestSeconds
                        try WorkoutSession.endSet(workout, restSeconds: rest, context: context)
                        onLog()
                    } catch { self.error = error.localizedDescription }
                } label: { Label("End set", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.orange).accessibilityIdentifier("workoutEndSet")
            } else if workout.hasPendingSet {
                Button("Log finished set", action: onLog).buttonStyle(.borderedProminent).accessibilityIdentifier("workoutLogFinishedSet")
            } else {
                Button(action: onStart) { Label("Start set", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.teal).disabled(workout.isPublished || workout.endedAt != nil).accessibilityIdentifier("workoutStartSet")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
}
