import SwiftUI
import SwiftData

/// Cardio has one activity and one elapsed-time recording, never strength sets or presets.
struct CardioStartView: View {
    let profile: UserProfile
    var requiresEquipment = false
    var initialOutdoor = false
    let onStarted: (Workout) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var gym: GymStore
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var cardio: [CardioSession]
    @Query private var claims: [QuestClaim]
    @State private var activity = TrainingActivity.running
    @State private var outdoor = false
    @State private var confirmSwitch = false
    @State private var busy = false
    @State private var error: String?
    private var active: Workout? { workouts.first { !$0.isPublished } }
    private var timed: Workout? { active.flatMap { $0.cardioTimerStartedAt != nil && $0.activity != .strength ? $0 : nil } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activity", selection: $activity) {
                        ForEach(TrainingActivity.allCases.filter { $0 != .strength && (!requiresEquipment || $0 != .swimming) }) { Text($0.name).tag($0) }
                    }.accessibilityIdentifier("cardioActivity")
                    if !requiresEquipment {
                        Picker("Location", selection: $outdoor) { Text("Indoor").tag(false); Text("Outdoor").tag(true) }.pickerStyle(.segmented)
                    }
                    Text("Start begins the timer. End saves your elapsed time automatically.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button(timed == nil ? "Start cardio" : "Resume cardio") {
                        if let timed { onStarted(timed); return }
                        guard active?.hasPendingSet != true else { error = "Finish your current strength set first."; return }
                        if let active, !active.exercises.isEmpty || !active.notes.isEmpty || !active.routePoints.isEmpty { confirmSwitch = true }
                        else { start() }
                    }.disabled(busy).accessibilityIdentifier("startCardioTimer")
                    if busy { ProgressView("Starting…") }
                    if let error { Text(error).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("Cardio").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { outdoor = initialOutdoor && !requiresEquipment }
            .confirmationDialog("Finish your current workout and start cardio? Recorded sets are kept; uncompleted todos are removed.", isPresented: $confirmSwitch, titleVisibility: .visible) {
                Button("Finish workout & start cardio") { start(finishing: true) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
    private func start(finishing: Bool = false) {
        guard !requiresEquipment || gym.ownsStation("cardio") else { error = "This cardio machine is no longer reserved for you."; return }
        busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                var convertingEmpty: Workout?
                if let current = active {
                    guard !current.hasPendingSet else { throw GymFailure.message("Finish the current set first.") }
                    if finishing {
                        _ = WorkoutPublisher.publish(current, profile: profile, exercises: exercises, workouts: workouts, cardio: cardio, claims: claims, context: context)
                        await TrainingHealthManager.shared.finish(current, context: context)
                    } else {
                        guard current.exercises.isEmpty, current.notes.isEmpty, current.routePoints.isEmpty else { throw GymFailure.message("Finish your current workout first.") }
                        TrainingHealthManager.shared.discard(current); convertingEmpty = current
                    }
                }
                if !requiresEquipment, gym.station != "lounge", gym.membership != nil { try await gym.equipmentAction(gym.station, "release") }
                let session = try CardioWorkoutSession.start(profile: profile, activity: activity, outdoor: outdoor, context: context, convertingEmpty: convertingEmpty)
                onStarted(session)
                await TrainingHealthManager.shared.start(session, context: context)
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct CardioTimerControls: View {
    @Bindable var workout: Workout
    let profile: UserProfile
    var onEnded: () -> Void = {}
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var gym: GymStore
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var cardio: [CardioSession]
    @Query private var claims: [QuestClaim]
    @State private var error: String?
    @State private var ending = false
    @State private var pausing = false
    var body: some View {
        VStack(spacing: 12) {
            if workout.isPublished {
                Label("Cardio saved", systemImage: "checkmark.circle.fill").foregroundStyle(.teal).accessibilityIdentifier("cardioSaved")
                Text(workout.duration.clockString).font(.title.monospacedDigit()).accessibilityIdentifier("cardioSavedDuration")
            } else if workout.cardioTimerStartedAt != nil {
                HStack {
                    Label(workout.cardioIsPaused ? "Paused" : workout.activity.name, systemImage: workout.cardioIsPaused ? "pause.circle" : "figure.run")
                    Spacer()
                    CardioElapsedText(workout: workout).accessibilityIdentifier("cardioElapsed")
                }.font(.title2.bold())
                if workout.endedAt == nil {
                    Button { pauseOrResume() } label: { Label(workout.cardioIsPaused ? "Resume cardio" : "Pause cardio", systemImage: workout.cardioIsPaused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).disabled(pausing || ending).accessibilityIdentifier("pauseResumeCardio")
                }
                Button { end() } label: { Label("End cardio", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.orange).disabled(ending).accessibilityIdentifier("endCardioTimer")
            } else {
                Text("This older cardio draft has no running timer. Start a new cardio session from Home or the gym.").font(.callout)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
    private func pauseOrResume() {
        pausing = true; error = nil
        Task {
            defer { pausing = false }
            do { try await CardioLiveActivityManager.shared.setPaused(!workout.cardioIsPaused, workoutID: workout.id.uuidString) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func end() {
        guard !ending else { return }; ending = true
        do {
            let record = try CardioWorkoutSession.finish(workout, context: context)
            let allCardio = cardio.contains(where: { $0.id == record.id }) ? cardio : cardio + [record]
            let gsr = RankAggregator.overall(muscleScores: RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)))
            _ = DailyTrainingEngine.claimIfEarned(profile: profile, workouts: workouts, cardio: allCardio, claims: claims, gsr: gsr, context: context)
            CardioLiveActivityManager.shared.refresh()
            onEnded()
            Task {
                if gym.station == "cardio", gym.ownsStation("cardio") { try? await gym.equipmentAction("cardio", "release") }
                await TrainingHealthManager.shared.finish(workout, context: context)
            }
        } catch { self.error = error.localizedDescription; ending = false }
    }
}

struct TimedCardioWorkoutView: View {
    @Bindable var workout: Workout
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var liveActivity = CardioLiveActivityManager.shared
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Label(workout.isOutdoor ? "Outdoor" : "Indoor", systemImage: workout.isOutdoor ? "sun.max" : "building.2").foregroundStyle(.secondary)
                    CardioTimerControls(workout: workout, profile: profile).padding(20).background(.background, in: RoundedRectangle(cornerRadius: 20))
                    if workout.isOutdoor { OutdoorWorkoutMap(workout: workout) }
                    TrainingHealthStatusView(workout: workout)
                    if let error = liveActivity.error, !workout.isPublished {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button("Retry Live Activity") { liveActivity.retry() }
                    }
                }.padding(20)
            }.background(Color(.systemGroupedBackground))
            .navigationTitle(workout.activity.name)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(workout.isPublished ? "Done" : "Minimize") { dismiss() } } }
            .task { if workout.cardioTimerStartedAt != nil { await TrainingHealthManager.shared.start(workout, context: workout.modelContext) } }
        }
    }
}

struct CardioElapsedText: View {
    @Bindable var workout: Workout
    var body: some View {
        let now = Date()
        let state = CardioActivityAttributes.ContentState(elapsed: workout.cardioElapsed(at: now), updatedAt: now, isPaused: workout.cardioIsPaused, isFinished: workout.endedAt != nil || workout.isPublished)
        CardioActivityClock(state: state)
    }
}
