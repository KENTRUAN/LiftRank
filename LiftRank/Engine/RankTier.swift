import SwiftUI

enum RankTier: Int, CaseIterable, Identifiable, Comparable {
    case wood, bronze, silver, gold, platinum, diamond, champion, titan, olympian

    var id: Int { rawValue }
    static func < (a: RankTier, b: RankTier) -> Bool { a.rawValue < b.rawValue }

    static func tier(for score: Int) -> RankTier {
        switch score {
        case ..<200: .wood
        case ..<300: .bronze
        case ..<400: .silver
        case ..<500: .gold
        case ..<600: .platinum
        case ..<700: .diamond
        case ..<800: .champion
        case ..<900: .titan
        default: .olympian
        }
    }

    var minScore: Int { [1, 200, 300, 400, 500, 600, 700, 800, 900][rawValue] }
    var maxScore: Int { [199, 299, 399, 499, 599, 699, 799, 899, 1000][rawValue] }

    var name: String {
        ["Wood", "Bronze", "Silver", "Gold", "Platinum", "Diamond", "Champion", "Titan", "Olympian"][rawValue]
    }
    var nameZh: String {
        ["木", "青铜", "白银", "黄金", "铂金", "钻石", "冠军", "泰坦", "奥林匹亚"][rawValue]
    }
    var color: Color {
        switch self {
        case .wood: Color(red: 0.55, green: 0.40, blue: 0.26)
        case .bronze: Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver: Color(red: 0.68, green: 0.70, blue: 0.74)
        case .gold: Color(red: 0.95, green: 0.75, blue: 0.15)
        case .platinum: Color(red: 0.35, green: 0.80, blue: 0.80)
        case .diamond: Color(red: 0.40, green: 0.60, blue: 1.00)
        case .champion: Color(red: 0.65, green: 0.35, blue: 0.95)
        case .titan: Color(red: 0.95, green: 0.30, blue: 0.35)
        case .olympian: Color(red: 1.00, green: 0.55, blue: 0.10)
        }
    }
    var icon: String {
        switch self {
        case .wood: "leaf.fill"
        case .bronze, .silver, .gold: "medal.fill"
        case .platinum: "shield.fill"
        case .diamond: "diamond.fill"
        case .champion: "trophy.fill"
        case .titan: "bolt.shield.fill"
        case .olympian: "crown.fill"
        }
    }

    /// League points within the current tier (0–100). Wood spans 199 points and is scaled.
    static func lp(for score: Int) -> Int {
        let t = tier(for: score)
        switch t {
        case .wood: return max(0, min(99, score * 100 / 200))
        case .olympian: return max(0, min(100, score - 900))
        default: return max(0, min(99, score - t.minScore))
        }
    }
}
