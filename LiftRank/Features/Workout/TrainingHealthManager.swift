import SwiftUI
import SwiftData
import HealthKit
import WatchConnectivity

/// One HealthKit owner per local workout: Watch if installed, otherwise iPhone.
@MainActor
final class TrainingHealthManager: NSObject, ObservableObject {
    static let shared = TrainingHealthManager()
    @Published private(set) var heartRate: Double?
    @Published private(set) var calories: Double?
    @Published private(set) var heartRateReading: WorkoutHeartRate?
    private var currentID: UUID?
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKWorkoutBuilder?
    private var current: Workout? {
        didSet {
            if currentID != current?.id { heartRate = nil; calories = nil; heartRateReading = nil }
            currentID = current?.id
        }
    }
    private var context: ModelContext?
    private var startingID: UUID?
    private var finishingIDs: Set<UUID> = []
    private var watchTimeout: Task<Void, Never>?

    override private init() {
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
        healthStore.workoutSessionMirroringStartHandler = { [weak self] mirrored in
            Task { @MainActor in
                guard let self else { return }
                self.session = mirrored; mirrored.delegate = self
                if self.context == nil, let context = try? StoreLoader.shared.requireContext() { self.bind(context: context) }
                if let workout = self.current, workout.healthOwner == "watch" { self.sendWatch(self.message("status", workout)) }
            }
        }
    }

