import SwiftUI
import SwiftData

struct GymProfileSettingsView: View {
    @ObservedObject var store: GymStore
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var cardio: [CardioSession]
    @Query private var templates: [WorkoutTemplate]
    @State private var name = ""
    @State private var interests = ""
    @State private var visibility = "public"
    @State private var shareRank = false
    @State private var shareActivity = false
    @State private var publicIDs: Set<PersistentIdentifier> = []
    @State private var avatar = false
    @State private var saved = false
    var body: some View {
        NavigationStack {
            Form {
                if store.connected {
                    Section("Gym visibility") {
                        Picker("Mode", selection: $visibility) { Text("Public").tag("public"); Text("Anonymous").tag("anonymous") }.pickerStyle(.segmented).accessibilityIdentifier("gymVisibility")
                        Text(visibility == "anonymous" ? "A generic avatar. No profile or new friend requests. Existing conversations stay in Messages." : "Gym members can open your profile and ask to connect.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Shared profile") {
                        TextField("Nickname", text: $name).accessibilityIdentifier("gymEditNickname")
                        TextField("Training interests", text: $interests)
                        Toggle("Share my rank and equipped cosmetics", isOn: $shareRank)
                        Toggle("Share workout highlights & activity", isOn: $shareActivity)
                        Text("Share recent workout types, dates, duration, set counts, seven-day muscle scores and six-month activity totals. Measurements, weights, reps and notes remain private.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Public routines") {
                        if templates.isEmpty { Text("Create a routine on Home to share it here.").font(.caption) }
                        ForEach(templates) { routine in
                            Toggle(routine.name, isOn: Binding(get: { publicIDs.contains(routine.id) }, set: { if $0 { publicIDs.insert(routine.id) } else { publicIDs.remove(routine.id) } }))
                                .disabled(publicIDs.count >= 5 && !publicIDs.contains(routine.id))
                        }
                        Text("Up to five routines: exercise names and planned sets/reps only. Changes publish when you save.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        Button { avatar = true } label: {
                            HStack { GymAvatarView(profile: store.me, image: store.portraits[store.uid]); Text("Edit avatar") }
                        }
                    }
                    Section {
                        Button("Save community profile") {
                            let gsr = RankAggregator.overall(muscleScores: RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)))
                            store.perform {
                                let shared = GymProfileSnapshot.routines(templates.filter { publicIDs.contains($0.id) }, exercises: exercises, selectedOnly: false)
                                try await store.updateProfile(name: name, interests: interests, shareRank: shareRank, gsr: gsr, cosmetics: profile.sharedCosmeticIDs,
                                    muscleRanks: GymProfileSnapshot.ranks(profile: profile, workouts: workouts, exercises: exercises), shareActivity: shareActivity,
                                    highlights: shareActivity ? GymProfileSnapshot.highlights(profile: profile, workouts: workouts, exercises: exercises, cardio: cardio) : nil, routines: shared, visibility: visibility)
                                for routine in templates { routine.isPublic = publicIDs.contains(routine.id) }
                                try templates.first?.modelContext?.save()
                                saved = true
                            }
                        }.disabled(store.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if saved { Label("Profile saved", systemImage: "checkmark.circle.fill").foregroundStyle(.teal) }
                    }
                } else if store.restoring { ProgressView("Restoring profile…") }
                else {
                    Text("Create your shared profile once in the Community tab. You can edit it here afterward.")
                    if let error = store.restoreError { Text(error).foregroundStyle(.orange) }
                    Button("Retry connection") { Task { await restore() } }
                }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle("Community settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $avatar) { GymAvatarEditor(store: store) }
            .task { await restore() }
            .onChange(of: store.connected) { _, connected in if connected { loadDraft() } }
        }
    }
    private func restore() async {
        if !store.connected { await store.restore() }
        loadDraft()
    }
    private func loadDraft() {
        name = store.me?.name ?? profile.name
        interests = store.me?.interests ?? ""
        visibility = store.me?.visibility ?? "public"
        shareRank = store.sharesRank
        shareActivity = store.me?.shareActivity ?? false
        publicIDs = Set(templates.filter(\.isPublic).map(\.id))
    }
}
