import SwiftUI
import SwiftData

/// A persistent main-tab destination. Joining a room does not replace the tab bar.
struct GymHubView: View {
    let profile: UserProfile
    @EnvironmentObject private var store: GymStore
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var plans: [DailyPlan]
    @AppStorage(TrainingPortraitFile.revisionKey) private var portraitRevision = 0
    @State private var portrait: UIImage?
    @State private var showSettings = false
    private var session: Workout? { workouts.first { !$0.isPublished } }
    private var gsr: Int {
        RankAggregator.overall(muscleScores: RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)))
    }
    /// The player's own look: local nickname, cosmetics and portrait, never a truncated cloud copy.
    private var mine: SocialProfile {
        SocialProfile(uid: store.uid, name: profile.name, gsr: gsr, cosmetics: profile.sharedCosmeticIDs, interests: store.me?.interests ?? "", avatar: store.me?.avatar ?? AvatarAppearance())
    }
    private var workoutSummary: String {
        if let active = session, !active.isPublished {
            return active.sortedExercises.map { entry in
                let name = exercises.first { $0.key == entry.exerciseKey }?.nameEn ?? entry.exerciseName
                let sets = entry.sortedSets.filter(\.isCompleted).map {
                    entry.isCardio ? "\($0.reps) minutes, \($0.weightKg.fmt(1)) km" : "\($0.reps) reps at \($0.weightKg.fmt(1)) kg"
                }
                return "\(name): \(sets.isEmpty ? "planned" : sets.joined(separator: ", "))"
            }.joined(separator: "; ")
        }
        return "No active workout. Ask about today's training goals."
    }
    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            Picker("Community section", selection: $app.communitySection) {
                Text("Gym").tag(0); Text(store.inboxCount > 0 ? "Messages (\(store.inboxCount))" : "Messages").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 6).background(.regularMaterial).accessibilityIdentifier("communitySection")
            if app.communitySection == 1 {
                GymFriendsView(store: store, workout: workoutSummary, embedded: true)
            } else {
                NavigationStack {
                    Group {
                        if let gym = store.room {
                            GymRoomView(store: store, gym: gym, profile: profile, session: session,
                                        workoutSummary: workoutSummary, startSession: startSession)
                        } else { lobby }
                    }
                    .sheet(isPresented: $showSettings) { CommunityProfileView(store: store, profile: profile) }
                }
            }
        }
        .task(id: portraitRevision) { portrait = TrainingPortraitFile.image() }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["LIFTRANK_GYM"] == "sample", store.uid.isEmpty {
                store.sample(name: ProcessInfo.processInfo.environment["LIFTRANK_GYM_NAME"] ?? profile.name, gsr: gsr, cosmetics: profile.sharedCosmeticIDs)
                return
            }
            #endif
            if !store.prepared { await store.restore() }
            #if DEBUG
            if ProcessInfo.processInfo.environment["LIFTRANK_GYM"] == "live", store.configuration?.emulatorHost != nil, store.room == nil {
                store.perform {
                    if !store.connected {
                        try await store.connect(name: ProcessInfo.processInfo.environment["LIFTRANK_GYM_NAME"] ?? profile.name,
                                                gsr: gsr, cosmetics: profile.sharedCosmeticIDs, interests: "Demo strength training")
                    }
                    try await store.join(.demo)
                    do { try beginSession() } catch { await store.leave(); throw error }
                }
            }
            #endif
        }
    }
    private var lobby: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Where are you training?").font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Choose a gym or make your own space.").foregroundStyle(.white.opacity(0.8))
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white).background(Color(red: 0.07, green: 0.18, blue: 0.22), in: RoundedRectangle(cornerRadius: 24))
                if store.restoring || (!store.prepared && store.restoreError == nil) {
                    ProgressView("Restoring your community profile…")
                } else if let error = store.restoreError {
                    Text(error).font(.callout).foregroundStyle(.orange)
                    Button("Retry connection") { Task { await store.restore() } }.buttonStyle(.bordered)
                } else if !store.connected { onboarding }
                else {
                    HStack(spacing: 12) {
                        GymAvatarView(profile: mine, image: portrait ?? store.portraits[store.uid], size: 46)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Welcome back, \(profile.name)").font(.headline)
                            Text("Your profile and avatar are ready.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error = store.error { Text(error).font(.callout).foregroundStyle(.orange).accessibilityIdentifier("gymError") }
                if store.busy { ProgressView("One moment…") }
                WorkoutSpacePicker(store: store, startLocal: {
                    do { try beginSession(); store.startPrivateSpace(name: profile.name, gsr: gsr, cosmetics: profile.sharedCosmeticIDs) }
                    catch { store.error = error.localizedDescription }
                }, entered: beginSession)
                presetCard
            }.padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Start workout").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Community settings")
            }
        }
    }
    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 12) {
            CommunityOnboardingCard(store: store, profile: profile, gsr: gsr)
        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("DEMO GYM · PRESET", systemImage: "building.2.fill").font(.caption.bold()).foregroundStyle(.teal)
            Text("Meet here, from anywhere.").font(.title3.bold())
            Text(store.connected ? "Real multiplayer. No location required. Entering starts or resumes your current workout." : "Explore an offline sample with simulated members. No workout is recorded.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                if store.connected {
                    store.perform {
                        try await store.join(.demo)
                        do { try beginSession() }
                        catch { await store.leave(); throw error }
                    }
                } else { store.sample(name: profile.name, gsr: gsr, cosmetics: profile.sharedCosmeticIDs) }
            } label: {
                Label(store.connected ? "Enter live Demo Gym" : "Try offline sample", systemImage: "arrow.up.right").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(.teal).disabled(store.busy || store.restoring).accessibilityIdentifier("enterDemoGym")
        }.padding(18).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }
    private func beginSession() throws {
        _ = try WorkoutSession.startOrResume(profile: profile, context: context)
    }
    private func startSession() {
        do { try beginSession() } catch { store.error = L("Could not save the workout: %@", error.localizedDescription) }
    }
}

struct GymAvatarView: View {
    let profile: SocialProfile?
    var image: UIImage?
    var size: CGFloat = 44
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: profile?.avatar.symbol ?? "person.fill").font(.system(size: size * 0.4)).frame(width: size, height: size).background((profile?.avatar.tint ?? .teal).opacity(0.2)) }
        }.frame(width: size, height: size).clipShape(Circle())
            .overlay(Circle().strokeBorder(profile?.avatar.tint ?? .teal, lineWidth: 2))
    }
}
