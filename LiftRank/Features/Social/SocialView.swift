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
    @Environment(\.modelContext) private var context
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var cardio: [CardioSession]
    @Query(sort: \Friend.gsr, order: .reverse) private var friends: [Friend]
    @State private var pasted = ""
    @State private var message: String?
    @State private var cardImage: Image?

    private var bests: [ExerciseBest] { RankAggregator.exerciseBests(workouts: workouts, exercises: exercises, sex: profile.sex) }
    private var muscles: [MuscleGroup: Int] { RankAggregator.muscleScores(bests: bests) }
    private var gsr: Int { RankAggregator.overall(muscleScores: muscles) }
    private var streak: Int { StreakEngine.current(profile: profile, workouts: workouts, cardio: cardio).currentDays }
    private var myCode: RankCode { RankCode.make(profile: profile, gsr: gsr, muscles: muscles, streak: streak) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RankCardView(name: profile.name, gsr: gsr, muscles: muscles, streak: streak, cosmetics: profile.sharedCosmeticIDs)
                HStack {
                    if let cardImage {
                        ShareLink(item: cardImage, preview: SharePreview("\(profile.name) 的段位卡", image: cardImage)) {
                            Label("分享段位卡", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                    }
                    ShareLink(item: myCode.encode()) { Label("分享段位码", systemImage: "qrcode").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("我的段位码").font(.headline)
                    HStack(alignment: .top, spacing: 12) {
                        if let qr = QRCode.image(for: myCode.encode()) {
                            Image(uiImage: qr).interpolation(.none).resizable().frame(width: 110, height: 110)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("把段位码发给好友，对方在下方粘贴即可把你加入排行榜；段位码包含昵称、GSR、肌群评分与外观，不包含训练明细。").font(.caption).foregroundStyle(.secondary)
                            Button { UIPasteboard.general.string = myCode.encode(); message = "已复制段位码" } label: { Label("复制", systemImage: "doc.on.doc") }.font(.caption.bold())
                        }
                    }
                }.card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("添加好友").font(.headline)
                    HStack {
                        TextField("粘贴好友的段位码 LR1.…", text: $pasted).textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                        Button("添加") { addFriend() }.buttonStyle(.borderedProminent).disabled(pasted.isEmpty)
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }.card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("好友排行榜").font(.headline)
                    let rows: [(String, String, Int, Int, [String], Bool)] = ([(profile.friendCode, profile.name, gsr, streak, profile.sharedCosmeticIDs, true)] + friends.map { ($0.code, $0.name, $0.gsr, $0.streakDays, $0.cosmetics, false) }).sorted { $0.2 > $1.2 }
                    ForEach(Array(rows.enumerated()), id: \.element.0) { i, r in
                        HStack(spacing: 10) {
                            Text("\(i + 1)").font(.headline.monospacedDigit()).frame(width: 24)
                            AvatarBadge(name: r.1, frame: CosmeticCatalog.item(r.4.first { $0.hasPrefix("frame.") } ?? "") ?? CosmeticCatalog.defaultItem(for: .frame), size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(r.1).font(.subheadline.bold())
                                    if r.5 { Text("我").font(.caption2).padding(.horizontal, 5).background(Color.accentColor.opacity(0.15), in: Capsule()) }
                                    if let t = CosmeticCatalog.item(r.4.first { $0.hasPrefix("title.") } ?? "") { TitleTag(cosmetic: t) }
                                }
                                Text("连续 \(r.3) 天").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(r.2)").font(.headline.monospacedDigit()).foregroundStyle(RankTier.tier(for: r.2).color)
                            TierBadge(tier: RankTier.tier(for: r.2), compact: true)
                        }
                        if !r.5, let f = friends.first(where: { $0.code == r.0 }) {
                            NavigationLink { FriendCompareView(friend: f, myMuscles: muscles, myGSR: gsr) } label: {
                                Text("与 \(f.name) 对比肌群 · 更新于 \(f.updatedAt.shortString)").font(.caption).foregroundStyle(Color.accentColor)
                            }
                            .swipeActions { Button(role: .destructive) { context.delete(f); try? context.save() } label: { Label("删除", systemImage: "trash") } }
                        }
                        Divider()
                    }
                    Text("离线版本：好友数据来自对方分享的段位码，重新粘贴即可更新。实时同步与全球排行榜需要云端账号。").font(.caption2).foregroundStyle(.secondary)
                }.card()
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("好友与段位卡")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: renderCard)
    }

    @MainActor
    private func renderCard() {
        let renderer = ImageRenderer(content: RankCardView(name: profile.name, gsr: gsr, muscles: muscles, streak: streak, cosmetics: profile.sharedCosmeticIDs).frame(width: 360))
        renderer.scale = 3
        if let ui = renderer.uiImage { cardImage = Image(uiImage: ui) }
    }

    private func addFriend() {
        guard let code = RankCode.decode(pasted) else { message = "段位码无效，请检查是否完整。"; return }
        guard code.uid != profile.friendCode else { message = "这是你自己的段位码。"; return }
        let json = (try? JSONEncoder().encode(code.muscles)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        if let existing = friends.first(where: { $0.code == code.uid }) {
            existing.name = code.name; existing.gsr = code.gsr; existing.muscleScoresJSON = json; existing.cosmetics = code.cosmetics; existing.streakDays = code.streak; existing.updatedAt = code.at
            message = "已更新 \(code.name) 的段位"
        } else {
            context.insert(Friend(code: code.uid, name: code.name, gsr: code.gsr, muscleScoresJSON: json, cosmetics: code.cosmetics, streakDays: code.streak, updatedAt: code.at))
            message = "已添加好友 \(code.name)"
        }
        try? context.save()
        pasted = ""
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