    func bind(context: ModelContext) {
        self.context = context
        if current == nil {
            let records = (try? context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\Workout.startedAt, order: .reverse)]))) ?? []
            current = records.first { $0.healthOwner == "watch" && $0.healthState != "saved" && $0.healthState != "off" }
                ?? records.first { !$0.isPublished }
        }
    }
    nonisolated static func syncIdentifier(_ id: UUID) -> String { "liftrank.training.\(id.uuidString)" }

    func start(_ workout: Workout, context: ModelContext?) async {
        guard !workout.isDeleted, !workout.isPublished, workout.endedAt == nil, workout.startOptionsChosen else { return }
        if let context { self.context = context }
        CardioLiveActivityManager.shared.refresh()
        let requestedID = workout.id
        if startingID == requestedID { return }
        for _ in 0..<100 where startingID != nil { try? await Task.sleep(for: .milliseconds(100)) }
        guard startingID == nil else { fail(workout, L("Apple tracking is still switching activities. Retry shortly.")); return }
        for _ in 0..<100 where !finishingIDs.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        guard finishingIDs.isEmpty else { fail(workout, L("The previous Apple workout is still saving. Retry shortly.")); return }
        guard !workout.isDeleted, workout.id == requestedID, !workout.isPublished, workout.endedAt == nil else { return }
        if let previous = current, previous.id != workout.id, previous.healthOwner == "watch", previous.healthState != "saved" {
            sendWatch(message("finish", previous))
            fail(workout, L("Finish saving the previous workout on your Watch, then retry Apple Health."))
            return
        }
        if current?.id == workout.id, workout.healthOwner != "watch", builder != nil { return }
        if workout.healthState == "saved" { return }
        current = workout
        #if DEBUG
        if ProcessInfo.processInfo.environment["LIFTRANK_SKIP_HEALTH"] == "1" { workout.healthState = "off"; return }
        #endif
        guard UserDefaults.standard.object(forKey: "training.appleHealthEnabled") as? Bool != false else {
            workout.healthState = "off"; save(); return
        }
        guard HKHealthStore.isHealthDataAvailable() else { fail(workout, L("Apple Health is unavailable on this device.")); return }
        startingID = workout.id
        defer { startingID = nil }
        do {
            let type = HKObjectType.workoutType()
            if healthStore.authorizationStatus(for: type) == .notDetermined {
                try await HealthKitManager.shared.requestAuthorization()
            }
            guard currentID == requestedID, !workout.isDeleted, workout.id == requestedID, !workout.isPublished, workout.endedAt == nil else { return }
            guard healthStore.authorizationStatus(for: type) == .sharingAuthorized else {
                fail(workout, L("Allow LiftRank to write workouts in Settings → Health → Data Access & Devices."))
                return
            }
            if workout.healthOwner == "watch" {
                sendWatch(message("status", workout))
                if workout.healthState == "startingWatch" { try await healthStore.startWatchApp(toHandle: workout.healthConfiguration) }
                scheduleWatchTimeout(workout)
                return // Never create a second phone recording while the Watch owns this session.
            }
            if WCSession.isSupported() {
                for _ in 0..<10 where WCSession.default.activationState != .activated {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard currentID == requestedID, !workout.isDeleted, workout.id == requestedID, !workout.isPublished, workout.endedAt == nil else { return }
                if WCSession.default.isPaired && WCSession.default.isWatchAppInstalled {
                    workout.healthOwner = "watch"; workout.healthState = "startingWatch"; workout.healthError = ""; save()
                    sendWatch(message("start", workout))
                    do {
                        try await healthStore.startWatchApp(toHandle: workout.healthConfiguration)
                        guard currentID == requestedID, !workout.isDeleted, workout.id == requestedID, !workout.isPublished, workout.endedAt == nil else { return }
                        // The Watch acknowledges actual recording separately from app launch.
                        scheduleWatchTimeout(workout)
                        return
                    } catch {
                        guard currentID == requestedID, !workout.isDeleted, workout.id == requestedID, !workout.isPublished, workout.endedAt == nil else { return }
                        sendWatch(message("cancel", workout))
                        workout.healthOwner = "phone"
                        workout.healthError = L("Watch unavailable. Recording on iPhone.")
                    }
                }
            }
            try await startPhone(workout)
        } catch { if currentID == requestedID { fail(workout, error.localizedDescription) } }
    }

    private func startPhone(_ workout: Workout) async throws {
        guard !workout.isDeleted, !workout.isPublished, current?.id == workout.id else { return }
        let requestedID = workout.id
        workout.healthOwner = "phone"
        try await beginPhoneCollection(workout)
        guard currentID == requestedID, !workout.isDeleted else { return }
        if workout.cardioIsPaused { session?.pause() }
        workout.healthState = "recordingPhone"; save()
    }

    private func beginPhoneCollection(_ workout: Workout) async throws {
        let requestedID = workout.id
        // Xcode 16's SDK marks live builders unavailable on iOS; runtime availability alone is insufficient.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if workout.healthState == "recordingPhone", let recovered = try? await healthStore.recoverActiveWorkoutSession() {
                session = recovered; recovered.delegate = self
                let live = recovered.associatedWorkoutBuilder()
                live.delegate = self; live.shouldCollectWorkoutEvents = workout.cardioTimerStartedAt == nil; builder = live
                return
            }
            let liveSession = try HKWorkoutSession(healthStore: healthStore, configuration: workout.healthConfiguration)
            let live = liveSession.associatedWorkoutBuilder()
            liveSession.delegate = self; live.delegate = self
            live.shouldCollectWorkoutEvents = workout.cardioTimerStartedAt == nil
            live.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: workout.healthConfiguration)
            session = liveSession; builder = live
            try await live.addMetadata(metadata(workout))
            liveSession.startActivity(with: workout.startedAt)
            do { try await live.beginCollection(at: workout.startedAt) }
            catch { liveSession.end(); live.discardWorkout(); session = nil; builder = nil; throw error }
            return
        }
        #endif
        let recorder = HKWorkoutBuilder(healthStore: healthStore, configuration: workout.healthConfiguration, device: .local())
        try await recorder.addMetadata(metadata(workout))
        try await recorder.beginCollection(at: workout.startedAt)
        guard currentID == requestedID else { recorder.discardWorkout(); return }
        builder = recorder
    }

    func finish(_ workout: Workout, context: ModelContext?) async {
        if let context { self.context = context }
        guard workout.healthState != "saved", workout.healthState != "off", !finishingIDs.contains(workout.id) else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["LIFTRANK_SKIP_HEALTH"] == "1" { workout.healthState = "off"; return }
        #endif
        // The Watch owns its Health permissions. Always deliver Finish to an existing
        // Watch recording, even if phone permissions/preferences changed mid-workout.
        if workout.healthOwner == "watch" {
            workout.healthState = "savingWatch"; save()
            sendWatch(message("finish", workout))
            scheduleWatchTimeout(workout)
            return
        }
        guard UserDefaults.standard.object(forKey: "training.appleHealthEnabled") as? Bool != false || workout.healthState.hasPrefix("recording") else { return }
        guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            fail(workout, L("Workout saved locally. Apple Health permission is needed to sync.")); return
        }
        finishingIDs.insert(workout.id)
        defer { finishingIDs.remove(workout.id) }
        do {
            let end = workout.endedAt ?? Date()
            let ownsBuilder = current?.id == workout.id && builder != nil
            let recorder: HKWorkoutBuilder
            if ownsBuilder, let builder {
                recorder = builder
                if let session {
                    session.stopActivity(with: end)
                    for _ in 0..<50 where session.state != .stopped && session.state != .ended {
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    guard session.state == .stopped || session.state == .ended else { throw GymFailure.message(L("Apple workout is still stopping. Retry sync.")) }
                }
            } else {
                recorder = HKWorkoutBuilder(healthStore: healthStore, configuration: workout.healthConfiguration, device: .local())
                try await recorder.addMetadata(metadata(workout))
                try await recorder.beginCollection(at: workout.startedAt)
            }
            workout.healthState = "saving"; save()
            // Phone-only recording can include explicitly entered distance; do not invent sensor data.
            if !ownsBuilder || !isLivePhone {
                try await addDistance(workout, to: recorder, end: end)

            }
            if workout.cardioTimerStartedAt != nil {
                let events = CardioClock.healthEvents(workout.cardioPauses)
                if !events.isEmpty { try await recorder.addWorkoutEvents(events) }
            }
            try await recorder.endCollection(at: end)
            let saved = try await recorder.finishWorkout()
            workout.healthWorkoutID = saved?.uuid.uuidString ?? Self.syncIdentifier(workout.id)
            workout.healthState = "saved"; workout.healthError = ""; save()
            if ownsBuilder, current?.id == workout.id { session?.end(); session = nil; builder = nil }
        } catch {
            if current?.id == workout.id { session?.end(); session = nil; builder = nil }
            fail(workout, L("Workout saved locally. Health sync failed: %@", error.localizedDescription))
        }
    }

    private var isLivePhone: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return builder is HKLiveWorkoutBuilder }
        #endif
        return false
    }
    private func metadata(_ workout: Workout) -> [String: Any] {
        [HKMetadataKeySyncIdentifier: Self.syncIdentifier(workout.id), HKMetadataKeySyncVersion: 1,
         "LiftRankWorkoutID": workout.id.uuidString]
    }
    private func addDistance(_ workout: Workout, to recorder: HKWorkoutBuilder, end: Date) async throws {
        let identifier: HKQuantityTypeIdentifier
        switch workout.activity {
        case .running, .walking: identifier = .distanceWalkingRunning
        case .cycling: identifier = .distanceCycling
        case .swimming: identifier = .distanceSwimming
        default: return
        }
        let km = workout.isOutdoor && workout.cardioTimerStartedAt != nil ? workout.routeDistanceMeters / 1000 : workout.exercises.filter { $0.isCardio && $0.exerciseKey == workout.activity.rawValue }
            .flatMap(\.sets).filter(\.isCompleted).reduce(0) { $0 + $1.weightKg }
        if km > 0 {
            try await recorder.addSamples([HKQuantitySample(type: HKQuantityType(identifier), quantity: HKQuantity(unit: .meter(), doubleValue: km * 1000), start: workout.startedAt, end: end)])
        }
    }

    func updateCardioPause(_ workout: Workout) async {
        guard !workout.isPublished, workout.endedAt == nil, workout.cardioTimerStartedAt != nil else { return }
        if workout.healthOwner == "watch" {
            sendWatch(message(workout.cardioIsPaused ? "pause" : "resume", workout))
        } else if current?.id == workout.id, let session {
            if workout.cardioIsPaused && session.state == .running { session.pause() }
            else if !workout.cardioIsPaused && session.state == .paused { session.resume() }
        }
        // iOS 17–25 phone builders receive the persisted events when the workout is saved.
    }

    func discard(_ workout: Workout) {
        discard(workoutID: workout.id, healthOwner: workout.healthOwner)
    }
    func discard(workoutID: UUID, healthOwner: String) {
        if healthOwner == "watch" { sendWatch(WorkoutBridgeMessage(action: "cancel", workoutID: workoutID.uuidString)) }
        guard currentID == workoutID else { return }
        watchTimeout?.cancel()
        session?.end(); builder?.discardWorkout(); session = nil; builder = nil; current = nil
        heartRate = nil; calories = nil
    }
    private func message(_ action: String, _ workout: Workout) -> WorkoutBridgeMessage {
        WorkoutBridgeMessage(action: action, workoutID: workout.id.uuidString, activity: workout.activityRaw,
                             startedAt: workout.startedAt, endedAt: workout.endedAt, outdoor: workout.isOutdoor, cardioPauses: workout.cardioPauses, controlVersion: WorkoutBridgeRules.version(workout.cardioPauses))
    }
    private func sendWatch(_ message: WorkoutBridgeMessage) {
        guard WCSession.isSupported(), let data = message.data else { return }
        if let session, current?.healthOwner == "watch", currentID?.uuidString == message.workoutID {
            Task { try? await session.sendToRemoteWorkoutSession(data: data) }
        }
        let link = WCSession.default
        guard link.activationState == .activated else { return }
        if link.isReachable {
            link.sendMessageData(data, replyHandler: nil, errorHandler: { _ in link.transferUserInfo(["workout": data]) })
        } else { link.transferUserInfo(["workout": data]) }
        // The latest desired state wins if the Watch starts after an earlier request times out.
        try? link.updateApplicationContext(["workout": data])
    }
    private func handle(_ message: WorkoutBridgeMessage) {
        if context == nil, let context = try? StoreLoader.shared.requireContext() { bind(context: context) }
        // A temporarily locked/unavailable store is not evidence that a workout was discarded.
        guard let id = message.workoutID, let context,
              let records = try? context.fetch(FetchDescriptor<Workout>()) else { return }
        guard let workout = records.first(where: { $0.id.uuidString == id }) else {
            if message.action == "recording", let id = message.workoutID { sendWatch(WorkoutBridgeMessage(action: "cancel", workoutID: id)) }
            return
        }
        guard workout.healthOwner == "watch" else {
            if message.action == "recording" { sendWatch(self.message("cancel", workout)) }
            return
        }
        if ["pauseRequest", "resumeRequest"].contains(message.action) {
            do { _ = try WorkoutWatchSync.applyPauseRequest(message, workout: workout, context: context) }
            catch { workout.healthError = error.localizedDescription }
            var state = self.message(workout.isPublished || workout.endedAt != nil ? "finish" : "state", workout)
            state.requestID = message.requestID
            sendWatch(state); save(); return
        }
        if message.action == "recording" {
            guard workout.healthState != "saved" else { return }
            watchTimeout?.cancel()
            let stopped = workout.isPublished || workout.endedAt != nil
            workout.healthState = stopped ? "savingWatch" : "recordingWatch"
            workout.healthError = ""
            if stopped { sendWatch(self.message("finish", workout)) }
        } else if ["stopped", "saved"].contains(message.action) {
            watchTimeout?.cancel()
            do { try WorkoutWatchSync.applyCompletion(message, workout: workout, context: context) }
            catch { workout.healthError = error.localizedDescription }
            if workout.healthState == "saved", currentID == workout.id { session = nil }
        } else if message.action == "error", workout.healthState != "saved" { fail(workout, message.error ?? "The Watch could not record this workout.") }
        if currentID == workout.id, !workout.isPublished, workout.endedAt == nil, workout.healthOwner == "watch" {
            if let bpm = message.heartRate, let measuredAt = message.metricsAt,
               measuredAt >= (heartRateReading?.measuredAt ?? .distantPast) {
                heartRateReading = WorkoutHeartRate(workoutID: workout.id, beatsPerMinute: bpm, measuredAt: measuredAt)
                heartRate = heartRateReading?.value(for: workout.id)
            }
            calories = message.calories ?? calories
        }
        if message.action == "metrics" { CardioLiveActivityManager.shared.refreshMetrics() }
        else { save() }
    }
    private func scheduleWatchTimeout(_ workout: Workout) {
        watchTimeout?.cancel()
        watchTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard ["startingWatch", "savingWatch", "error"].contains(workout.healthState), workout.healthOwner == "watch" else { return }
            workout.healthError = L("Open LiftRank on your Watch and check its Health permissions, then retry. Your local workout continues.")
            self?.save()
        }
    }
    private func fail(_ workout: Workout, _ message: String) { workout.healthState = "error"; workout.healthError = message; save() }
    private func save() { try? context?.save(); CardioLiveActivityManager.shared.refresh() }
}

