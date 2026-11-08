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
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKWorkoutBuilder?
    private var current: Workout?
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
        guard !workout.isPublished, workout.endedAt == nil, workout.startOptionsChosen else { return }
        if let context { self.context = context }
        let requestedID = workout.id
        if startingID == requestedID { return }
        for _ in 0..<100 where startingID != nil { try? await Task.sleep(for: .milliseconds(100)) }
        guard startingID == nil else { fail(workout, L("Apple tracking is still switching activities. Retry shortly.")); return }
        for _ in 0..<100 where !finishingIDs.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        guard finishingIDs.isEmpty else { fail(workout, L("The previous Apple workout is still saving. Retry shortly.")); return }
        guard workout.id == requestedID, !workout.isPublished, workout.endedAt == nil else { return }
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
            guard workout.id == requestedID, current?.id == requestedID, !workout.isPublished, workout.endedAt == nil else { return }
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
                guard workout.id == requestedID, current?.id == requestedID, !workout.isPublished, workout.endedAt == nil else { return }
                if WCSession.default.isPaired && WCSession.default.isWatchAppInstalled {
                    workout.healthOwner = "watch"; workout.healthState = "startingWatch"; workout.healthError = ""; save()
                    sendWatch(message("start", workout))
                    do {
                        try await healthStore.startWatchApp(toHandle: workout.healthConfiguration)
                        guard workout.id == requestedID, current?.id == requestedID, !workout.isPublished, workout.endedAt == nil else { return }
                        // The Watch acknowledges actual recording separately from app launch.
                        scheduleWatchTimeout(workout)
                        return
                    } catch {
                        guard workout.id == requestedID, current?.id == requestedID, !workout.isPublished, workout.endedAt == nil else { return }
                        sendWatch(message("cancel", workout))
                        workout.healthOwner = "phone"
                        workout.healthError = L("Watch unavailable. Recording on iPhone.")
                    }
                }
            }
            try await startPhone(workout)
        } catch { fail(workout, error.localizedDescription) }
    }

    private func startPhone(_ workout: Workout) async throws {
        guard !workout.isDeleted, !workout.isPublished, current?.id == workout.id else { return }
        workout.healthOwner = "phone"
        try await beginPhoneCollection(workout)
        if workout.cardioIsPaused { session?.pause() }
        workout.healthState = "recordingPhone"; save()
    }

    private func beginPhoneCollection(_ workout: Workout) async throws {
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
        builder = recorder
    }

    func finish(_ workout: Workout, context: ModelContext?) async {
        if let context { self.context = context }
        guard workout.healthState != "saved", workout.healthState != "off", !finishingIDs.contains(workout.id) else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["LIFTRANK_SKIP_HEALTH"] == "1" { workout.healthState = "off"; return }
        #endif
        guard UserDefaults.standard.object(forKey: "training.appleHealthEnabled") as? Bool != false || workout.healthState.hasPrefix("recording") else { return }
        guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            fail(workout, L("Workout saved locally. Apple Health permission is needed to sync.")); return
        }
        if workout.healthOwner == "watch" {
            workout.healthState = "savingWatch"; save()
            sendWatch(message("finish", workout))
            scheduleWatchTimeout(workout)
            return
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
        if workout.healthOwner == "watch" { sendWatch(message("cancel", workout)) }
        watchTimeout?.cancel()
        guard current?.id == workout.id else { return }
        session?.end(); builder?.discardWorkout(); session = nil; builder = nil; current = nil
    }
    private func message(_ action: String, _ workout: Workout) -> WorkoutBridgeMessage {
        WorkoutBridgeMessage(action: action, workoutID: workout.id.uuidString, activity: workout.activityRaw,
                             startedAt: workout.startedAt, endedAt: workout.endedAt, outdoor: workout.isOutdoor, cardioPauses: workout.cardioPauses, controlVersion: workout.cardioPauses.count * 2 - (workout.cardioIsPaused ? 1 : 0))
    }
    private func sendWatch(_ message: WorkoutBridgeMessage) {
        guard WCSession.isSupported(), let data = message.data else { return }
        let link = WCSession.default
        guard link.activationState == .activated else { return }
        if link.isReachable {
            link.sendMessageData(data, replyHandler: nil, errorHandler: { _ in link.transferUserInfo(["workout": data]) })
        } else { link.transferUserInfo(["workout": data]) }
        // The latest desired state wins if the Watch starts after an earlier request times out.
        try? link.updateApplicationContext(["workout": data])
    }
    private func handle(_ message: WorkoutBridgeMessage) {
        guard let id = message.workoutID, let context,
              let workout = try? context.fetch(FetchDescriptor<Workout>()).first(where: { $0.id.uuidString == id }) else { return }
        if message.action == "recording" {
            guard workout.healthOwner == "watch" else { sendWatch(self.message("cancel", workout)); return }
            watchTimeout?.cancel()
            workout.healthState = workout.isPublished ? "savingWatch" : "recordingWatch"
            workout.healthError = ""
            if workout.isPublished { sendWatch(self.message("finish", workout)) }
        } else if message.action == "saved" {
            guard workout.healthOwner == "watch" else { return }
            watchTimeout?.cancel()
            workout.healthState = "saved"; workout.healthWorkoutID = message.healthID ?? Self.syncIdentifier(workout.id); workout.healthError = ""
            // Watch Finish stops the same local workout; it does not create another local record.
            if !workout.isPublished, let ended = message.endedAt {
                workout.endedAt = ended
                CardioLiveActivityManager.shared.refresh()
                if workout.hasPendingSet, workout.setEndedAt == nil { workout.setEndedAt = ended; workout.restUntil = nil }
            }
            if current?.id == workout.id { session = nil }
        } else if message.action == "error" { fail(workout, message.error ?? "The Watch could not record this workout.") }
        heartRate = message.heartRate ?? heartRate
        calories = message.calories ?? calories
        save()
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
    private func save() { try? context?.save() }
}

extension TrainingHealthManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
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
            if let workout = self.current {
                let action = workout.healthOwner != "watch" || workout.isDeleted ? "cancel" : workout.isPublished ? "finish" : "start"
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
        Task { @MainActor in self.heartRate = hr; self.calories = energy }
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
            if let hr = health.heartRate, workout.healthState.hasPrefix("recording") { Text("\(Int(hr)) bpm").font(.caption.monospacedDigit()) }
            if !workout.healthError.isEmpty { Text(workout.healthError).font(.caption).foregroundStyle(.orange) }
            if ["error", "savingWatch", "startingWatch"].contains(workout.healthState) {
                Button("Retry Apple Health") {
                    Task {
                        if workout.isPublished { await health.finish(workout, context: context) }
                        else { await health.start(workout, context: context) }
                    }
                }.font(.caption)
            }
        }
    }
}
