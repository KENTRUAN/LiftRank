import Foundation

/// Settings is the source of truth for every trainer surface and request.
struct TrainerIdentity: Equatable {
    let name: String
    let intro: String
    let avatarIDs: [String]

    init(profile: UserProfile) {
        let configuredName = profile.coachName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = configuredName.isEmpty ? "小段" : String(configuredName.prefix(80))
        intro = String(profile.coachIntro.prefix(1000))
        avatarIDs = profile.coachAvatarIDs
    }

    var requestContext: [String: String] { ["name": name, "intro": intro] }
}
