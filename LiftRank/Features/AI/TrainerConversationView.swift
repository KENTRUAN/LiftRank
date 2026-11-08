import SwiftUI
import SwiftData

struct TrainerConversationView: View {
    let profile: UserProfile
    var initialDraft = ""
    @EnvironmentObject private var gym: GymStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TrainerMessage.createdAt) private var messages: [TrainerMessage]
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var plans: [DailyPlan]
    @State private var input = ""
    @State private var busy = false
    @State private var error: String?
    @State private var failedDraft = ""
    @State private var initialized = false
    @State private var showAvatar = false
    @StateObject private var speech = SpeechRecognizer()
    private var active: Workout? { workouts.first { !$0.isPublished } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Button { showAvatar = true } label: {
                    HStack {
                        CoachFace(spec: profile.coachAvatar, size: 30)
                        Label("Private AI trainer · \(profile.coachName)", systemImage: "sparkles")
                    }.font(.caption).foregroundStyle(.teal).padding(8)
                }.buttonStyle(.plain).accessibilityLabel("Edit trainer appearance")
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty {
                                Text("What are we training?").font(.title2.bold())
                                ForEach(["Plan my workout today", "Create a week of training", "Add bench press to my todos"], id: \.self) { text in Button(text) { input = text }.buttonStyle(.bordered) }
                            }
                            ForEach(messages.suffix(100)) { message in
                                HStack {
                                    if message.role == "user" { Spacer(minLength: 30) }
                                    Text(message.text).accessibilityIdentifier(message.role == "assistant" && message.id == messages.last(where: { $0.role == "assistant" })?.id ? "trainerLatestReply" : "trainerMessage.\(message.role)").padding(12).background(message.role == "user" ? Color.teal.opacity(0.14) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                                    if message.role == "assistant" { Spacer(minLength: 30) }
                                }.id(message.id)
                            }
                            if busy { ProgressView("Thinking…") }
                        }.padding()
                    }
                    .onChange(of: messages.count) { _, _ in if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                    .onAppear { if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                if let error {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        if !failedDraft.isEmpty { Button("Retry") { input = failedDraft; send() }.disabled(busy) }
                    }.padding(8)
                }
                HStack {
                    Button { speech.isRecording ? speech.stop() : speech.start() } label: {
                        Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                    }.accessibilityLabel(speech.isRecording ? "Stop dictation" : "Dictate message").disabled(busy)
                    TextField("Message your trainer", text: $input, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...5).accessibilityIdentifier("trainerInput")
                    Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("trainerSend")
                }.padding()
                if let error = speech.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            .navigationTitle("AI trainer").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showAvatar) { CoachAvatarView(profile: profile) }
            .onAppear { if !initialized { input = initialDraft; initialized = true } }
            .onChange(of: speech.transcript) { _, value in if !value.isEmpty { input = value } }
            .onDisappear { speech.stop() }
        }
    }
    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 3000 else { return }
        speech.stop()
        let retrying = messages.last?.role == "user" && messages.last?.text == text
        let history = messages.dropLast(retrying ? 1 : 0).suffix(14).map { ["role": $0.role, "text": String($0.text.prefix(3000))] } + [["role": "user", "text": text]]
        let workout = active, revision = TrainerPlanEditor.revision(active), today = Date()
        if !retrying { context.insert(TrainerMessage(role: "user", text: text)); try? context.save() }
        input = ""; busy = true; error = nil; failedDraft = ""
        Task {
            defer { busy = false }
            do {
                let api = try await gym.trainerAPI()
                let current: [String: Any]? = workout.map { w in
                    ["activity": w.activity.name, "allowsTodoEditing": w.activity == .strength, "remaining": TrainerPlanEditor.remainingTodos(w).map { ["exerciseKey": $0.exerciseKey, "sets": $0.sets, "repsLow": $0.repsLow, "repsHigh": $0.repsHigh, "restSeconds": $0.restSeconds] },
                     "completed": w.sortedExercises.map { e in ["exerciseKey": e.exerciseKey, "sets": e.sets.filter(\.isCompleted).count] }]
                }
                let schedule = plans.filter { $0.dayKey >= today.dayKey && ($0.requestedByUser || $0.sourceRaw == "ai") }.prefix(28).map { p in
                    ["date": p.dayKey, "title": p.title, "items": p.items.map { ["exerciseKey": $0.exerciseKey, "sets": $0.sets, "repsLow": $0.repsLow, "repsHigh": $0.repsHigh, "restSeconds": $0.restSeconds] }] as [String: Any]
                }
                let reply: TrainerReply = try await api.post("trainer", body: ["messages": history, "localDate": today.dayKey,
                    "catalog": exercises.map { ["key": $0.key, "name": $0.nameEn, "cardio": $0.isCardio] }, "activeWorkout": current as Any? ?? NSNull(),
                    "schedule": schedule, "goals": profile.planGoal.name])
                let result = try TrainerPlanEditor.apply(reply, workout: workout, expectedRevision: revision, exercises: exercises, plans: plans, context: context, today: today)
                context.insert(TrainerMessage(role: "assistant", text: reply.reply + (result.isEmpty ? "" : "\n\n" + result)))
                try context.save()
            } catch { self.error = error.localizedDescription; self.failedDraft = text }
        }
    }
}
