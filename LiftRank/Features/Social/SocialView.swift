import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins

/// Compact, shareable snapshot of a lifter's rank. Encoded as "LR1.<base64url json>".
struct RankCode: Codable {
    var v = 1
    var uid: String
    var name: String
    var gsr: Int
    var muscles: [String: Int]
    var cosmetics: [String]
    var streak: Int
    var at: Date

    static let prefix = "LR1."

    func encode() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return Self.prefix + data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> RankCode? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix(prefix) else { return nil }
        s = String(s.dropFirst(prefix.count)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s) else { return nil }
        return try? JSONDecoder().decode(RankCode.self, from: data)
    }

    static func make(profile: UserProfile, gsr: Int, muscles: [MuscleGroup: Int], streak: Int) -> RankCode {
        RankCode(uid: profile.friendCode, name: profile.name, gsr: gsr,
                 muscles: Dictionary(uniqueKeysWithValues: muscles.map { ($0.key.rawValue, $0.value) }),
                 cosmetics: profile.sharedCosmeticIDs, streak: streak, at: Date())
    }
}

struct SocialView: View {
    @Bindable var profile: UserProfile
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var cardio: [CardioSession]
    @Query(sort: \Friend.gsr, order: .reverse) private var friends: [Friend]
    @State private var cardImage: Image?
    private var muscles: [MuscleGroup: Int] { RankAggregator.muscleScores(bests: RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex)) }
    private var gsr: Int { RankAggregator.overall(muscleScores: muscles) }
    private var streak: Int { StreakEngine.current(profile: profile, workouts: workouts, cardio: cardio).currentDays }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RankCardView(name: profile.name, gsr: gsr, muscles: muscles, streak: streak, cosmetics: profile.sharedCosmeticIDs)
                if let cardImage {
                    ShareLink(item: cardImage, preview: SharePreview("My LiftRank card", image: cardImage)) {
                        Label("Share rank image", systemImage: "square.and.arrow.up")
                    }.buttonStyle(.borderedProminent)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Meet at your gym").font(.headline)
                    Text("Connect with people checked into the same gym. Your friends and conversations stay in Community → Messages.").foregroundStyle(.secondary)
                    Button("Open friends & messages") { AppState.shared.communitySection = 1; AppState.shared.tab = AppState.communityTab }
                }.card()
                if !friends.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Saved offline rank cards").font(.headline)
                        Text("Previously saved snapshots. These are not live accounts or friendships.").font(.caption).foregroundStyle(.secondary)
                        ForEach(friends) { friend in
                            NavigationLink { FriendCompareView(friend: friend, myMuscles: muscles, myGSR: gsr) } label: {
                                HStack { Text(friend.name); Spacer(); Text("\(friend.gsr) GSR") }
                            }
                        }
                    }.card()
                }
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Rank cards").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let renderer = ImageRenderer(content: RankCardView(name: profile.name, gsr: gsr, muscles: muscles, streak: streak, cosmetics: profile.sharedCosmeticIDs).frame(width: 360))
            renderer.scale = 3
            if let ui = renderer.uiImage { cardImage = Image(uiImage: ui) }
        }
    }
}

struct RankCardView: View {
    let name: String
    let gsr: Int
    let muscles: [MuscleGroup: Int]
    let streak: Int
    let cosmetics: [String]

    private var frame: Cosmetic { CosmeticCatalog.item(cosmetics.first { $0.hasPrefix("frame.") } ?? "") ?? CosmeticCatalog.defaultItem(for: .frame) }
    private var title: Cosmetic { CosmeticCatalog.item(cosmetics.first { $0.hasPrefix("title.") } ?? "") ?? CosmeticCatalog.defaultItem(for: .title) }
    private var card: Cosmetic { CosmeticCatalog.item(cosmetics.first { $0.hasPrefix("card.") } ?? "") ?? CosmeticCatalog.defaultItem(for: .card) }
    private var dark: Bool { card.id != "card.classic" }
    private var tier: RankTier { RankTier.tier(for: gsr) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AvatarBadge(name: name, frame: frame, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.title3.bold()).foregroundStyle(dark ? .white : .primary)
                    TitleTag(cosmetic: title)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(gsr)").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(tier.color)
                    TierBadge(tier: tier)
                }
            }
            HStack(spacing: 8) {
                ForEach(muscles.sorted { $0.value > $1.value }.prefix(4), id: \.key) { g, v in
                    VStack(spacing: 2) {
                        Text(g.name).font(.caption2).foregroundStyle(dark ? .white.opacity(0.8) : .secondary)
                        Text("\(v)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(RankTier.tier(for: v).color)
                    }.frame(maxWidth: .infinity).padding(6).background((dark ? Color.white : Color.black).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack {
                Label("连续 \(streak) 天", systemImage: "flame.fill").font(.caption).foregroundStyle(.orange)
                Spacer()
                Text("段位健身 · LiftRank").font(.caption2).foregroundStyle(dark ? .white.opacity(0.6) : .secondary)
            }
        }
        .padding(16)
        .background(card.gradient, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(tier.color.opacity(0.5), lineWidth: 1.5))
    }
}

struct FriendCompareView: View {
    let friend: Friend
    let myMuscles: [MuscleGroup: Int]
    let myGSR: Int
    var body: some View {
        List {
            Section("总体") {
                HStack { Text("我"); Spacer(); Text("\(myGSR)").bold(); TierBadge(tier: RankTier.tier(for: myGSR), compact: true) }
                HStack { Text(friend.name); Spacer(); Text("\(friend.gsr)").bold(); TierBadge(tier: RankTier.tier(for: friend.gsr), compact: true) }
            }
            Section("肌群对比") {
                let theirs = friend.muscleScores
                ForEach(MuscleGroup.rankable) { g in
                    let a = myMuscles[g], b = theirs[g]
                    HStack {
                        Text(g.name).frame(width: 60, alignment: .leading)
                        Text(a.map { "\($0)" } ?? "—").monospacedDigit().foregroundStyle((a ?? 0) >= (b ?? 0) ? .green : .primary).frame(width: 50)
                        Spacer()
                        Text(b.map { "\($0)" } ?? "—").monospacedDigit().foregroundStyle((b ?? 0) > (a ?? 0) ? .green : .primary).frame(width: 50)
                    }
                }
            }
        }
        .navigationTitle("与 \(friend.name) 对比")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