extension TrainingHealthManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            if let workout = self.current, workout.healthOwner == "watch" {
                self.sendWatch(self.message(workout.isPublished || workout.endedAt != nil ? "finish" : "status", workout))
            }
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let message = try? JSONDecoder().decode(WorkoutBridgeMessage.self, from: messageData) else { return }
        Task { @MainActor in self.handle(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let data = userInfo["workout"] as? Data { self.session(session, didReceiveMessageData: data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if self.context == nil, let context = try? StoreLoader.shared.requireContext() { self.bind(context: context) }
            if let workout = self.current {
                let action = workout.healthOwner != "watch" || workout.isDeleted ? "cancel" : (workout.isPublished || workout.endedAt != nil) ? "finish" : "start"
                replyHandler(["workout": self.message(action, workout).data ?? Data()])
            } else { replyHandler([:]) }
        }
    }
}
extension TrainingHealthManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in if self.session === workoutSession, let workout = self.current { self.fail(workout, error.localizedDescription) } }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for item in data {
            if let message = try? JSONDecoder().decode(WorkoutBridgeMessage.self, from: item) { Task { @MainActor in self.handle(message) } }
        }
    }
}
#if compiler(>=6.2)
@available(iOS 26.0, *)
extension TrainingHealthManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let energy = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        Task { @MainActor in
            guard self.builder === workoutBuilder, let id = self.currentID else { return }
            self.heartRate = hr; self.calories = energy
            if collectedTypes.contains(HKQuantityType(.heartRate)) {
                self.heartRateReading = hr.map { WorkoutHeartRate(workoutID: id, beatsPerMinute: $0, measuredAt: Date()) }
                CardioLiveActivityManager.shared.refreshMetrics()
            }
        }
    }
}
#endif

