import SwiftUI
import SwiftData

struct GymEquipmentSheet: View {
    @Bindable var workout: Workout
    let profile: UserProfile
    let station: String
    var requiresEquipment = false
    let onLogged: (String, Int) -> Void
    @EnvironmentObject private var gym: GymStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    @Query private var workouts: [Workout]
    @State private var selectedKey = ""
    @State private var weight = ""
    @State private var reps = ""
    @State private var error: String?
    @State private var saved = false
    @FocusState private var inputFocused: Bool
    private var logging: Bool { workout.setEndedAt != nil }
    private var choices: [Exercise] {
        if workout.hasPendingSet { return exercises.filter { $0.key == workout.currentExerciseKey } }
        if station == "all" || station == "lounge" {
            return exercises.filter { !$0.isCardio }.sorted { a, b in
                let aPlanned = workout.exercises.contains { $0.exerciseKey == a.key }
                let bPlanned = workout.exercises.contains { $0.exerciseKey == b.key }
                return aPlanned != bPlanned ? aPlanned : a.nameEn < b.nameEn
            }
        }
        return GymEquipment.exerciseKeys(at: station).compactMap { key in exercises.first { $0.key == key } }
    }
    private var exercise: Exercise? { choices.first { $0.key == selectedKey } }
    private var enteredWeight: Double? { try? Double(weight, format: .number) }
    private var enteredReps: Int? { try? Int(reps, format: .number) }
    private var valid: Bool {
        guard let exercise, let weight = enteredWeight, let reps = enteredReps else { return false }
        let kg = exercise.isCardio ? weight : profile.unit.toKg(weight)
        return weight.isFinite && kg.isFinite && kg >= 0 && kg <= (exercise.isCardio ? 1000 : 1500) && reps > 0 && reps <= (exercise.isCardio ? 1440 : 1000)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(station == "all" ? "Your workout" : GymEquipment.title(station), systemImage: station == "cardio" ? "figure.run" : "dumbbell.fill").font(.title2.bold())
                    Text(logging ? "Set ended. Rest has started. Confirm your reps and weight to save it." : "Choose your exercise, then start the set. Tap End set when you finish.").font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Exercise") {
                    Picker("Exercise", selection: $selectedKey) {
                        ForEach(choices, id: \.key) { Text($0.nameEn).tag($0.key) }
                    }.accessibilityIdentifier("gymExercise")
                    if let exercise {
                        let completed = workout.exercises.first { $0.exerciseKey == exercise.key }?.sets.filter(\.isCompleted).count ?? 0
                        Text("\(completed) completed · logging set \(completed + 1)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let exercise, logging {
                    Section(exercise.isCardio ? "Cardio effort" : "Completed set") {
                        LabeledContent(exercise.isCardio ? "Distance (km)" : "Weight (\(profile.unit.label))") {
                            TextField(exercise.isCardio ? "km" : profile.unit.label, text: $weight)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($inputFocused).accessibilityIdentifier("gymSetWeight")
                        }
                        LabeledContent(exercise.isCardio ? "Minutes" : "Reps") {
                            TextField(exercise.isCardio ? "Minutes" : "Reps", text: $reps)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).focused($inputFocused).accessibilityIdentifier("gymSetReps")
                        }
                        if exercise.key.contains("db_") { Text("Use the weight of one dumbbell.").font(.caption).foregroundStyle(.secondary) }
                        if exercise.bodyweightFactor > 0 { Text("Enter added weight; use 0 for bodyweight only.").font(.caption).foregroundStyle(.secondary) }
                    }
                    Section {
                        Button { log(exercise) } label: { Label("Save completed set", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity) }
                            .disabled(!valid || saved || workout.isPublished).accessibilityIdentifier("gymSaveSet")
                        if let error { Text(error).foregroundStyle(.orange) }
                    }
                } else if let exercise {
                    Button {
                        guard !requiresEquipment || gym.ownsStation(station) else { error = L("This equipment is no longer reserved for you."); return }
                        do { try WorkoutSession.beginSet(workout, exerciseKey: exercise.key, context: context); dismiss() }
                        catch { self.error = error.localizedDescription }
                    } label: { Label("Start set", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .disabled(workout.hasPendingSet).accessibilityIdentifier("confirmStartSet")
                } else { Text("No matching exercise is available in your catalogue.") }
                if workout.hasPendingSet {
                    Button("Discard this set", role: .destructive) {
                        do { try WorkoutSession.discardSet(workout, context: context); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle(logging ? "Save your set" : "Start a set").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { inputFocused = false } }
            }
            .onAppear {
                // Prefer an unfinished planned exercise at this station.
                selectedKey = choices.first { candidate in workout.exercises.contains { $0.exerciseKey == candidate.key && $0.sets.contains { !$0.isCompleted } } }?.key ?? choices.first?.key ?? ""
                prefill()
            }
            .onChange(of: selectedKey) { _, _ in prefill() }
        }
    }
    private func prefill() {
        guard let exercise else { return }
        let entry = workout.exercises.first { $0.exerciseKey == exercise.key }
        let previous = entry?.sortedSets.first { !$0.isCompleted } ?? entry?.sortedSets.last
            ?? WorkoutPublisher.lastSets(for: exercise.key, workouts: workouts, excluding: workout).first
        weight = exercise.isCardio ? (previous?.weightKg ?? 0).formatted(.number) : profile.unit.inputText(kg: previous?.weightKg ?? 0)
        reps = (previous?.reps ?? 0) > 0 ? "\(previous!.reps)" : ""
        error = nil
    }
    private func log(_ exercise: Exercise) {
        guard !saved, let weight = enteredWeight, let reps = enteredReps else { return }
        do {
            try WorkoutSession.saveEndedSet(workout, exercise: exercise, weight: weight, reps: reps, unit: profile.unit,
                                   restSeconds: profile.defaultRestSeconds, context: context)
            saved = true
            let rest = workout.exercises.first { $0.exerciseKey == exercise.key }?.restSeconds ?? profile.defaultRestSeconds
            onLogged(exercise.nameEn, rest)
            dismiss()
        } catch { self.error = L("Could not save this set. %@", error.localizedDescription) }
    }
}
