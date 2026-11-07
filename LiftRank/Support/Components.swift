import SwiftUI

struct BirthdayField: View {
    @Bindable var profile: UserProfile
    var onOpen: () -> Void = {}
    @State private var isPresented = false
    @State private var draft = Date()

    private let calendar = UserProfile.birthdayCalendar
    private let locale = Locale(identifier: "zh_CN")

    private var today: Date {
        let localDay = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        return calendar.date(from: localDay) ?? Date()
    }

    var body: some View {
        Button {
            onOpen()
            let existingDate = profile.birthday ?? calendar.date(from: DateComponents(year: profile.birthYear, month: 1, day: 1))
            draft = min(existingDate ?? today, today)
            isPresented = true
        } label: {
            LabeledContent("生日") {
                if let birthday = profile.birthday {
                    Text(birthday, format: Date.FormatStyle(date: .long, time: .omitted,
                                                            locale: locale, calendar: calendar, timeZone: calendar.timeZone))
                } else if profile.hasOnboarded {
                    Text("\(String(profile.birthYear)) 年")
                } else {
                    Text("选择日期")
                }
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                ScrollView {
                    DatePicker("生日", selection: $draft, in: ...today, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .environment(\.calendar, calendar)
                        .environment(\.locale, locale)
                        .environment(\.timeZone, calendar.timeZone)
                        .padding(.horizontal)
                }
                .navigationTitle("选择生日")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { isPresented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确定") {
                            profile.birthday = calendar.startOfDay(for: draft)
                            profile.birthYear = calendar.component(.year, from: draft)
                            isPresented = false
                        }
                    }
                }
            }
            .presentationDetents([.height(450), .large])
        }
    }
}

struct TierBadge: View {
    let tier: RankTier
    var compact = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tier.icon)
            if !compact { Text(tier.name) }
        }
        .font(compact ? .caption2.bold() : .caption.bold())
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 4)
        .background(tier.color.opacity(0.18), in: Capsule())
        .foregroundStyle(tier.color)
    }
}

struct ScoreGauge: View {
    let score: Int
    var size: CGFloat = 140
    var tier: RankTier { RankTier.tier(for: score) }
    var body: some View {
        ZStack {
            Circle().stroke(tier.color.opacity(0.2), lineWidth: 12)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1000, score))) / 1000)
                .stroke(tier.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(score)").font(.system(size: size * 0.28, weight: .heavy, design: .rounded))
                Text(tier.name).font(.caption.bold()).foregroundStyle(tier.color)
            }
        }
        .frame(width: size, height: size)
    }
}

struct LPBar: View {
    let score: Int
    var body: some View {
        let tier = RankTier.tier(for: score)
        let lp = RankTier.lp(for: score)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(lp) LP").font(.caption.bold()).foregroundStyle(tier.color)
                Spacer()
                if tier != .olympian {
                    let next = RankTier(rawValue: tier.rawValue + 1)!
                    Text("距 \(next.name) 还差 \(100 - lp) LP").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("已达最高段位").font(.caption).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(tier.color).frame(width: geo.size.width * CGFloat(lp) / 100)
                }
            }
            .frame(height: 8)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var color: Color = .accentColor
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
extension View { func card() -> some View { modifier(CardBackground()) } }

struct EggIcon: View {
    var size: CGFloat = 14
    var body: some View {
        Ellipse()
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.7), Color(red: 0.95, green: 0.75, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Ellipse().stroke(Color(red: 0.8, green: 0.6, blue: 0.2), lineWidth: 1))
            .frame(width: size * 0.8, height: size)
    }
}

struct EggAmount: View {
    let amount: Int
    var signed = false
    var body: some View {
        HStack(spacing: 3) {
            Text(signed && amount > 0 ? "+\(amount)" : "\(amount)")
            EggIcon(size: 12)
        }
    }
}

struct ProLockedNote: View {
    let feature: String
    var body: some View {
        Label("\(feature) 属于 Pro 功能，且需要联网与后端服务。当前版本未接入。", systemImage: "lock.fill")
            .font(.footnote).foregroundStyle(.secondary)
    }
}
