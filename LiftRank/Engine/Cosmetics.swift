import SwiftUI

/// Where a cosmetic ("外观") is shown once equipped.
enum CosmeticSlot: String, CaseIterable, Identifiable {
    case frame, title, theme, card
    var id: String { rawValue }
    var name: String {
        switch self {
        case .frame: "头像框"
        case .title: "称号"
        case .theme: "主题色"
        case .card: "段位卡"
        }
    }
    var icon: String {
        switch self {
        case .frame: "person.crop.circle.badge.checkmark"
        case .title: "text.badge.star"
        case .theme: "paintpalette.fill"
        case .card: "rectangle.portrait.on.rectangle.portrait.angled.fill"
        }
    }
}

struct Cosmetic: Identifiable, Hashable {
    let id: String
    let slot: CosmeticSlot
    let name: String
    let detail: String
    let price: Int
    /// Current GSR tier needed to buy and keep this equipped; links the shop to the rank system.
    let requiredTier: RankTier?
    let colors: [Color]
    let icon: String

    static func == (a: Cosmetic, b: Cosmetic) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    var primaryColor: Color { colors.first ?? .accentColor }
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

enum CosmeticCatalog {
    static let all: [Cosmetic] = [
        // Avatar frames
        Cosmetic(id: "frame.wood", slot: .frame, name: "木纹框", detail: "初始头像框", price: 0, requiredTier: nil, colors: [RankTier.wood.color], icon: "circle"),
        Cosmetic(id: "frame.bronze", slot: .frame, name: "青铜框", detail: "达到 Bronze 后可购买", price: 40, requiredTier: .bronze, colors: [RankTier.bronze.color, .orange], icon: "circle"),
        Cosmetic(id: "frame.silver", slot: .frame, name: "白银框", detail: "达到 Silver 后可购买", price: 80, requiredTier: .silver, colors: [RankTier.silver.color, .white], icon: "circle"),
        Cosmetic(id: "frame.gold", slot: .frame, name: "黄金框", detail: "达到 Gold 后可购买", price: 150, requiredTier: .gold, colors: [RankTier.gold.color, .yellow], icon: "circle"),
        Cosmetic(id: "frame.platinum", slot: .frame, name: "铂金框", detail: "达到 Platinum 后可购买", price: 240, requiredTier: .platinum, colors: [RankTier.platinum.color, .mint], icon: "circle"),
        Cosmetic(id: "frame.diamond", slot: .frame, name: "钻石框", detail: "达到 Diamond 后可购买", price: 360, requiredTier: .diamond, colors: [RankTier.diamond.color, .cyan], icon: "circle"),
        Cosmetic(id: "frame.champion", slot: .frame, name: "冠军框", detail: "达到 Champion 后可购买", price: 520, requiredTier: .champion, colors: [RankTier.champion.color, .pink], icon: "circle"),
        Cosmetic(id: "frame.flame", slot: .frame, name: "烈焰框", detail: "连续训练的象征", price: 200, requiredTier: nil, colors: [.red, .orange, .yellow], icon: "flame.fill"),
        // Titles
        Cosmetic(id: "title.rookie", slot: .title, name: "新手上路", detail: "初始称号", price: 0, requiredTier: nil, colors: [.gray], icon: "leaf.fill"),
        Cosmetic(id: "title.iron", slot: .title, name: "铁人", detail: "每天都来", price: 60, requiredTier: nil, colors: [.gray], icon: "figure.strengthtraining.traditional"),
        Cosmetic(id: "title.squat", slot: .title, name: "深蹲机器", detail: "腿日从不缺席", price: 90, requiredTier: .silver, colors: [.green], icon: "figure.cross.training"),
        Cosmetic(id: "title.bench", slot: .title, name: "卧推狂人", detail: "胸日最爱", price: 90, requiredTier: .silver, colors: [.blue], icon: "dumbbell.fill"),
        Cosmetic(id: "title.deadlift", slot: .title, name: "硬拉之王", detail: "拉起一切", price: 120, requiredTier: .gold, colors: [.purple], icon: "bolt.fill"),
        Cosmetic(id: "title.titan", slot: .title, name: "泰坦之躯", detail: "达到 Titan 后可购买", price: 400, requiredTier: .titan, colors: [RankTier.titan.color], icon: "bolt.shield.fill"),
        // Accent themes
        Cosmetic(id: "theme.orange", slot: .theme, name: "活力橙", detail: "默认主题色", price: 0, requiredTier: nil, colors: [.orange], icon: "paintpalette.fill"),
        Cosmetic(id: "theme.blue", slot: .theme, name: "深海蓝", detail: "冷静专注", price: 50, requiredTier: nil, colors: [.blue], icon: "paintpalette.fill"),
        Cosmetic(id: "theme.green", slot: .theme, name: "森林绿", detail: "自然放松", price: 50, requiredTier: nil, colors: [.green], icon: "paintpalette.fill"),
        Cosmetic(id: "theme.purple", slot: .theme, name: "暗夜紫", detail: "达到 Gold 后可购买", price: 120, requiredTier: .gold, colors: [.purple], icon: "paintpalette.fill"),
        Cosmetic(id: "theme.red", slot: .theme, name: "熔岩红", detail: "达到 Platinum 后可购买", price: 160, requiredTier: .platinum, colors: [.red], icon: "paintpalette.fill"),
        // Rank card styles
        Cosmetic(id: "card.classic", slot: .card, name: "经典卡", detail: "默认段位卡", price: 0, requiredTier: nil, colors: [Color(.systemGray6), Color(.systemGray4)], icon: "rectangle.fill"),
        Cosmetic(id: "card.night", slot: .card, name: "暗夜卡", detail: "深色分享卡", price: 80, requiredTier: nil, colors: [Color(red: 0.1, green: 0.1, blue: 0.16), Color(red: 0.2, green: 0.2, blue: 0.3)], icon: "moon.stars.fill"),
        Cosmetic(id: "card.neon", slot: .card, name: "霓虹卡", detail: "达到 Diamond 后可购买", price: 300, requiredTier: .diamond, colors: [Color(red: 0.05, green: 0.05, blue: 0.2), .purple, .cyan], icon: "sparkles"),
        Cosmetic(id: "card.gold", slot: .card, name: "鎏金卡", detail: "达到 Champion 后可购买", price: 450, requiredTier: .champion, colors: [Color(red: 0.35, green: 0.25, blue: 0.05), RankTier.gold.color], icon: "crown.fill"),
    ]

