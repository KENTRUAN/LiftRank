import SwiftUI
import MapKit
import CoreLocation
import SwiftData
import HealthKit

extension Workout {
    var healthConfiguration: HKWorkoutConfiguration { activity.configuration(outdoor: isOutdoor) }
    var routeDistanceMeters: Double {
        zip(routePoints, routePoints.dropFirst()).reduce(0) { total, pair in
            guard !cardioPauses.contains(where: { $0.startedAt < pair.1.timestamp && ($0.endedAt ?? .distantFuture) > pair.0.timestamp }) else { return total }
            return total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude).distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
    }
}

/// Foreground-only private route. Gym check-in and social presence never receive these points.
@MainActor
final class OutdoorWorkoutTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = OutdoorWorkoutTracker()
    @Published var error: String?
    private let manager = CLLocationManager()
    private var workout: Workout?
    private override init() {
        super.init(); manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest; manager.distanceFilter = 10; manager.activityType = .fitness
    }
    func follow(_ workout: Workout?, foreground: Bool) {
        guard foreground, let workout, workout.isOutdoor, workout.activity != .strength, workout.startOptionsChosen, !workout.cardioIsPaused, !workout.isPublished, workout.endedAt == nil else { manager.stopUpdatingLocation(); self.workout = nil; return }
        self.workout = workout
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: error = nil; manager.startUpdatingLocation()
        default: error = "Allow location in Settings to show your outdoor route. Workout timing continues."
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.follow(self.workout, foreground: self.workout != nil) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let workout = self.workout, !workout.cardioIsPaused, !workout.isPublished, workout.endedAt == nil else { return }
            for point in locations where point.horizontalAccuracy >= 0 && point.horizontalAccuracy <= 50 && abs(point.timestamp.timeIntervalSinceNow) < 20 {
                if let last = workout.routePoints.last {
                    let seconds = point.timestamp.timeIntervalSince(last.timestamp)
                    let distance = point.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
                    guard seconds > 0, distance >= 5, distance / seconds < 35 else { continue }
                }
                workout.routePoints.append(WorkoutRoutePoint(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude, timestamp: point.timestamp))
                if workout.routePoints.count > 10000 { workout.routePoints = workout.routePoints.enumerated().filter { $0.offset % 2 == 0 }.map(\.element) }
            }
            try? workout.modelContext?.save()
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.error = "Waiting for an accurate location…" }
    }
}

struct OutdoorWorkoutMap: View {
    @Bindable var workout: Workout
    @ObservedObject private var tracker = OutdoorWorkoutTracker.shared
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Label("Outdoor route", systemImage: "map.fill").font(.headline); Spacer(); Text("\((workout.routeDistanceMeters / 1000).fmt(2)) km").monospacedDigit() }
            Map(position: $camera) {
                UserAnnotation()
                if workout.routePoints.count > 1 { MapPolyline(coordinates: workout.routePoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.teal, lineWidth: 5) }
            }
            .mapControls { MapUserLocationButton(); MapCompass() }
            .frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("outdoorWorkoutMap")
            Text(tracker.error ?? "Private route · updates while LiftRank is open").font(.caption).foregroundStyle(.secondary)
        }
    }
}