struct TrainingHealthStatusView: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var context
    @ObservedObject private var health = TrainingHealthManager.shared
    private var label: String {
        switch workout.healthState {
        case "startingWatch": L("Starting Apple Watch…")
        case "recordingWatch": L("Apple Watch · recording")
        case "recordingPhone": L("iPhone · Apple Health recording")
        case "savingWatch": L("Waiting for Watch to save")
        case "saving": L("Saving to Apple Health…")
        case "saved": L("Saved to Apple Health")
        case "off": L("Apple Health sync off")
        case "error": L("Apple Health needs attention")
        default: L("Apple Health starts after workout setup")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(workout.cardioIsPaused && workout.healthState.hasPrefix("recording") ? label + " · paused" : label, systemImage: workout.healthState.contains("Watch") ? "applewatch" : "heart.fill").font(.caption).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 5)) { timeline in
                if let hr = health.heartRateReading?.value(for: workout.id, now: timeline.date), workout.healthState.hasPrefix("recording"), !workout.isPublished, workout.endedAt == nil {
                    Text("\(Int(hr)) bpm").font(.caption.monospacedDigit())
                }
            }
            if !workout.healthError.isEmpty { Text(workout.healthError).font(.caption).foregroundStyle(.orange) }
            if ["error", "savingWatch", "startingWatch"].contains(workout.healthState) {
                Button("Retry Apple Health") {
                    Task {
                        if workout.isPublished || workout.endedAt != nil { await health.finish(workout, context: context) }
                        else { await health.start(workout, context: context) }
                    }
                }.font(.caption)
            }
        }
    }
}

struct WorkoutHeartRateIndicator: View {
    let workout: Workout?
    @ObservedObject private var health = TrainingHealthManager.shared
    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            if let workout, workout.healthOwner == "watch", workout.healthState == "recordingWatch", !workout.isPublished, workout.endedAt == nil,
               let value = health.heartRateReading?.value(for: workout.id, now: timeline.date) {
                Label("\(Int(value)) bpm", systemImage: "heart.fill").foregroundStyle(.red)
            } else {
                Label("Heart rate unavailable", systemImage: "heart")
            }
        }.accessibilityIdentifier("gymHeartRate")
    }
}