    static func item(_ id: String) -> Cosmetic? { all.first { $0.id == id } }
    static func defaultItem(for slot: CosmeticSlot) -> Cosmetic { all.first { $0.slot == slot && $0.price == 0 }! }
    static func items(for slot: CosmeticSlot) -> [Cosmetic] { all.filter { $0.slot == slot } }
}

extension UserProfile {
    func owns(_ cosmetic: Cosmetic) -> Bool { cosmetic.price == 0 || ownedCosmetics.contains(cosmetic.id) }

    func equipped(_ slot: CosmeticSlot) -> Cosmetic {
        let prefix = slot.rawValue + ":"
        if let entry = equippedCosmetics.first(where: { $0.hasPrefix(prefix) }),
           let item = CosmeticCatalog.item(String(entry.dropFirst(prefix.count))), owns(item) {
            return item
        }
        return CosmeticCatalog.defaultItem(for: slot)
    }

    func equip(_ cosmetic: Cosmetic) {
        guard owns(cosmetic) else { return }
        equippedCosmetics.removeAll { $0.hasPrefix(cosmetic.slot.rawValue + ":") }
        equippedCosmetics.append("\(cosmetic.slot.rawValue):\(cosmetic.id)")
    }

    func unequip(_ slot: CosmeticSlot) {
        equippedCosmetics.removeAll { $0.hasPrefix(slot.rawValue + ":") }
    }

    var accentColor: Color { equipped(.theme).primaryColor }
    var titleName: String { equipped(.title).name }
    /// Equipped cosmetic ids shared with friends through the rank code.
    var sharedCosmeticIDs: [String] { CosmeticSlot.allCases.map { equipped($0).id } }
}
