import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase
import CoreLocation

struct SocialConfiguration {
    let apiURL: URL
    let emulatorHost: String?
    let projectID: String
    let apiKey: String
    let appID: String
    let senderID: String
    let databaseURL: String
    let storageBucket: String

    static func load() -> SocialConfiguration? {
        guard let url = Bundle.main.url(forResource: "SocialConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url), let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let endpoint = raw["API_URL"], let apiURL = URL(string: endpoint),
              let project = raw["PROJECT_ID"], let key = raw["API_KEY"], let appID = raw["APP_ID"],
              let databaseURL = raw["DATABASE_URL"] else { return nil }
        let emulator = raw["EMULATOR_HOST"].flatMap { $0.isEmpty ? nil : $0 }
        guard apiURL.scheme == "https" || (emulator != nil && apiURL.scheme == "http") else { return nil }
        return SocialConfiguration(apiURL: apiURL, emulatorHost: emulator, projectID: project, apiKey: key,
            appID: appID, senderID: raw["SENDER_ID"] ?? "123456789", databaseURL: databaseURL,
            storageBucket: raw["STORAGE_BUCKET"] ?? "\(project).firebasestorage.app")
    }

    func configureFirebase() {
        guard FirebaseApp.app() == nil else { return }
        let options = FirebaseOptions(googleAppID: appID, gcmSenderID: senderID)
        options.projectID = projectID; options.apiKey = apiKey
        options.databaseURL = databaseURL; options.storageBucket = storageBucket
        FirebaseApp.configure(options: options)
        if let emulatorHost {
            Auth.auth().useEmulator(withHost: emulatorHost, port: 9099)
            Database.database().useEmulator(withHost: emulatorHost, port: 9000)
        }
        // Never persist queued movement across launches.
        Database.database().isPersistenceEnabled = false
    }
}

final class GymAPI {
    let configuration: SocialConfiguration
    // Keep private AI payloads out of persistent HTTP caches. This also avoids
    // the cached HTTP/3 regression in the iOS 18.4 simulator (Apple FB17006003).
    private let session = URLSession(configuration: .ephemeral)
    init(configuration: SocialConfiguration) { self.configuration = configuration }
    deinit { session.invalidateAndCancel() }
    func post<T: Decodable>(_ path: String, body: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        guard let user = Auth.auth().currentUser else { throw GymFailure.message(L("Please connect your guest profile first.")) }
        let token = try await user.getIDToken()
        var request = URLRequest(url: configuration.apiURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = path.contains("generate") ? 120 : (path == "trainer" ? 135 : 55)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError {
            throw GymFailure.message(error.code == .timedOut
                ? "The request took too long. Please retry."
                : "Connection lost. Check your internet connection and retry.")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw GymFailure.message(error ?? "The gym service is unavailable. Please retry.")
        }
        return try JSONDecoder().decode(type, from: data)
    }
    func send(_ path: String, body: [String: Any] = [:]) async throws {
        let _: IgnoredResponse = try await post(path, body: body)
    }
    private struct IgnoredResponse: Decodable {}
}

protocol GymDirectoryService {
    func search(query: String, location: GymLocation?, radius: Int) async throws -> [GymSummary]
}
protocol RoomService {
    func join(_ gym: GymSummary, location: GymLocation?) async throws -> RoomMembership
    func renew(_ membership: RoomMembership) async throws -> RoomMembership
    func leave(_ membership: RoomMembership) async throws
}
protocol AvatarService {
    func generate(prompt: String, selfie: AvatarPreview?) async throws -> AvatarPreview
    func approve(_ preview: AvatarPreview) async throws
}
protocol CompanionService {
    func respond(messages: [[String: String]], workout: String, station: String?, targetID: String?) async throws -> String
}
protocol SocialService {
    func friendAction(target: String, action: String) async throws
    func message(target: String, room: Bool, id: String, text: String) async throws
}

extension GymAPI: GymDirectoryService, RoomService, AvatarService, CompanionService, SocialService {
    func search(query: String, location: GymLocation?, radius: Int) async throws -> [GymSummary] {
        struct Result: Decodable { var gyms: [GymSummary] }
        var body: [String: Any] = ["query": query, "radius": radius]
        if let location { body["location"] = location.jsonObject }
        return try await post("gyms/search", body: body, as: Result.self).gyms
    }
    func join(_ gym: GymSummary, location: GymLocation?) async throws -> RoomMembership {
        var body: [String: Any] = ["roomId": gym.id]
        if let placeID = gym.placeID { body["placeID"] = placeID }
        if let location { body["location"] = location.jsonObject }
        return try await post("rooms/join", body: body)
    }
    func renew(_ membership: RoomMembership) async throws -> RoomMembership {
        try await post("rooms/renew", body: ["sessionId": membership.sessionId])
    }
    func leave(_ membership: RoomMembership) async throws { try await send("rooms/leave", body: ["sessionId": membership.sessionId]) }
    func friendAction(target: String, action: String) async throws { try await send("friends/\(target)/\(action)") }
    func message(target: String, room: Bool, id: String, text: String) async throws {
        try await send("messages/\(room ? "room" : "private")/\(target)", body: ["id": id, "text": text])
    }
    func generate(prompt: String, selfie: AvatarPreview?) async throws -> AvatarPreview {
        var body: [String: Any] = ["prompt": prompt]
        if let selfie { body["selfie"] = selfie.jsonObject }
        return try await post("avatars/generate", body: body)
    }
    func approve(_ preview: AvatarPreview) async throws { try await send("avatars/approve", body: ["image": preview.jsonObject]) }
    func respond(messages: [[String: String]], workout: String, station: String?, targetID: String?) async throws -> String {
        struct Result: Decodable { var reply: String }
        var body: [String: Any] = ["messages": messages]
        if !workout.isEmpty { body["workout"] = workout }
        if let station { body["station"] = station }
        if let targetID { body["targetID"] = targetID }
        return try await post("companion", body: body, as: Result.self).reply
    }
}

extension Encodable {
    var jsonObject: [String: Any] { (try? JSONEncoder().encode(self)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:] }
}

@MainActor
final class GymLocationManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<GymLocation, Error>?
    private var timeout: Task<Void, Never>?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest }
    func current() async throws -> GymLocation {
        guard continuation == nil else { throw GymFailure.message(L("Already finding your location.")) }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(GymFailure.message(L("Location timed out. Try again outdoors or use Demo Gym."))))
            }
            if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
            else { requestIfAuthorized() }
        }
    }
    private func requestIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: finish(.failure(GymFailure.message(L("Enable precise location in Settings to check in. You can still search or use Demo Gym."))))
        default: break
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if continuation != nil { requestIfAuthorized() } }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last, value.horizontalAccuracy >= 0 else { return }
        finish(.success(GymLocation(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude,
            accuracy: value.horizontalAccuracy, timestamp: value.timestamp.timeIntervalSince1970 * 1000)))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<GymLocation, Error>) {
        timeout?.cancel(); timeout = nil
        let pending = continuation; continuation = nil
        pending?.resume(with: result)
    }
}
