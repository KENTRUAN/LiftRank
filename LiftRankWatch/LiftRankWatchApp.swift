import SwiftUI
import HealthKit
import WatchConnectivity
import WatchKit

@main
struct LiftRankWatchApp: App {
    @WKExtensionDelegateAdaptor(WatchDelegate.self) var delegate
    var body: some Scene { WindowGroup { WatchWorkoutView() } }
}

final class WatchDelegate: NSObject, WKExtensionDelegate {
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
    @Published var calories: Double = 0
    @Published var active = false
    @Published var startedAt: Date?
    @Published var cardioPauses: [CardioPause] = []
    var paused: Bool { cardioPauses.last.map { $0.endedAt == nil } ?? false }
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var request: WorkoutBridgeMessage?
    private var preparing = false
    private var finishing = false

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
            } catch { status = "Reconnect to your iPhone and retry."; return }
        } else if let data = WCSession.default.receivedApplicationContext["workout"] as? Data {
            request = try? JSONDecoder().decode(WorkoutBridgeMessage.self, from: data)
        }
        guard let request, request.action == "start", let id = request.workoutID else {
            status = "No pending workout. Start in LiftRank on iPhone."; return
        }
        if UserDefaults.standard.string(forKey: "workout.finishedID") == id { publish("saved"); return }
        do {
            let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming)]
            let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
            try await store.requestAuthorization(toShare: share, read: read)
            guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { throw NSError(domain: "LiftRank", code: 1, userInfo: [NSLocalizedDescriptionKey: "Allow workout access in Health settings."]) }
            let config = TrainingActivity(rawValue: request.activity ?? "")?.configuration(outdoor: request.outdoor ?? false) ?? configuration
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            session.delegate = self; builder.delegate = self
            builder.shouldCollectWorkoutEvents = request.activity == "strength"
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            self.session = session; self.builder = builder
            let start = request.startedAt ?? Date(); startedAt = start
            try await builder.addMetadata([HKMetadataKeySyncIdentifier: "liftrank.training.\(id)", HKMetadataKeySyncVersion: 1, "LiftRankWorkoutID": id])
            UserDefaults.standard.set(request.data, forKey: "workout.request")
            try await session.startMirroringToCompanionDevice()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            cardioPauses = request.cardioPauses ?? []
            if paused { session.pause() }
            active = true; status = TrainingActivity(rawValue: request.activity ?? "")?.name ?? "Workout"
            publish("recording")
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
            active = recovered.state == .running || recovered.state == .paused
            status = active ? "Workout recovered" : "Finishing workout…"
            try? await recovered.startMirroringToCompanionDevice()
        } catch { status = "Recovery unavailable. Open LiftRank on iPhone." }
    }

    func finish(at end: Date = Date()) async {
        guard !finishing else { return }
        finishing = true; defer { finishing = false }
        await recover()
        guard let session, let builder else {
            if let id = request?.workoutID, UserDefaults.standard.string(forKey: "workout.finishedID") == id { publish("saved") }
            else { publish("error", error: "No active Watch workout. Retry sync on iPhone.") }
            return
        }
        do {
            status = "Saving…"
            session.stopActivity(with: end)
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
            publish("saved")
            session.end(); self.session = nil; self.builder = nil; active = false; status = "Saved to Apple Health"
        } catch { status = error.localizedDescription; publish("error", error: status) }
    }
    private func cancel() {
        session?.end(); builder?.discardWorkout(); session = nil; builder = nil
        active = false; status = "Workout discarded"; UserDefaults.standard.removeObject(forKey: "workout.request")
    }
    private func handle(_ message: WorkoutBridgeMessage) async {
        if message.action == "start" {
            if active {
                if request?.workoutID == message.workoutID { publish("recording") }
                return
            }
            request = message
            // HealthKit's launch delegate starts the session after the phone wakes the app.
        } else {
            guard request?.workoutID == message.workoutID else { return }
            if ["pause", "resume", "status", "finish"].contains(message.action), (message.controlVersion ?? 0) >= (request?.controlVersion ?? 0) {
                request?.cardioPauses = message.cardioPauses; request?.controlVersion = message.controlVersion
                cardioPauses = message.cardioPauses ?? []
                UserDefaults.standard.set(request?.data, forKey: "workout.request")
                await recover()
                if paused && session?.state == .running { session?.pause() }
                else if !paused && session?.state == .paused { session?.resume() }
                if active, message.action != "finish" { publish("recording") }
            }
            if message.action == "finish" { await finish(at: message.endedAt ?? Date()) }
            if message.action == "cancel" { cancel(); request = nil }
            if message.action == "status" {
                await recover()
                if active { publish("recording") }
                else if UserDefaults.standard.string(forKey: "workout.finishedID") == message.workoutID { publish("saved") }
                else { publish("error", error: "The Watch session is unavailable. Your local workout is kept.") }
            }
        }
    }
    private func publish(_ action: String, error: String? = nil) {
        guard var message = request else { return }
        message.action = action; message.error = error; message.heartRate = heartRate; message.calories = calories
        guard let data = message.data else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessageData(data, replyHandler: nil, errorHandler: { _ in WCSession.default.transferUserInfo(["workout": data]) })
        } else if action != "metrics" { WCSession.default.transferUserInfo(["workout": data]) }
    }
}

extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
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
        Task { @MainActor in self.heartRate = heart; self.calories = kcal; self.publish("metrics") }
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
                        if manager.paused { Text(CardioClock.display(CardioClock.elapsed(start: start, pauses: manager.cardioPauses, at: Date()))).font(.title.monospacedDigit()) }
                        else { Text(Date().addingTimeInterval(-CardioClock.elapsed(start: start, pauses: manager.cardioPauses, at: Date())), style: .timer).font(.title.monospacedDigit()) }
                        if manager.paused { Text("Paused").foregroundStyle(.orange) }
                    }
                    Label("\(Int(manager.heartRate)) bpm", systemImage: "heart.fill").foregroundStyle(.red)
                    Text("\(Int(manager.calories)) kcal").foregroundStyle(.secondary)
                    Button("Finish workout", role: .destructive) { Task { await manager.finish() } }
                }
            }.padding()
        }.task { await manager.recover() }
    }
}
