import SwiftUI
import FirebaseAuth
import FirebaseDatabase
import FirebaseStorage
import CryptoKit

@MainActor
final class GymStore: ObservableObject {
    @Published var uid = ""
    @Published var connected = false
    @Published var offlineSample = false
    @Published var error: String?
    @Published var busy = false
    @Published var prepared = false
    @Published var restoring = false
    @Published var restoreError: String?
    @Published private(set) var latestMessages: [String: ChatMessage] = [:]
    @Published private(set) var readThrough: [String: Double] = [:]
    @Published var gyms: [GymSummary] = []
    @Published var room: GymSummary?
    @Published var members: [RoomPresence] = []
    @Published var profiles: [String: SocialProfile] = [:]
    @Published var portraits: [String: UIImage] = [:]
    @Published var friends: [Friendship] = []
    @Published var blocked: Set<String> = []
    @Published var muted: Set<String> = []
    @Published private(set) var status = "Ready"
    @Published var equipment: [String: GymEquipmentOccupancy] = [:]
    @Published private(set) var setCompletedAt: Double = 0
    private var equipmentObservation: (DatabaseReference, DatabaseHandle)?
    private var equipmentDisconnectRefs: [DatabaseReference] = []
    @Published var station = "lounge"
    let configuration = SocialConfiguration.load()
    let location = GymLocationManager()
    private(set) var api: GymAPI?
    private(set) var membership: RoomMembership?
    private var observations: [(DatabaseReference, DatabaseHandle)] = []
    private var inboxObservations: [String: (DatabaseQuery, DatabaseHandle)] = [:]
    var openConversation: String?
    private var roomObservation: (DatabaseReference, DatabaseHandle)?
    private var profileRefs: [String: (DatabaseReference, DatabaseHandle)] = [:]
    private var assetPaths: [String: String] = [:]
    private var heartbeat: Task<Void, Never>?
    private var cleanup: Task<Void, Never>?
    private var joinAttempt: UUID?
    private var presenceRef: DatabaseReference?
    private var lastSend = Date.distantPast
    private var position = CGPoint(x: 2, y: 7)
    var me: SocialProfile? { profiles[uid] }
    var roomIdentity: String { membership?.publicID ?? uid }
    var anonymous: Bool { me?.visibility == "anonymous" }
    var incomingWorkIns: [(String, GymWorkInRequest)] {
        equipment.flatMap { station, value in value.requests.values.filter { $0.ownerID == roomIdentity && $0.expiresAt > Date().timeIntervalSince1970 * 1000 }.map { (station, $0) } }
    }
    func roomProfile(_ id: String) -> SocialProfile? {
        if id.hasPrefix("anon-") || members.first(where: { $0.uid == id })?.visibility == "anonymous" {
            var hidden = SocialProfile(uid: id, name: L("Anonymous lifter"), gsr: 0, cosmetics: [], interests: "", avatar: AvatarAppearance(preset: "anonymous", color: "blue"))
            hidden.visibility = "anonymous"
            return hidden
        }
        return profiles[id]
    }
    var roomProfiles: [String: SocialProfile] { Dictionary(uniqueKeysWithValues: members.compactMap { member in roomProfile(member.uid).map { (member.uid, $0) } }) }
    func occupants(_ station: String) -> [String] {
        (equipment[station]?.members ?? [:]).filter { id, session in members.contains { $0.uid == id && $0.sessionId == session && $0.isFresh() } }.keys.sorted()
    }
    func ownsStation(_ station: String) -> Bool { occupants(station).contains(roomIdentity) }
    func recordSetCompletion(_ date: Date) {
        let time = date.timeIntervalSince1970 * 1000
        guard time > setCompletedAt else { return }
        setCompletedAt = time; publishPresence(force: true)
    }
    func equipmentAction(_ station: String, _ action: String, target: String? = nil, mode: String = "workIn") async throws {
        guard let api, membership != nil else { throw GymFailure.message(L("Enter a live gym first.")) }
        var body: [String: Any] = ["mode": mode]
        if let target { body["targetID"] = target }
        try await api.send("equipment/\(station)/\(action)", body: body)
        if action == "claim" { setStation(station) }
        if action == "release", self.station == station { setStation("lounge") }
    }
    func trainerAPI() async throws -> GymAPI {
        if let api { return api }
        guard let configuration else { throw GymFailure.message(L("Cloud setup is missing.")) }
        configuration.configureFirebase()
        if Auth.auth().currentUser == nil { _ = try await Auth.auth().signInAnonymously() }
        uid = Auth.auth().currentUser?.uid ?? ""
        let service = GymAPI(configuration: configuration); api = service
        return service
    }
    var incomingRequests: [Friendship] { friends.filter { $0.status == "incoming" && !blocked.contains($0.uid) } }
    var unreadFriends: [String] { latestMessages.keys.filter { isUnread($0) }.sorted() }
    var inboxCount: Int { incomingRequests.count + unreadFriends.count + incomingWorkIns.count }
    var sharesRank: Bool {
        let key = "gym.shareRank.\(uid)"
        if UserDefaults.standard.object(forKey: key) != nil { return UserDefaults.standard.bool(forKey: key) }
        return (me?.gsr ?? 0) > 0 || !(me?.cosmetics.isEmpty ?? true)
    }

