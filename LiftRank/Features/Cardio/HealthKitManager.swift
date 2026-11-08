import Foundation
import HealthKit

struct CardioImport {
    let externalID: String
    let date: Date
    let type: CardioType
    let durationMinutes: Double
    let distanceKm: Double
    let calories: Double
    let avgHeartRate: Double
    let sourceName: String
}

/// Reads workouts recorded by Apple Watch / Fitness and writes manual cardio back to Health.
final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = [HKObjectType.workoutType()]
        for id in [HKQuantityTypeIdentifier.heartRate, .activeEnergyBurned, .distanceWalkingRunning, .distanceCycling, .distanceSwimming] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { set.insert(t) }
        }
        return set
    }
    private var writeTypes: Set<HKSampleType> {
        var set: Set<HKSampleType> = [HKObjectType.workoutType()]
        for id in [HKQuantityTypeIdentifier.activeEnergyBurned, .distanceWalkingRunning, .distanceCycling, .distanceSwimming] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { set.insert(t) }
        }
        return set
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    func importWorkouts(since: Date) async throws -> [CardioImport] {
        guard isAvailable else { throw HealthError.unavailable }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: (samples as? [HKWorkout]) ?? []) }
            }
            store.execute(q)
        }
        var out: [CardioImport] = []
        for w in workouts {
            // Unified LiftRank workouts already exist locally; never import them a second time.
            if w.metadata?["LiftRankWorkoutID"] != nil || w.metadata?["LiftRankCardioID"] != nil { continue }
            guard let type = Self.cardioType(for: w.workoutActivityType) else { continue }
            let km = (w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()
                      ?? w.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()
                      ?? w.statistics(for: HKQuantityType(.distanceSwimming))?.sumQuantity())?.doubleValue(for: .meterUnit(with: .kilo)) ?? 0
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            let hr = await averageHeartRate(start: w.startDate, end: w.endDate)
            out.append(CardioImport(externalID: w.uuid.uuidString, date: w.startDate, type: type, durationMinutes: w.duration / 60,
                                    distanceKm: km, calories: kcal, avgHeartRate: hr, sourceName: w.sourceRevision.source.name))
        }
        return out
    }

    private func averageHeartRate(start: Date, end: Date) async -> Double {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: hrType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0)
            }
            store.execute(q)
        }
    }

    /// Saves a manually logged session as an HKWorkout so it shows in Fitness.
    func save(_ session: CardioSession) async throws {
        guard isAvailable else { throw HealthError.unavailable }
        let config = HKWorkoutConfiguration()
        config.activityType = Self.activityType(for: session.type)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.addMetadata([HKMetadataKeySyncIdentifier: "liftrank.cardio.\(session.id.uuidString)", HKMetadataKeySyncVersion: 1, "LiftRankCardioID": session.id.uuidString])
        let start = session.date
        let end = start.addingTimeInterval(session.durationMinutes * 60)
        try await builder.beginCollection(at: start)
        var samples: [HKSample] = []
        if session.calories > 0, let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            samples.append(HKQuantitySample(type: t, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: session.calories), start: start, end: end))
        }
        if session.distanceKm > 0 {
            let id: HKQuantityTypeIdentifier = session.type == .cycling ? .distanceCycling : session.type == .swimming ? .distanceSwimming : .distanceWalkingRunning
            if let t = HKObjectType.quantityType(forIdentifier: id) {
                samples.append(HKQuantitySample(type: t, quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: session.distanceKm), start: start, end: end))
            }
        }
        if !samples.isEmpty { try await builder.addSamples(samples) }
        try await builder.endCollection(at: end)
        let saved = try await builder.finishWorkout()
        session.externalID = saved?.uuid.uuidString ?? session.externalID
    }

    static func cardioType(for t: HKWorkoutActivityType) -> CardioType? {
        switch t {
        case .running: .running
        case .walking: .walking
        case .hiking: .hiking
        case .cycling, .handCycling: .cycling
        case .swimming: .swimming
        case .rowing: .rowing
        case .elliptical: .elliptical
        case .stairClimbing, .stairs, .stepTraining: .stairs
        case .jumpRope: .jumpRope
        case .highIntensityIntervalTraining: .hiit
        case .mixedCardio, .crossTraining, .cardioDance, .kickboxing, .soccer, .basketball, .tennis, .badminton: .other
        default: nil
        }
    }

    static func activityType(for c: CardioType) -> HKWorkoutActivityType {
        switch c {
        case .running: .running
        case .walking: .walking
        case .hiking: .hiking
        case .cycling: .cycling
        case .swimming: .swimming
        case .rowing: .rowing
        case .elliptical: .elliptical
        case .stairs: .stairClimbing
        case .jumpRope: .jumpRope
        case .hiit: .highIntensityIntervalTraining
        case .other: .mixedCardio
        }
    }

    enum HealthError: LocalizedError {
        case unavailable
        var errorDescription: String? { L("此设备不支持 Apple Health。") }
    }
}
