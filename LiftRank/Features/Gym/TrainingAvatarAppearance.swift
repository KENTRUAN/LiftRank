import SwiftUI

/// A portable snapshot of the selected training mascot and its equipped accessory.
/// Rank and cosmetics continue to come from the consent-filtered social profile.
struct TrainingAvatarAppearance: Codable, Equatable {
    static let styleKey = "trainingAvatar.mascotStyle"
    static let placementsKey = "trainingAvatar.mascotAccessoryOffsets"
    var style: String
    var offsetX: Double
    var offsetY: Double
    var rotation: Double
    var scale: Double

    init(style: RankMascotStyle, placement: RankAccessoryPlacement = RankAccessoryPlacement()) {
        self.style = style.rawValue
        offsetX = Self.bounded(Double(placement.offset.width), -1...1, fallback: 0)
        offsetY = Self.bounded(Double(placement.offset.height), -1...1, fallback: 0)
        rotation = placement.rotation.isFinite ? placement.rotation.truncatingRemainder(dividingBy: 360) : 0
        scale = Self.bounded(placement.scale, 0.5...2, fallback: 1)
    }
    var mascotStyle: RankMascotStyle { RankMascotStyle(rawValue: style) ?? .nailong }
    var placement: RankAccessoryPlacement {
        RankAccessoryPlacement(offset: CGSize(width: Self.bounded(offsetX, -1...1, fallback: 0), height: Self.bounded(offsetY, -1...1, fallback: 0)),
                               rotation: Self.bounded(rotation, -360...360, fallback: 0), scale: Self.bounded(scale, 0.5...2, fallback: 1))
    }
    static func current(accessory: String, defaults: UserDefaults = .standard) -> TrainingAvatarAppearance {
        let style = RankMascotStyle(rawValue: defaults.string(forKey: styleKey) ?? "") ?? .nailong
        return snapshot(style: style, accessory: accessory, savedPlacements: defaults.data(forKey: placementsKey) ?? Data())
    }
    static func snapshot(style: RankMascotStyle, accessory: String, savedPlacements: Data) -> TrainingAvatarAppearance {
        let key = style == .nailong ? accessory : "\(style.rawValue).\(accessory)"
        let decoder = JSONDecoder()
        let placements = (try? decoder.decode([String: RankAccessoryPlacement].self, from: savedPlacements))
            ?? ((try? decoder.decode([String: CGSize].self, from: savedPlacements)) ?? [:]).mapValues { RankAccessoryPlacement(offset: $0) }
        return TrainingAvatarAppearance(style: style, placement: placements[key] ?? RankAccessoryPlacement())
    }
    private static func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

struct SharedTrainingAvatarView: View {
    let profile: SocialProfile
    let appearance: TrainingAvatarAppearance
    var body: some View {
        RankMascotView(tier: RankTier.tier(for: profile.gsr), spec: AvatarSpec(ids: profile.cosmetics),
                       style: appearance.mascotStyle, accessoryPlacement: appearance.placement)
            .accessibilityIdentifier("sharedTrainingAvatar")
    }
}