    /// Restore the approved cloud profile without publishing any local fields again.
    func restore() async {
        guard !connected, !restoring else { return }
        restoring = true; restoreError = nil
        defer { restoring = false }
        guard let configuration else { prepared = true; return }
        configuration.configureFirebase()
        guard let user = Auth.auth().currentUser else { prepared = true; return }
        do {
            let snapshot = try await Database.database().reference(withPath: "profiles/\(user.uid)").getData()
            if snapshot.exists() {
                guard let profile: SocialProfile = Self.decode(snapshot.value) else { throw GymFailure.message(L("Your community profile could not be loaded. Please retry.")) }
                uid = user.uid; api = GymAPI(configuration: configuration)
                activate(profile)
            }
            prepared = true
        } catch { restoreError = L("Could not restore your community profile. %@", error.localizedDescription) }
    }

    func perform(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await work() } catch {
                let nsError = error as NSError
                self.error = nsError.domain == AuthErrorDomain && nsError.code == AuthErrorCode.keychainError.rawValue
                    ? L("Your device could not securely save the guest session. Please close and reopen the app.")
                    : error.localizedDescription
            }
        }
    }

    func connect(name: String, gsr: Int, cosmetics: [String], interests: String, shareRank: Bool? = nil) async throws {
        guard let configuration else { throw GymFailure.message(L("Cloud setup is missing. Use the offline sample, or add SocialConfig.plist using the setup guide.")) }
        configuration.configureFirebase()
        api = GymAPI(configuration: configuration)
        let user: FirebaseAuth.User
        if let existing = Auth.auth().currentUser { user = existing }
        else { user = try await Auth.auth().signInAnonymously().user }
        uid = user.uid
        let profile: SocialProfile = try await api!.post("profile", body: ["name": name, "gsr": gsr, "cosmetics": cosmetics, "interests": interests, "shareRank": shareRank ?? (gsr > 0 || !cosmetics.isEmpty)])
        UserDefaults.standard.set(shareRank ?? (gsr > 0 || !cosmetics.isEmpty), forKey: "gym.shareRank.\(uid)")
        activate(profile)
    }

    func updateProfile(name: String, interests: String, shareRank: Bool, gsr: Int, cosmetics: [String], muscleRanks: [String: Int], shareActivity: Bool, highlights: GymTrainingHighlights?, routines: [GymPublicRoutine], snapshotOnly: Bool = false, visibility: String? = nil) async throws {
        guard let me, let api else { throw GymFailure.message(L("Connect your community profile first.")) }
        let previousRoom = room, changedVisibility = visibility != nil && visibility != me.visibility
        var body = me.jsonObject
        if let visibility { body["visibility"] = visibility }
        body["name"] = name; body["interests"] = interests
        body["gsr"] = shareRank ? gsr : 0; body["cosmetics"] = shareRank ? cosmetics : []
        body["snapshotOnly"] = snapshotOnly
        body["shareRank"] = shareRank
        body["muscleRanks"] = shareRank ? muscleRanks : [:]
        body["shareActivity"] = shareActivity
        if shareActivity, let highlights, let data = try? JSONEncoder().encode(highlights) { body["highlights"] = try? JSONSerialization.jsonObject(with: data) }
        else { body["highlights"] = NSNull() }
        if let data = try? JSONEncoder().encode(routines) { body["routines"] = try? JSONSerialization.jsonObject(with: data) }
        let saved: SocialProfile = try await api.post("profile", body: body)
        if !snapshotOnly {
            profiles[uid] = saved
            UserDefaults.standard.set(shareRank, forKey: "gym.shareRank.\(uid)")
            if changedVisibility, let previousRoom { await leave(); try await join(previousRoom) }
        }
    }

    private func activate(_ profile: SocialProfile) {
        stopObservers()
        profiles[uid] = profile; connected = true; offlineSample = false; prepared = true
        restoreError = nil
        muted = Set(UserDefaults.standard.stringArray(forKey: "gym.muted.\(uid)") ?? [])
        readThrough = UserDefaults.standard.dictionary(forKey: "gym.readThrough.\(uid)") as? [String: Double] ?? [:]
        observeProfile(uid)
        let friendsRef = Database.database().reference(withPath: "social/friends/\(uid)")
        observations.append((friendsRef, friendsRef.observe(.value) { [weak self] snap in
            Task { @MainActor in
                guard let self else { return }
                self.friends = Self.decodeDictionary(snap.value, as: Friendship.self).sorted { $0.updatedAt > $1.updatedAt }
                for friend in self.friends { self.observeProfile(friend.uid) }
                self.observeInbox()
            }
        }))
        let blockRef = Database.database().reference(withPath: "social/blocks/\(uid)")
        observations.append((blockRef, blockRef.observe(.value) { [weak self] snap in
            Task { @MainActor in self?.blocked = Set((snap.value as? [String: Bool] ?? [:]).filter(\.value).map(\.key)) }
        }))
        let connectionRef = Database.database().reference(withPath: ".info/connected")
        observations.append((connectionRef, connectionRef.observe(.value) { [weak self] snap in
            Task { @MainActor in
                guard let self else { return }
                if snap.value as? Bool == false, self.membership != nil {
                    Database.database().purgeOutstandingWrites()
                    self.detachRoom()
                    self.error = L("Connection lost. Check in again when you are online.")
                }
            }
        }))
    }

    func isUnread(_ id: String) -> Bool {
        guard !blocked.contains(id), let latest = latestMessages[id], latest.senderID != uid else { return false }
        return latest.createdAt > (readThrough[id] ?? 0)
    }
    func markRead(_ id: String) {
        guard let latest = latestMessages[id] else { return }
        readThrough[id] = max(readThrough[id] ?? 0, latest.createdAt)
        UserDefaults.standard.set(readThrough, forKey: "gym.readThrough.\(uid)")
    }
    private func observeInbox() {
        let accepted = Set(friends.filter { $0.status == "accepted" }.map(\.uid))
        for id in Array(inboxObservations.keys) where !accepted.contains(id) {
            if let (query, handle) = inboxObservations.removeValue(forKey: id) { query.removeObserver(withHandle: handle) }
            latestMessages[id] = nil
        }
        for id in accepted where inboxObservations[id] == nil {
            let query = Database.database().reference(withPath: "social/chats/\(Self.conversationID(uid, id))/messages").queryOrdered(byChild: "createdAt").queryLimited(toLast: 1)
            let handle = query.observe(.value, with: { [weak self] snapshot in
                Task { @MainActor in
                    guard let self, self.friends.contains(where: { $0.uid == id && $0.status == "accepted" }) else { return }
                    self.latestMessages[id] = Self.decodeDictionary(snapshot.value, as: ChatMessage.self).max { $0.createdAt < $1.createdAt }
                    if self.openConversation == id { self.markRead(id) }
                }
            }, withCancel: { [weak self] _ in Task { @MainActor in self?.latestMessages[id] = nil } })
            inboxObservations[id] = (query, handle)
        }
    }

    func sample(name: String, gsr: Int, cosmetics: [String]) {
        stopObservers(); uid = "sample-me"; connected = false; offlineSample = true; prepared = true
        friends = []; blocked = []; muted = []
        profiles = [uid: SocialProfile(uid: uid, name: name, gsr: gsr, cosmetics: cosmetics, interests: L("Strength training"), avatar: AvatarAppearance())]
        let sample = SocialProfile(uid: "sample-alex", name: L("Alex · sample"), gsr: 540, cosmetics: [], interests: L("Bench press and consistency"), avatar: AvatarAppearance(preset: "star", color: "blue"))
        profiles[sample.uid] = sample
        members = [RoomPresence(uid: uid, sessionId: "sample", x: 2, y: 7, station: "lounge", status: status, updatedAt: Date().timeIntervalSince1970 * 1000),
            RoomPresence(uid: sample.uid, sessionId: "sample", x: 4, y: 3, station: "bench", status: "Training", updatedAt: Date().timeIntervalSince1970 * 1000)]
        room = .demo
    }

    func search(query: String, nearby: Bool, radius: Int) async throws {
        guard let api else { throw GymFailure.message(L("Connect your guest profile first.")) }
        let point = nearby ? try await location.current() : nil
        gyms = try await api.search(query: query, location: point, radius: radius)
    }

    func join(_ gym: GymSummary) async throws {
        guard let api else { return }
        let attempt = UUID(); joinAttempt = attempt
        defer { if joinAttempt == attempt { joinAttempt = nil } }
        // A quick Leave → Enter must finish removing the old presence before publishing a new one.
        await cleanup?.value
        cleanup = nil
        guard joinAttempt == attempt else { throw GymFailure.message(L("Gym entry was cancelled. Enter again when ready.")) }
        await leave()
        guard joinAttempt == attempt else { throw GymFailure.message(L("Gym entry was cancelled. Enter again when ready.")) }
        let point = gym.isDemo ? nil : try await location.current()
        let lease = try await api.join(gym, location: point)
        guard joinAttempt == attempt else {
            try? await api.leave(lease)
            throw GymFailure.message(L("Gym entry was cancelled. Enter again when ready."))
        }
        membership = lease; position = CGPoint(x: lease.spawnX ?? 2, y: lease.spawnY ?? 7); station = "lounge"
        let ref = Database.database().reference(withPath: "world/rooms/\(lease.roomId)/presence/\(lease.publicID ?? uid)")
        presenceRef = ref
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                ref.onDisconnectRemoveValue { error, _ in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            guard joinAttempt == attempt, membership?.sessionId == lease.sessionId else {
                _ = try? await ref.removeValue(); _ = try? await ref.cancelDisconnectOperations()
                try? await api.leave(lease)
                throw GymFailure.message(L("Gym entry was cancelled. Enter again when ready."))
            }
            for station in GymLayout.stations where station != "lounge" {
                let equipmentRef = Database.database().reference(withPath: "world/rooms/\(lease.roomId)/equipment/\(station)/members/\(lease.publicID ?? uid)")
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    equipmentRef.onDisconnectRemoveValue { error, _ in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }
                }
                equipmentDisconnectRefs.append(equipmentRef)
            }
            // Publish only after server-side disconnect cleanup is installed.
            publishPresence(force: true)
        } catch { await leave(); throw error }
        let roomRef = ref.parent!
        roomObservation = (roomRef, roomRef.observe(.value, with: { [weak self] snap in
            Task { @MainActor in
                guard let self, self.membership?.sessionId == lease.sessionId else { return }
                self.members = Self.decodeDictionary(snap.value, as: RoomPresence.self).filter { $0.isFresh() }
                for member in self.members where member.visibility != "anonymous" { self.observeProfile(member.uid) }
            }
        }, withCancel: { [weak self] error in Task { @MainActor in self?.error = error.localizedDescription; self?.detachRoom() } }))
        let equipmentRef = Database.database().reference(withPath: "world/rooms/\(lease.roomId)/equipment")
        equipmentObservation = (equipmentRef, equipmentRef.observe(.value) { [weak self] snap in
            Task { @MainActor in
                guard let self, self.membership?.sessionId == lease.sessionId else { return }
                let raw = snap.value as? [String: Any] ?? [:]
                self.equipment = raw.compactMapValues { Self.decode($0) as GymEquipmentOccupancy? }
                if let accepted = GymLayout.stations.first(where: { self.ownsStation($0) }), self.station != accepted { self.setStation(accepted) }
                else if self.station != "lounge" && !self.ownsStation(self.station) { self.setStation("lounge") }
            }
        })
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.membership?.sessionId == lease.sessionId else { return }
                do {
                    let renewed = try await api.renew(lease)
                    guard self.membership?.sessionId == lease.sessionId else { return }
                    self.membership = renewed
                    self.publishPresence(force: true)
                    self.members.removeAll { !$0.isFresh() }
                } catch { self.error = error.localizedDescription; await self.leave(); return }
            }
        }
        room = gym
    }

    func move(x: Double, y: Double) {
        position = CGPoint(x: x, y: y)
        if offlineSample {
            if let index = members.firstIndex(where: { $0.uid == uid }) { members[index].x = x; members[index].y = y }
        } else { publishPresence(force: false) }
    }
    func publishPresence(force: Bool) {
        guard let membership, membership.expiresAt > Date().timeIntervalSince1970 * 1000, let ref = presenceRef else { return }
        guard force || Date().timeIntervalSince(lastSend) >= 0.2 else { return }
        lastSend = Date()
        ref.setValue(["uid": roomIdentity, "sessionId": membership.sessionId, "x": position.x, "y": position.y,
            "station": station, "status": status, "visibility": membership.visibility ?? "public", "setCompletedAt": setCompletedAt, "updatedAt": ServerValue.timestamp()]) { [weak self] error, _ in
            if let error { Task { @MainActor in self?.error = error.localizedDescription } }
        }
    }
    func setStation(_ value: String) {
        guard GymLayout.stations.contains(value), value == "lounge" || offlineSample || ownsStation(value) else { return }
        station = value
        if offlineSample, let index = members.firstIndex(where: { $0.uid == uid }) { members[index].station = value; members[index].status = status }
        publishPresence(force: true)
    }
    func setTrainingState(_ value: String) {
        guard ["Ready", "Training", "Resting"].contains(value), status != value else { return }
        status = value
        setStation(station)
    }
    func canRequestFriend(_ id: String) -> Bool {
        guard membership != nil, !anonymous, !offlineSample, !blocked.contains(id), id != uid, members.first(where: { $0.uid == id })?.visibility != "anonymous" else { return false }
        return members.contains { $0.uid == id && $0.isFresh() } && members.contains { $0.uid == roomIdentity && $0.isFresh() }
    }
    func leave() async {
        let lease = membership, ref = presenceRef
        detachRoom()
        await cleanup?.value
        if let ref { _ = try? await ref.removeValue(); _ = try? await ref.cancelDisconnectOperations() }
        if let lease { try? await api?.leave(lease) }
    }
    func suspend() {
        // Clear the scene immediately before asynchronous network cleanup.
        joinAttempt = nil
        let lease = membership, ref = presenceRef
        detachRoom()
        let previous = cleanup
        cleanup = Task {
            await previous?.value
            if let ref { _ = try? await ref.removeValue(); _ = try? await ref.cancelDisconnectOperations() }
            if let lease { try? await api?.leave(lease) }
        }
    }
    private func detachRoom() {
        if let (ref, handle) = equipmentObservation { ref.removeObserver(withHandle: handle) }
        equipmentObservation = nil; equipment = [:]
        let disconnectRefs = equipmentDisconnectRefs; equipmentDisconnectRefs = []
        let pendingCleanup = cleanup
        cleanup = Task {
            await pendingCleanup?.value
            for ref in disconnectRefs { _ = try? await ref.removeValue(); _ = try? await ref.cancelDisconnectOperations() }
        }
        heartbeat?.cancel(); heartbeat = nil
        if let (ref, handle) = roomObservation { ref.removeObserver(withHandle: handle) }
        roomObservation = nil; membership = nil; presenceRef = nil; room = nil; members = []
    }
    func observeProfile(_ id: String) {
        guard profileRefs[id] == nil else { return }
        let ref = Database.database().reference(withPath: "profiles/\(id)")
        let handle = ref.observe(.value, with: { [weak self] snap in
            Task { @MainActor in
                guard let self, let p: SocialProfile = Self.decode(snap.value) else { return }
                self.profiles[id] = p
                if let path = p.avatar.assetPath, self.assetPaths[id] != path {
                    self.assetPaths[id] = path
                    Task {
                        if let data = try? await Storage.storage().reference(withPath: path).data(maxSize: 5 * 1024 * 1024),
                           self.assetPaths[id] == path { self.portraits[id] = UIImage(data: data) }
                    }
                } else if p.avatar.assetPath == nil { self.portraits[id] = nil; self.assetPaths[id] = nil }
            }
        }, withCancel: { [weak self] _ in
            Task { @MainActor in
                self?.profileRefs.removeValue(forKey: id)
                self?.profiles.removeValue(forKey: id)
                self?.portraits.removeValue(forKey: id)
                self?.assetPaths.removeValue(forKey: id)
            }
        })
        profileRefs[id] = (ref, handle)
    }
    func saveAppearance(_ avatar: AvatarAppearance, reset: Bool = false) async throws {
        guard var me else { return }
        me.avatar = avatar
        if offlineSample { profiles[uid] = me; return }
        var body = me.jsonObject; body["resetAvatar"] = reset
        let saved: SocialProfile = try await api!.post("profile", body: body)
        profiles[uid] = saved
    }
    func toggleMute(_ id: String) {
        if muted.contains(id) { muted.remove(id) } else { muted.insert(id) }
        UserDefaults.standard.set(Array(muted), forKey: "gym.muted.\(uid)")
    }
    func stopObservers() {
        for (ref, handle) in observations { ref.removeObserver(withHandle: handle) }
        for (_, pair) in profileRefs { pair.0.removeObserver(withHandle: pair.1) }
        for (_, pair) in inboxObservations { pair.0.removeObserver(withHandle: pair.1) }
        observations = []; profileRefs = [:]; inboxObservations = [:]; latestMessages = [:]; openConversation = nil
    }
    static func decode<T: Decodable>(_ value: Any?) -> T? {
        guard let value, JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    static func decodeDictionary<T: Decodable>(_ value: Any?, as type: T.Type) -> [T] {
        guard let dict = value as? [String: Any] else { return [] }
        return dict.values.compactMap { decode($0) }
    }
    static func conversationID(_ a: String, _ b: String) -> String {
        SHA256.hash(data: Data([a, b].sorted().joined(separator: "\0").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class GymChatFeed: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var error: String?
    private var query: DatabaseQuery?
    private var handle: DatabaseHandle?
    func start(path: String) {
        stop()
        let query = Database.database().reference(withPath: path).queryOrdered(byChild: "createdAt").queryLimited(toLast: 200)
        self.query = query
        handle = query.observe(.value, with: { [weak self] snap in
            Task { @MainActor in self?.messages = GymStore.decodeDictionary(snap.value, as: ChatMessage.self).sorted { $0.createdAt < $1.createdAt } }
        }, withCancel: { [weak self] _ in Task { @MainActor in self?.messages = []; self?.error = L("This conversation is no longer available.") } })
    }
    func stop() { if let handle { query?.removeObserver(withHandle: handle) }; query = nil; handle = nil; messages = [] }
}
