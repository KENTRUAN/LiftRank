import SwiftUI
import HealthKit
import WatchConnectivity
import WatchKit

@main
struct LiftRankWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchDelegate.self) var delegate
    var body: some Scene { WindowGroup { WatchWorkoutView() } }
}

final class WatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in await WatchWorkoutManager.shared.receiveStart(workoutConfiguration) }
    }
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in await WatchWorkoutManager.shared.recover() }
    }
}

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()
    @Published var status = "Start a workout in LiftRank on your iPhone."
    @Published var heartRate: Double = 0
    private var heartRateMeasuredAt: Date?
    @Published var calories: Double = 0
    @Published var active = false
    @Published var startedAt: Date?
    @Published var cardioPauses: [CardioPause] = []
    @Published private(set) var requestingControl = false
    @Published private(set) var stoppedAt: Date?
    var canPause: Bool { active && request?.activity != "strength" && stoppedAt == nil }
    var paused: Bool { cardioPauses.last.map { $0.endedAt == nil } ?? false }
    func freshHeartRate(at date: Date) -> Int? {
        guard let measured = heartRateMeasuredAt, date.timeIntervalSince(measured) <= 30,
              heartRate.isFinite, heartRate > 0, heartRate < 350 else { return nil }
        return Int(heartRate)
    }
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var request: WorkoutBridgeMessage?
    private var preparing = false
    private var finishing = false
    private var pendingControlID: String?
    private var outbox: [Data] { get { UserDefaults.standard.array(forKey: "workout.outbox") as? [Data] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "workout.outbox") } }

    private override init() {
        super.init()
        WCSession.default.delegate = self; WCSession.default.activate()
        if let data = UserDefaults.standard.data(forKey: "workout.request") {
            request = try? JSONDecoder().decode(WorkoutBridgeMessage.self, from: data)
            cardioPauses = request?.cardioPauses ?? []
        }
    }

    func receiveStart(_ configuration: HKWorkoutConfiguration) async {
        guard !preparing else { return }
        preparing = true; defer { preparing = false }
        await recover()
        if active { publish("recording"); return }
        status = "Connecting to iPhone…"
        for _ in 0..<20 where WCSession.default.activationState != .activated { try? await Task.sleep(for: .milliseconds(100)) }
        // Ask the phone for its latest desired state before honoring a delayed launch.
        if WCSession.default.isReachable {
            do {
                let response: [String: Any] = try await withCheckedThrowingContinuation { continuation in
                    WCSession.default.sendMessage(["requestSession": true], replyHandler: { continuation.resume(returning: $0) },
                                                  errorHandler: { continuation.resume(throwing: $0) })
                }
                if let data = response["workout"] as? Data { request = try JSONDecoder().decode(WorkoutBridgeMessage.self, from: data) }
                else { request = nil }
            } catch { status = "Reconnect to your iPhone and retry."; return }
        } else if let data = WCSession.default.receivedApplicationContext["workout"] as? Data {
            request = try? JSONDecoder().decode(WorkoutBridgeMessage.self, from: data)
        }
        guard let request, ["start", "state", "pause", "resume", "status"].contains(request.action), let id = request.workoutID,
              !discardedIDs.contains(id) else {
            status = "No pending workout. Start in LiftRank on iPhone."; return
        }
        if UserDefaults.standard.string(forKey: "workout.finishedID") == id { publishFinished(); return }
        do {
            let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming)]
            let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
            try await store.requestAuthorization(toShare: share, read: read)
            guard self.request?.workoutID == id, !discardedIDs.contains(id), self.request?.action != "cancel", self.request?.action != "finish" else { return }
            guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { throw NSError(domain: "LiftRank", code: 1, userInfo: [NSLocalizedDescriptionKey: "Allow workout access in Health settings."]) }
            let config = TrainingActivity(rawValue: request.activity ?? "")?.configuration(outdoor: request.outdoor ?? false) ?? configuration
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            session.delegate = self; builder.delegate = self
            builder.shouldCollectWorkoutEvents = request.activity == "strength"
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            self.session = session; self.builder = builder
            heartRate = 0; calories = 0; heartRateMeasuredAt = nil; stoppedAt = nil
            let start = request.startedAt ?? Date(); startedAt = start
            try await builder.addMetadata([HKMetadataKeySyncIdentifier: "liftrank.training.\(id)", HKMetadataKeySyncVersion: 1, "LiftRankWorkoutID": id])
            UserDefaults.standard.set(request.data, forKey: "workout.request")
            // A temporary mirroring outage must not discard the only Health recording.
            try? await session.startMirroringToCompanionDevice()
            guard self.request?.workoutID == id, !discardedIDs.contains(id), self.request?.action != "cancel" else { session.end(); builder.discardWorkout(); return }
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            cardioPauses = self.request?.cardioPauses ?? []
            UserDefaults.standard.set(self.request?.data, forKey: "workout.request")
            if paused { session.pause() }
            active = true; status = TrainingActivity(rawValue: request.activity ?? "")?.name ?? "Workout"
            publish("recording")
            if self.request?.action == "finish" { await finish(at: self.request?.endedAt ?? Date()) }
        } catch {
            session?.end(); builder?.discardWorkout(); session = nil; builder = nil
            status = error.localizedDescription; publish("error", error: status)
        }
    }

    func recover() async {
        guard session == nil else { return }
        do {
            guard let recovered = try await store.recoverActiveWorkoutSession() else { return }
            session = recovered; recovered.delegate = self
            builder = recovered.associatedWorkoutBuilder(); builder?.delegate = self
            builder?.shouldCollectWorkoutEvents = request?.activity == "strength"
            startedAt = recovered.startDate
            stoppedAt = request?.endedAt
            active = recovered.state == .running || recovered.state == .paused
            status = active ? "Workout recovered" : "Finishing workout…"
            try? await recovered.startMirroringToCompanionDevice()
            if let stoppedAt { await finish(at: stoppedAt) }
            else if active { publish("recording") }
        } catch { status = "Recovery unavailable. Open LiftRank on iPhone." }
    }

    func finish(at end: Date = Date()) async {
        guard !finishing else { return }
        finishing = true; defer { finishing = false }
        await recover()
        guard let session, let builder else {
            if let id = request?.workoutID, UserDefaults.standard.string(forKey: "workout.finishedID") == id { publishFinished() }
            else { publish("error", error: "No active Watch workout. Retry sync on iPhone.") }
            return
        }
        do {
            let end = stoppedAt ?? end
            stoppedAt = end; request?.endedAt = end
            cardioPauses = WorkoutBridgeRules.pauses(cardioPauses, endingAt: end)
            request?.cardioPauses = cardioPauses
            UserDefaults.standard.set(request?.data, forKey: "workout.request")
            publish("stopped")
            status = "Saving…"
            if session.state == .running || session.state == .paused || session.state == .prepared { session.stopActivity(with: end) }
            for _ in 0..<50 where session.state != .stopped && session.state != .ended { try await Task.sleep(for: .milliseconds(100)) }
            guard session.state == .stopped || session.state == .ended else { throw NSError(domain: "LiftRank", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not stop the Watch workout. Retry."]) }
            let events = CardioClock.healthEvents(cardioPauses)
            if !events.isEmpty { try await builder.addWorkoutEvents(events) }
            try await builder.endCollection(at: end)
            let result = try await builder.finishWorkout()
            request?.endedAt = end
            request?.healthID = result?.uuid.uuidString
            UserDefaults.standard.set(request?.workoutID, forKey: "workout.finishedID")
            UserDefaults.standard.set(request?.data, forKey: "workout.request")
            UserDefaults.standard.set(requestMessage("saved")?.data, forKey: "workout.finishedMessage")
            await transmit(requestMessage("saved"), durable: true)
            session.end(); self.session = nil; self.builder = nil; active = false; status = "Saved to Apple Health"
        } catch { status = error.localizedDescription; publish("error", error: status) }
    }
    private func rememberDiscard(_ id: String) {
        var ids = UserDefaults.standard.stringArray(forKey: "workout.discardedIDs") ?? []
        ids.removeAll { $0 == id }; ids.append(id)
        UserDefaults.standard.set(Array(ids.suffix(64)), forKey: "workout.discardedIDs")
    }
    private func cancel() {
        session?.end(); builder?.discardWorkout(); session = nil; builder = nil
        active = false; requestingControl = false; pendingControlID = nil; stoppedAt = nil
        status = "Workout discarded"; UserDefaults.standard.removeObject(forKey: "workout.request")
    }
    private var discardedIDs: Set<String> { Set(UserDefaults.standard.stringArray(forKey: "workout.discardedIDs") ?? []) }

    func pauseOrResume() {
        guard canPause, !requestingControl, var message = request else { return }
        message.action = paused ? "resumeRequest" : "pauseRequest"
        message.requestID = UUID().uuidString
        pendingControlID = message.requestID; requestingControl = true
        Task {
            await transmit(message, durable: true)
            try? await Task.sleep(for: .seconds(15))
            if pendingControlID == message.requestID {
                requestingControl = false
                status = "Open LiftRank on iPhone to sync controls."
            }
        }
    }
    private func handle(_ message: WorkoutBridgeMessage) async {
        if message.action == "cancel", let id = message.workoutID {
            // Cancellation can beat the delayed start message or HealthKit launch.
            rememberDiscard(id)
            if request?.workoutID == id { await recover(); cancel(); request = nil }
            return
        }
        if message.action == "start" {
            guard let id = message.workoutID, !discardedIDs.contains(id) else { return }
            if UserDefaults.standard.string(forKey: "workout.finishedID") == id {
                publishFinished()
                return
            }
            if active {
                if request?.workoutID == message.workoutID { await applySnapshot(message); publish("recording") }
                return
            }
            request = message
            UserDefaults.standard.set(message.data, forKey: "workout.request")
            // HealthKit's launch delegate starts the session after the phone wakes the app.
        } else {
            guard request?.workoutID == message.workoutID else { return }
            if ["pause", "resume", "state", "status", "finish"].contains(message.action) { await applySnapshot(message) }
            if message.action == "finish" { request?.action = "finish"; request?.endedAt = message.endedAt; await finish(at: message.endedAt ?? Date()) }
            if message.action == "status" {
                await recover()
                if active { publish("recording") }
                else if UserDefaults.standard.string(forKey: "workout.finishedID") == message.workoutID { publishFinished() }
                else { publish("error", error: "The Watch session is unavailable. Your local workout is kept.") }
            }
        }
    }
    private func applySnapshot(_ message: WorkoutBridgeMessage) async {
        guard let current = request, WorkoutBridgeRules.acceptsSnapshot(message, current: current) else { return }
        if stoppedAt == nil {
            request?.cardioPauses = message.cardioPauses; request?.controlVersion = message.controlVersion
            cardioPauses = message.cardioPauses ?? []
        }
        if message.requestID == pendingControlID { requestingControl = false; pendingControlID = nil }
        UserDefaults.standard.set(request?.data, forKey: "workout.request")
        await recover()
        if paused && session?.state == .running { session?.pause() }
        else if !paused && session?.state == .paused && stoppedAt == nil { session?.resume() }
        if active, message.action != "finish" { status = TrainingActivity(rawValue: request?.activity ?? "")?.name ?? "Workout"; publish("recording") }
    }
    private func requestMessage(_ action: String, error: String? = nil) -> WorkoutBridgeMessage? {
        guard var message = request else { return nil }
        message.action = action; message.error = error; message.heartRate = heartRate; message.calories = calories
        message.metricsAt = heartRateMeasuredAt
        return message
    }
    private func publish(_ action: String, error: String? = nil) {
        let message = requestMessage(action, error: error)
        Task { await transmit(message, durable: action != "metrics") }
    }
    private func publishFinished() {
        guard let data = UserDefaults.standard.data(forKey: "workout.finishedMessage"),
              let message = try? JSONDecoder().decode(WorkoutBridgeMessage.self, from: data) else { return }
        Task { await transmit(message, durable: true) }
    }
    private func flushOutbox() {
        guard WCSession.default.activationState == .activated else { return }
        for data in outbox { WCSession.default.transferUserInfo(["workout": data]) }
        outbox = []
    }
    private func transmit(_ message: WorkoutBridgeMessage?, durable: Bool) async {
        guard let message, let data = message.data else { return }
        // Queue terminal events and controls even when mirroring succeeds. Delivery can
        // outlive either process; workout IDs and versions make repeated delivery safe.
        if durable { outbox.append(data); flushOutbox() }
        if let session {
            do { try await session.sendToRemoteWorkoutSession(data: data); return }
            catch { /* Reconnect through WatchConnectivity without duplicating the workout. */ }
        }
        guard WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessageData(data, replyHandler: nil, errorHandler: nil)
        }
    }
}

extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.flushOutbox() }
        if let data = session.receivedApplicationContext["workout"] as? Data { self.session(session, didReceiveMessageData: data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let message = try? JSONDecoder().decode(WorkoutBridgeMessage.self, from: messageData) else { return }
        Task { @MainActor in await self.handle(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let data = userInfo["workout"] as? Data { self.session(session, didReceiveMessageData: data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["workout"] as? Data { self.session(session, didReceiveMessageData: data) }
    }
}
extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.status = error.localizedDescription; self.publish("error", error: self.status); self.active = false }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for data in data { if let message = try? JSONDecoder().decode(WorkoutBridgeMessage.self, from: data) { Task { @MainActor in await self.handle(message) } } }
    }
}
extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heart = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        Task { @MainActor in
            guard self.builder === workoutBuilder else { return }
            self.heartRate = heart; self.calories = kcal
            if collectedTypes.contains(HKQuantityType(.heartRate)) { self.heartRateMeasuredAt = Date() }
            self.publish("metrics")
        }
    }
}

struct WatchWorkoutView: View {
    @StateObject private var manager = WatchWorkoutManager.shared
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("LIFTRANK").font(.caption.bold()).foregroundStyle(.mint)
                Text(manager.status).font(.headline).multilineTextAlignment(.center)
                if manager.active {
                    if let start = manager.startedAt {
                        if manager.paused || manager.stoppedAt != nil { Text(CardioClock.display(CardioClock.elapsed(start: start, pauses: manager.cardioPauses, at: manager.stoppedAt ?? Date()))).font(.title.monospacedDigit()) }
                        else { Text(Date().addingTimeInterval(-CardioClock.elapsed(start: start, pauses: manager.cardioPauses, at: Date())), style: .timer).font(.title.monospacedDigit()) }
                        if manager.paused { Text("Paused").foregroundStyle(.orange) }
                    }
                    TimelineView(.periodic(from: .now, by: 5)) { timeline in
                        if let bpm = manager.freshHeartRate(at: timeline.date) {
                            Label("\(bpm) bpm", systemImage: "heart.fill").foregroundStyle(.red)
                        } else { Label("Waiting for heart rate", systemImage: "heart").font(.caption) }
                    }
                    Text("\(Int(manager.calories)) kcal").foregroundStyle(.secondary)
                    if manager.canPause {
                        Button(manager.paused ? "Resume" : "Pause") { manager.pauseOrResume() }
                            .disabled(manager.requestingControl).accessibilityIdentifier("watchPauseResume")
                        if manager.requestingControl { Text("Waiting for iPhone…").font(.caption) }
                    }
                    Button("Finish workout", role: .destructive) { Task { await manager.finish() } }
                        .accessibilityIdentifier("watchFinishWorkout")
                }
            }.padding()
        }.task { await manager.recover() }
    }
}
