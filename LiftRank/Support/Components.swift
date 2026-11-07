import SwiftUI
import UIKit

extension View {
    func formInputStyle() -> some View {
        textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.primary)
    }
}

struct KeyboardDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> WindowObserver {
        let observer = WindowObserver()
        observer.isUserInteractionEnabled = false
        return observer
    }

    func updateUIView(_ view: WindowObserver, context: Context) {}

    final class WindowObserver: UIView, UIGestureRecognizerDelegate {
        private weak var observedWindow: UIWindow?
        private weak var inputAtTouchStart: UIView?

        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observedWindow?.removeGestureRecognizer(tap)
            observedWindow = window
            tap.delegate = self
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            window?.addGestureRecognizer(tap)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            inputAtTouchStart = nil
            var target = touch.view
            while let view = target {
                // Let alerts handle their own buttons before the keyboard moves their layout.
                if view is UITextInput || view.next is UIAlertController { return false }
                target = view.superview
            }

            inputAtTouchStart = window.flatMap { firstResponder(in: $0) }
            return inputAtTouchStart != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func dismissKeyboard() {
            if let input = inputAtTouchStart, input.isFirstResponder {
                input.resignFirstResponder()
            }
        }

        private func firstResponder(in view: UIView) -> UIView? {
            if view.isFirstResponder, view is UITextInput { return view }
            for child in view.subviews {
                if let responder = firstResponder(in: child) { return responder }
            }
            return nil
        }
    }
}

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

    private var selectionLabel: String {
        if let birthday = profile.birthday {
            return birthday.formatted(Date.FormatStyle(date: .long, time: .omitted,
                                                       locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        }
        return profile.hasOnboarded ? "\(String(profile.birthYear)) 年 · 选择日期" : "选择日期"
    }

    var body: some View {
        Button {
            onOpen()
            let existingDate = profile.birthday ?? calendar.date(from: DateComponents(year: profile.birthYear, month: 1, day: 1))
            draft = min(existingDate ?? today, today)
            isPresented = true
        } label: {
            LabeledContent("生日") {
                Text(selectionLabel).foregroundStyle(Color.accentColor)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("生日")
        .accessibilityValue(selectionLabel)
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

/// Avatar with the equipped frame cosmetic; shows the character's head when a spec is given, else the initial.
struct AvatarBadge: View {
    let name: String
    let frame: Cosmetic
    var size: CGFloat = 56
    var spec: AvatarSpec? = nil
    var body: some View {
        ZStack {
            Circle().fill(frame.gradient).frame(width: size, height: size)
            Circle().fill(Color(.secondarySystemGroupedBackground)).frame(width: size - 8, height: size - 8)
            if let spec {
                AvatarFigureView(spec: spec, bust: true, showBackdrop: false)
                    .frame(width: size - 8, height: size - 8)
                    .clipShape(Circle())
            } else {
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(frame.primaryColor)
            }
            if frame.icon != "circle" {
                Image(systemName: frame.icon).font(.system(size: size * 0.24)).foregroundStyle(frame.primaryColor)
                    .offset(x: size * 0.34, y: -size * 0.34)
            }
        }
    }
}

struct TitleTag: View {
    let cosmetic: Cosmetic
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: cosmetic.icon)
            Text(cosmetic.name)
        }
        .font(.caption2.bold())
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(cosmetic.primaryColor.opacity(0.16), in: Capsule())
        .foregroundStyle(cosmetic.primaryColor)
    }
}

struct Toast: ViewModifier {
    @Binding var text: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let text {
                Text(text).font(.subheadline.bold()).padding(12).background(.regularMaterial, in: Capsule()).padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: text)
        .onChange(of: text) { _, value in
            guard let value else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { if text == value { text = nil } }
        }
    }
}
extension View { func toast(_ text: Binding<String?>) -> some View { modifier(Toast(text: text)) } }
