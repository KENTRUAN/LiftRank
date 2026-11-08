import Foundation
import SwiftUI

struct AvatarAppearance: Codable, Equatable {
    var preset = "bolt"
    var color = "orange"
    var assetPath: String?
    var tint: Color {
        switch color { case "blue": .cyan; case "purple": .purple; case "green": .mint; default: .orange }
    }
    var symbol: String {
        switch preset { case "anonymous": "person.fill"; case "leaf": "leaf.fill"; case "star": "star.fill"; default: "bolt.fill" }
    }
}

struct SocialProfile: Codable, Identifiable, Equatable {
    var uid: String
    var name: String
    var gsr: Int
    var cosmetics: [String]
    var interests: String
    var avatar: AvatarAppearance
    var muscleRanks: [String: Int] = [:]
    var visibility = "public"
    var shareActivity = false
    var highlights: GymTrainingHighlights?
    var routines: [GymPublicRoutine] = []
    var id: String { uid }

    init(uid: String, name: String, gsr: Int, cosmetics: [String], interests: String, avatar: AvatarAppearance) {
        self.uid = uid; self.name = name; self.gsr = gsr; self.cosmetics = cosmetics
        self.interests = interests; self.avatar = avatar
    }
    enum CodingKeys: String, CodingKey { case uid, name, gsr, cosmetics, interests, avatar, muscleRanks, shareActivity, highlights, routines, visibility }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        uid = try values.decode(String.self, forKey: .uid)
        name = try values.decode(String.self, forKey: .name)
        gsr = try values.decodeIfPresent(Int.self, forKey: .gsr) ?? 0
        // Realtime Database removes empty arrays; omitted cosmetics are valid.
        cosmetics = try values.decodeIfPresent([String].self, forKey: .cosmetics) ?? []
        interests = try values.decodeIfPresent(String.self, forKey: .interests) ?? ""
        avatar = try values.decodeIfPresent(AvatarAppearance.self, forKey: .avatar) ?? AvatarAppearance()
        muscleRanks = try values.decodeIfPresent([String: Int].self, forKey: .muscleRanks) ?? [:]
        visibility = try values.decodeIfPresent(String.self, forKey: .visibility) ?? "public"
        shareActivity = try values.decodeIfPresent(Bool.self, forKey: .shareActivity) ?? false
        highlights = try values.decodeIfPresent(GymTrainingHighlights.self, forKey: .highlights)
        routines = try values.decodeIfPresent([GymPublicRoutine].self, forKey: .routines) ?? []
    }
}

struct GymSummary: Codable, Identifiable, Equatable {
    struct Attribution: Codable, Equatable { var provider: String; var uri: String }
    var id: String
    var placeID: String?
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var distanceMeters: Double?
    var isDemo: Bool
    var attributions: [Attribution]?
    static var demo: GymSummary { GymSummary(id: "demo-gym", name: L("Demo Gym"), address: L("A shared room for the hackathon. Join from anywhere."), isDemo: true) }
}

struct GymLocation: Codable {
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var timestamp: Double
}

struct RoomMembership: Codable {
    var roomId: String
    var sessionId: String
    var expiresAt: Double
    var spawnX: Double?
    var spawnY: Double?
    var publicID: String?
    var visibility: String?
}

struct RoomPresence: Codable, Identifiable, Equatable {
    var uid: String
    var sessionId: String
    var x: Double
    var y: Double
    var station: String
    var status: String
    var updatedAt: Double
    var openToChat: Bool? = nil // Decode older presences during rollout.
    var visibility: String? = nil
    var setCompletedAt: Double? = nil
    var id: String { uid }
    func isFresh(now: Date = Date()) -> Bool { now.timeIntervalSince1970 * 1000 - updatedAt < 45_000 }
}

struct Friendship: Codable, Identifiable {
    var uid: String
    var status: String
    var updatedAt: Double
    var id: String { uid }
}

struct ChatMessage: Codable, Identifiable {
    var id: String
    var senderID: String
    var text: String
    var createdAt: Double
}

struct AvatarPreview: Codable {
    var data: String
    var mimeType: String
    var image: UIImage? { Data(base64Encoded: data).flatMap(UIImage.init(data:)) }
}

enum GymFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

/// Integer grid shared by pathfinding, station selection, and scene projection.
enum GymLayout {
    struct Cell: Hashable { var x: Int; var y: Int }
    static let width = 12, height = 10
    static let stations = ["lounge", "bench", "rack", "cardio", "platform"]
    static let statuses = ["Ready", "Training", "Resting"]
    static let stationCells: [String: Cell] = ["lounge": Cell(x: 2, y: 7), "bench": Cell(x: 4, y: 3), "rack": Cell(x: 1, y: 2), "cardio": Cell(x: 9, y: 2), "platform": Cell(x: 8, y: 6)]
    static let blocked: Set<Cell> = [Cell(x: 1, y: 1), Cell(x: 2, y: 1), Cell(x: 4, y: 2), Cell(x: 5, y: 2), Cell(x: 8, y: 1), Cell(x: 9, y: 1), Cell(x: 8, y: 5), Cell(x: 9, y: 5), Cell(x: 1, y: 8), Cell(x: 2, y: 8)]
    static func walkable(_ c: Cell) -> Bool { (0..<width).contains(c.x) && (0..<height).contains(c.y) && !blocked.contains(c) }
    static func path(from start: Cell, to end: Cell) -> [Cell] {
        guard walkable(start), walkable(end), start != end else { return [] }
        var queue = [start], index = 0
        var previous: [Cell: Cell] = [:]
        var seen: Set<Cell> = [start]
        while index < queue.count {
            let current = queue[index]; index += 1
            if current == end {
                var result = [end], node = end
                while let parent = previous[node], parent != start { result.append(parent); node = parent }
                return result.reversed()
            }
            for d in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let next = Cell(x: current.x + d.0, y: current.y + d.1)
                if walkable(next), seen.insert(next).inserted { previous[next] = current; queue.append(next) }
            }
        }
        return []
    }
}

struct GymWorkInRequest: Codable, Identifiable, Equatable {
    var id: String
    var requesterID: String
    var ownerID: String
    var sessionId: String
    var mode: String
    var createdAt: Double
    var expiresAt: Double
}
struct GymEquipmentOccupancy: Codable, Equatable {
    var ownerID: String
    var members: [String: String]
    var requests: [String: GymWorkInRequest]
    enum CodingKeys: String, CodingKey { case ownerID, members, requests }
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        ownerID = try v.decodeIfPresent(String.self, forKey: .ownerID) ?? ""
        members = try v.decodeIfPresent([String: String].self, forKey: .members) ?? [:]
        requests = try v.decodeIfPresent([String: GymWorkInRequest].self, forKey: .requests) ?? [:]
    }
}
