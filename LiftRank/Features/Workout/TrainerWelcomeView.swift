import SwiftUI

/// Read-only encouragement. Opening Home never applies an AI workout edit.
struct TrainerWelcomeView: View {
    let profile: UserProfile
    let mode: TrainingHomeMode
    @EnvironmentObject private var gym: GymStore
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var phase
    let workout: Workout?
    let plan: DailyPlan?
    @State private var message = L("Ready when you are. Start a workout, or tell me what you want to train.")
    @State private var loading = false
    @State private var unavailable = false
    @State private var lastAttempt = Date.distantPast
    @State private var requestID = UUID()
    private var identity: TrainerIdentity { TrainerIdentity(profile: profile) }
    private var refreshKey: String { "\(mode.rawValue)|\(identity.name)|\(identity.intro)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CoachFace(spec: profile.coachAvatar, size: 30)
                Text(identity.name).font(.caption.bold()).foregroundStyle(.teal)
                Spacer()
                if loading { ProgressView().controlSize(.mini) }
                if unavailable {
                    Button { Task { await refresh(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Trainer unavailable. Retry welcome message")
                }
            }
            Text(message).font(.subheadline).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Button("Talk to your trainer") { app.showCoach = true }
                .font(.caption.bold())
        }.padding(16).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityIdentifier("trainerWelcome")
            .task(id: refreshKey) { await refresh(force: true) }
            .onChange(of: phase) { _, value in
                if value == .active && app.tab == 0 { Task { await refresh() } }
            }
    }
    private func refresh(force: Bool = false) async {
        guard force || (!loading && Date().timeIntervalSince(lastAttempt) > 10) else { return }
        let request = UUID(); requestID = request
        if force {
            message = mode == .cardio ? L("Ready for cardio? Choose an indoor or outdoor activity to get started.") : L("Ready when you are. Start a workout, or tell me what you want to train.")
        }
        loading = true; lastAttempt = Date()
        defer { if requestID == request { loading = false } }
        do {
            let api = try await gym.trainerAPI()
            struct Welcome: Decodable { let reply: String }
            let response: Welcome = try await api.post("trainer/greeting", body: [
                "localDate": Date().dayKey,
                "language": AppLanguage.current.locale.identifier,
                "trainer": identity.requestContext,
                "trainingMode": mode == .cardio ? "cardio" : "strength",
                "status": workout.map { "\($0.activity.name), \($0.completedSets.count) sets completed, \($0.trainingState(at: Date()))" } ?? "No active workout",
                "plan": plan.map { "\($0.title), \($0.items.count) planned exercises" } ?? "No requested plan today"
            ])
            if !Task.isCancelled, requestID == request { message = response.reply; unavailable = false }
        } catch { if !Task.isCancelled, requestID == request { unavailable = true } }
    }
}
