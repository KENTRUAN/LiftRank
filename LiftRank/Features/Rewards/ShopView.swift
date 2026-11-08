import SwiftUI
import SwiftData

/// Buy and equip cosmetics with Eggs. With `slots` limited to the character parts it doubles as the "形象工坊".
struct ShopView: View {
    @Bindable var profile: UserProfile
    let gsr: Int
    let muscles: [MuscleGroup: Int]
    let slots: [CosmeticSlot]
    let title: String
    let previewsRankMascot: Bool
    @Environment(\.modelContext) private var context
    @State private var slot: CosmeticSlot
    @State private var toast: String?
    @State private var front = true

    init(profile: UserProfile, gsr: Int, muscles: [MuscleGroup: Int] = [:], slots: [CosmeticSlot] = CosmeticSlot.allCases,
         title: String = L("商店"), previewsRankMascot: Bool = false) {
        _profile = Bindable(wrappedValue: profile)
        self.gsr = gsr
        self.muscles = muscles
        self.slots = slots
        self.title = title
        self.previewsRankMascot = previewsRankMascot
        _slot = State(initialValue: slots.first ?? .frame)
    }

    private var tier: RankTier { RankTier.tier(for: gsr) }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private func previewsMascot(for slot: CosmeticSlot) -> Bool {
        previewsRankMascot && (slot == .accessory || slot == .backdrop)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(slots) { s in
                            Button { withAnimation { slot = s } } label: {
                                Label(s.name, systemImage: s.icon).font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(slot == s ? Color.accentColor.opacity(0.18) : Color(.secondarySystemGroupedBackground), in: Capsule())
                                    .foregroundStyle(slot == s ? Color.accentColor : .primary)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 2)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(CosmeticCatalog.items(for: slot)) { item in cosmeticCell(item) }
                }

                if slots.contains(.frame) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("连续记录道具").font(.headline)
                        itemRow("Super Restore", price: 100, desc: L("恢复最长 30 天的连续记录"), owned: profile.superRestore) { profile.superRestore += 1 }
                        itemRow("Mega Restore", price: 200, desc: L("恢复最长 60 天的连续记录"), owned: profile.megaRestore) { profile.megaRestore += 1 }
                        itemRow("Streak Revive", price: 400, desc: L("恢复任意长度的连续记录"), owned: profile.streakRevive) { profile.streakRevive += 1 }
                        Text("Eggs 通过每日训练、本周奖励与赛季里程碑获得。虚拟物品不可兑换现金。").font(.caption2).foregroundStyle(.secondary)
                    }.card()
                }
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 14) {
            if previewsMascot(for: slot) {
                RankMascotView(tier: tier, spec: profile.avatar)
                    .frame(width: 110, height: 130)
            } else if slot.isAvatar {
                AvatarFigureView(spec: profile.avatar, muscles: muscles, front: front)
                    .frame(width: 110, height: 170)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { front.toggle() } }
            } else {
                AvatarBadge(name: profile.name, frame: profile.equipped(.frame), size: 64, spec: profile.avatar)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) { Text(profile.name).font(.headline); TitleTag(cosmetic: profile.equipped(.title)) }
                HStack(spacing: 6) { TierBadge(tier: tier, compact: true); Text("GSR \(gsr)").font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 4) { Text("余额").font(.caption).foregroundStyle(.secondary); EggAmount(amount: profile.eggs).font(.subheadline.bold()) }
                if previewsMascot(for: slot) {
                    Text("装备后会显示在段位奶龙上。").font(.caption2).foregroundStyle(.secondary)
                } else if slot.isAvatar {
                    Text(muscles.isEmpty ? "小人的身体会按各肌群段位着色。点击小人翻转。" : "身体颜色 = 各肌群段位。点击小人翻转。").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }.card()
    }

    private func cosmeticCell(_ item: Cosmetic) -> some View {
        let owned = profile.owns(item)
        let equipped = profile.equipped(item.slot) == item
        let locked = item.requiredTier.map { tier < $0 } ?? false
        let previewHeight: CGFloat = item.slot.isAvatar && !item.slot.bustPreview ? 110 : 76
        return VStack(spacing: 8) {
            ZStack {
                if item.slot.isAvatar {
                    RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemGroupedBackground)).frame(height: previewHeight)
                    Group {
                        if previewsMascot(for: item.slot) {
                            RankMascotView(tier: tier, spec: profile.avatar.applying(item))
                        } else {
                            AvatarFigureView(spec: profile.avatar.applying(item), muscles: muscles,
                                             bust: item.slot.bustPreview, showBackdrop: item.slot == .backdrop)
                        }
                    }
                    .frame(height: previewHeight - 8)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(item.gradient).frame(height: previewHeight)
                    if item.slot == .frame {
                        AvatarBadge(name: profile.name, frame: item, size: 48, spec: profile.avatar)
                    } else if item.slot == .title {
                        TitleTag(cosmetic: item).padding(4).background(.regularMaterial, in: Capsule())
                    } else if item.slot == .card {
                        VStack(spacing: 2) {
                            Text("GSR \(gsr)").font(.caption.bold())
                            TierBadge(tier: tier, compact: true)
                        }.padding(6).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "paintbrush.fill").font(.title2).foregroundStyle(.white)
                    }
                }
                if locked {
                    RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.35)).frame(height: previewHeight)
                    Image(systemName: "lock.fill").foregroundStyle(.white)
                }
            }
            VStack(spacing: 2) {
                Text(item.name).font(.subheadline.bold())
                Text(item.requiredTier.map { L("需 %@ 段位", $0.name) } ?? item.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if equipped {
                Button("已装备") { if item.price > 0 { profile.unequip(item.slot); try? context.save() } }
                    .buttonStyle(.bordered).controlSize(.small).tint(.green).disabled(item.price == 0)
            } else if owned {
                Button("装备") { profile.equip(item); try? context.save() }.buttonStyle(.borderedProminent).controlSize(.small).disabled(locked)
            } else {
                Button { buy(item) } label: { EggAmount(amount: item.price) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(locked || profile.eggs < item.price)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(equipped ? Color.green : .clear, lineWidth: 2))
    }

    private func buy(_ item: Cosmetic) {
        if let t = item.requiredTier, tier < t { toast = L("需要达到 %@ 段位", t.name); return }
        guard profile.eggs >= item.price else { toast = L("Eggs 不足"); return }
        profile.eggs -= item.price
        profile.ownedCosmetics.append(item.id)
        profile.equip(item)
        context.insert(RewardEvent(kind: .shop, xp: 0, eggs: -item.price, note: L("购买外观：%@", item.name)))
        try? context.save()
        toast = L("已购买并装备「%@」", item.name)
    }

    private func itemRow(_ name: String, price: Int, desc: String, owned: Int, buy: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) { Text("\(name) ×\(owned)").font(.subheadline.bold()); Text(desc).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button {
                guard profile.eggs >= price else { toast = L("Eggs 不足"); return }
                profile.eggs -= price
                buy()
                context.insert(RewardEvent(kind: .shop, xp: 0, eggs: -price, note: L("购买 %@", name)))
                try? context.save()
                toast = L("已购买 %@", name)
            } label: { EggAmount(amount: price) }.buttonStyle(.bordered).controlSize(.small).disabled(profile.eggs < price)
        }
    }
}
