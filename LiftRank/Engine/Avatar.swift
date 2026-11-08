import SwiftUI

// MARK: - Spec

/// Everything needed to draw a character ("小人"): resolved from cosmetic ids such as "hair.spiky" or "outfitColor.red".
struct AvatarSpec: Equatable {
    var skin: Color = AvatarPalette.skin["light"]!
    var hair = "short"
    var hairColor: Color = AvatarPalette.hair["black"]!
    var eyes = "normal"
    var outfit = "tank"
    var outfitColor: Color = AvatarPalette.cloth["gray"]!
    var accessory = "none"
    var accessoryColor: Color = .red
    var backdrop = "none"

    init() {}

    /// Unknown or missing slots keep their defaults.
    init(ids: [String]) {
        for slot in CosmeticSlot.avatarSlots {
            let prefix = slot.rawValue + "."
            guard let id = ids.first(where: { $0.hasPrefix(prefix) }), let item = CosmeticCatalog.item(id) else { continue }
            apply(item)
        }
    }

    mutating func apply(_ item: Cosmetic) {
        let key = item.optionKey
        switch item.slot {
        case .skin: skin = item.primaryColor
        case .hair: hair = key
        case .hairColor: hairColor = item.primaryColor
        case .eyes: eyes = key
        case .outfit: outfit = key
        case .outfitColor: outfitColor = item.primaryColor
        case .accessory: accessory = key; accessoryColor = item.primaryColor
        case .backdrop: backdrop = key
        default: break
        }
    }

    func applying(_ item: Cosmetic) -> AvatarSpec { var s = self; s.apply(item); return s }

    static let defaultCoachIDs = ["skin.fair", "hair.ponytail", "hairColor.blue", "eyes.happy", "outfit.hoodie", "outfitColor.purple", "accessory.headband", "backdrop.gym"]
}

enum AvatarPalette {
    static let skin: [String: Color] = [
        "light": Color(red: 0.98, green: 0.86, blue: 0.74), "fair": Color(red: 0.95, green: 0.79, blue: 0.66),
        "tan": Color(red: 0.86, green: 0.66, blue: 0.48), "olive": Color(red: 0.76, green: 0.58, blue: 0.42),
        "brown": Color(red: 0.60, green: 0.42, blue: 0.28), "dark": Color(red: 0.40, green: 0.27, blue: 0.18),
    ]
    static let hair: [String: Color] = [
        "black": Color(red: 0.12, green: 0.12, blue: 0.14), "brown": Color(red: 0.40, green: 0.26, blue: 0.15),
        "blonde": Color(red: 0.93, green: 0.80, blue: 0.45), "red": Color(red: 0.75, green: 0.25, blue: 0.15),
        "white": Color(red: 0.90, green: 0.90, blue: 0.92), "blue": Color(red: 0.25, green: 0.45, blue: 0.95),
        "pink": Color(red: 0.95, green: 0.45, blue: 0.70), "green": Color(red: 0.25, green: 0.70, blue: 0.45),
        "purple": Color(red: 0.55, green: 0.35, blue: 0.85),
    ]
    static let cloth: [String: Color] = [
        "gray": Color(red: 0.55, green: 0.56, blue: 0.60), "black": Color(red: 0.15, green: 0.15, blue: 0.17),
        "white": Color(red: 0.95, green: 0.95, blue: 0.96), "red": Color(red: 0.85, green: 0.22, blue: 0.22),
        "blue": Color(red: 0.22, green: 0.45, blue: 0.90), "green": Color(red: 0.20, green: 0.65, blue: 0.40),
        "orange": Color(red: 0.95, green: 0.55, blue: 0.15), "purple": Color(red: 0.50, green: 0.30, blue: 0.80),
        "pink": Color(red: 0.95, green: 0.50, blue: 0.70), "gold": Color(red: 0.92, green: 0.72, blue: 0.20),
    ]
    static let gold = Color(red: 0.95, green: 0.78, blue: 0.25)
    static let ink = Color(red: 0.16, green: 0.13, blue: 0.14)
}

// MARK: - View

/// Optional contour changes for the training avatar. Score never changes limb length or pose.
struct AvatarPhysique {
    let build: Double
    let scores: [MuscleGroup: Double]

    func growth(_ group: MuscleGroup) -> CGFloat {
        CGFloat(min(1, max(0, scores[group, default: 0] / 1000)))
    }
}

/// Chibi character drawn with Canvas. Muscle groups with a score are tinted with their tier color.
struct AvatarFigureView: View {
    var spec: AvatarSpec
    var muscles: [MuscleGroup: Int] = [:]
    var front = true
    var bust = false
    var showBackdrop = true
    var physique: AvatarPhysique?

    var body: some View {
        Canvas { ctx, size in
            AvatarPainter(spec: spec, muscles: muscles, front: front, physique: physique).draw(&ctx, size: size, bust: bust, backdrop: showBackdrop)
        }
        .accessibilityLabel(bust ? "头像" : "角色形象")
    }
}

// MARK: - Rank mascot

enum RankMascotStyle: String, CaseIterable {
    case nailong, doubao

    var title: String { self == .nailong ? L("奶龙") : L("豆包") }

    func asset(for tier: RankTier) -> String {
        let prefix = self == .nailong ? "RankMascot" : "RankMascotDoubao"
        return prefix + tier.name
    }

    func accessibilityLabel(for tier: RankTier) -> String {
        let rank = AppLanguage.current.isEnglish ? tier.name : tier.nameZh
        return self == .nailong ? L("%@ 奶龙", rank) : L("%@ 豆包", rank)
    }
}

private struct RankAccessoryPlacement: Codable {
    var offset: CGSize = .zero
    var rotation = 0.0
    var scale = 1.0
}

struct RankAccessoryLayout {
    let center: CGPoint
    let bounds: CGSize
    let scale: CGFloat

    init(base: CGSize, scale requestedScale: CGFloat, rotation: Double, center requestedCenter: CGPoint,
         viewport: CGSize, editing: Bool) {
        let angle = rotation * .pi / 180
        let width = abs(base.width * cos(angle)) + abs(base.height * sin(angle))
        let height = abs(base.width * sin(angle)) + abs(base.height * cos(angle))
        let inset: CGFloat = 10
        let handleWidth: CGFloat = editing ? 38 : 0
        let availableWidth = max(0, viewport.width - 2 * inset - handleWidth)
        let availableHeight = max(0, viewport.height - 2 * inset)
        scale = min(requestedScale, availableWidth / max(1, width), availableHeight / max(1, height))
        bounds = CGSize(width: width * scale, height: height * scale)

        let horizontalExtent = max(editing ? 22 : 0, bounds.width / 2)
        let left = min(viewport.width / 2, horizontalExtent + inset)
        let right = min(viewport.width - left, horizontalExtent + handleWidth + inset)
        let vertical = min(viewport.height / 2, max(editing ? 48 : 0, bounds.height / 2 + inset))
        center = CGPoint(x: min(viewport.width - right, max(left, requestedCenter.x)),
                         y: min(viewport.height - vertical, max(vertical, requestedCenter.y)))
    }
}

struct RankMascotView: View {
    private enum Edit { case move, rotate, resize }

    let tier: RankTier
    let spec: AvatarSpec
    let style: RankMascotStyle
    var allowsAccessoryPlacement = false
    @AppStorage("trainingAvatar.mascotAccessoryOffsets") private var savedPlacements = Data()
    @GestureState private var draft: RankAccessoryPlacement?
    @State private var selected = false

    private var placements: [String: RankAccessoryPlacement] {
        let decoder = JSONDecoder()
        if let saved = try? decoder.decode([String: RankAccessoryPlacement].self, from: savedPlacements) {
            return saved
        }
        let previousOffsets = (try? decoder.decode([String: CGSize].self, from: savedPlacements)) ?? [:]
        return previousOffsets.mapValues { RankAccessoryPlacement(offset: $0) }
    }

    private var placementKey: String {
        style == .nailong ? spec.accessory : "\(style.rawValue).\(spec.accessory)"
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let side = min(size.width, size.height) * 0.91
            ZStack {
                Canvas { context, size in
                    AvatarPainter(spec: spec, muscles: [:], front: true, physique: nil).drawBackdrop(&context, size: size)
                }
                .contentShape(Rectangle())
                .onTapGesture { selected = false }
                .accessibilityHidden(true)

                Image(style.asset(for: tier))
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)
                    .accessibilityLabel(style.accessibilityLabel(for: tier))
                    .accessibilityIdentifier("rankMascot")

                if spec.accessory != "none" {
                    let saved = placements[placementKey] ?? RankAccessoryPlacement()
                    let placement = draft ?? saved
                    let layout = accessoryLayout(placement, side: side, in: size)
                    if allowsAccessoryPlacement {
                        editor(placement, layout: layout, saved: saved, side: side, in: size)
                            .position(layout.center)
                    } else {
                        transformedAccessory(placement, scale: layout.scale, side: side)
                            .position(layout.center)
                            .allowsHitTesting(false)
                    }
                }
            }
            .coordinateSpace(name: "rankAccessoryPreview")
        }
        .onChange(of: placementKey) { _, _ in selected = false }
    }

    private func editor(_ placement: RankAccessoryPlacement, layout: RankAccessoryLayout, saved: RankAccessoryPlacement,
                        side: CGFloat, in size: CGSize) -> some View {
        let bounds = layout.bounds
        return transformedAccessory(placement, scale: layout.scale, side: side)
            .frame(width: max(44, bounds.width), height: max(44, bounds.height))
            .contentShape(Rectangle())
            .onTapGesture { selected = true }
            .highPriorityGesture(editGesture(.move, saved: saved, side: side, in: size), including: selected ? .all : .subviews)
            .accessibilityAction { selected = true }
            .accessibilityAction(named: "重置配饰") { save(RankAccessoryPlacement()) }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                        .frame(width: bounds.width + 8, height: bounds.height + 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .trailing) {
                if selected {
                    VStack(spacing: 4) {
                        Button {
                            var rotated = saved
                            rotated.rotation += 15
                            save(rotated)
                        } label: {
                            handle("arrow.clockwise")
                        }
                        .accessibilityLabel("旋转配饰")
                        .highPriorityGesture(editGesture(.rotate, saved: saved, side: side, in: size))

                        handle("arrow.up.left.and.arrow.down.right")
                            .accessibilityLabel("调整配饰大小")
                            .accessibilityValue("\(Int(layout.scale * 100))%")
                            .accessibilityAdjustableAction { direction in
                                var resized = saved
                                resized.scale = layout.scale
                                switch direction {
                                case .increment: resized.scale += 0.1
                                case .decrement: resized.scale -= 0.1
                                @unknown default: return
                                }
                                resized.scale = min(2, max(0.5, resized.scale))
                                save(resized)
                            }
                            .highPriorityGesture(editGesture(.resize, saved: saved, side: side, in: size))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 20)
                }
            }
    }

    private func handle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 28, height: 28)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1))
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }

    private func transformedAccessory(_ placement: RankAccessoryPlacement, scale: CGFloat, side: CGFloat) -> some View {
        accessoryLayer(side: side)
            .scaleEffect(scale)
            .rotationEffect(.degrees(placement.rotation))
    }

    private func editGesture(_ edit: Edit, saved: RankAccessoryPlacement, side: CGFloat, in size: CGSize) -> some Gesture {
        let layout = accessoryLayout(saved, side: side, in: size)
        return DragGesture(minimumDistance: 3, coordinateSpace: .named("rankAccessoryPreview"))
            .updating($draft) { value, state, _ in
                state = editedPlacement(edit, drag: value, saved: saved, layout: layout, side: side, in: size)
            }
            .onEnded { value in
                save(editedPlacement(edit, drag: value, saved: saved, layout: layout, side: side, in: size))
            }
    }

    private func editedPlacement(_ edit: Edit, drag: DragGesture.Value, saved: RankAccessoryPlacement,
                                 layout: RankAccessoryLayout, side: CGFloat, in size: CGSize) -> RankAccessoryPlacement {
        guard side > 0 else { return saved }
        var placement = saved
        let center = layout.center
        switch edit {
        case .move:
            let anchor = accessoryAnchor(side: side, in: size)
            placement.offset = CGSize(width: (center.x + drag.translation.width - anchor.x) / side,
                                      height: (center.y + drag.translation.height - anchor.y) / side)
        case .rotate:
            let start = atan2(drag.startLocation.y - center.y, drag.startLocation.x - center.x)
            let end = atan2(drag.location.y - center.y, drag.location.x - center.x)
            placement.rotation += (end - start) * 180 / .pi
        case .resize:
            let start = hypot(drag.startLocation.x - center.x, drag.startLocation.y - center.y)
            let end = hypot(drag.location.x - center.x, drag.location.y - center.y)
            placement.scale = min(2, max(0.5, layout.scale * end / max(1, start)))
        }
        let anchor = accessoryAnchor(side: side, in: size)
        let boundedCenter = accessoryLayout(placement, side: side, in: size).center
        placement.offset = CGSize(width: (boundedCenter.x - anchor.x) / side,
                                  height: (boundedCenter.y - anchor.y) / side)
        return placement
    }

    private func accessoryAnchor(side: CGFloat, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: (size.height - side) / 2 + side * accessoryHeight)
    }

    private func accessoryLayout(_ placement: RankAccessoryPlacement, side: CGFloat, in size: CGSize) -> RankAccessoryLayout {
        let anchor = accessoryAnchor(side: side, in: size)
        let center = CGPoint(x: anchor.x + placement.offset.width * side,
                             y: anchor.y + placement.offset.height * side)
        return RankAccessoryLayout(base: CGSize(width: side * accessoryWidth, height: side * accessoryCanvasHeight),
                                   scale: placement.scale, rotation: placement.rotation, center: center,
                                   viewport: size, editing: selected)
    }

    private func save(_ placement: RankAccessoryPlacement) {
        var updated = placements
        var normalized = placement
        normalized.rotation.formTruncatingRemainder(dividingBy: 360)
        updated[placementKey] = normalized
        if let data = try? JSONEncoder().encode(updated) { savedPlacements = data }
    }

    private func accessoryLayer(side: CGFloat) -> some View {
        let color = spec.accessoryColor
        return Canvas { context, size in
            let x = size.width * 0.5
            let center = CGPoint(x: x, y: size.height * 0.5)
            func band(_ point: CGPoint, width: CGFloat, height: CGFloat, color: Color) {
                let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: height * 0.35), with: .color(color))
            }
            func symbol(_ name: String, width: CGFloat, color: Color) {
                var image = context.resolve(Image(systemName: name))
                guard image.size.width > 0, image.size.height > 0 else { return }
                image.shading = .color(color)
                let scale = min(width / image.size.width, size.height * 0.9 / image.size.height)
                let bounds = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                context.draw(image, in: CGRect(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2,
                                               width: bounds.width, height: bounds.height))
            }
            switch spec.accessory {
            case "headband":
                band(center, width: side * (style == .doubao ? 0.15 : 0.18), height: side * 0.027, color: color)
            case "wristbands":
                let distance = size.width / 2 - side * 0.035
                for direction in [-1.0, 1.0] {
                    band(CGPoint(x: x + direction * distance, y: center.y), width: side * 0.07, height: side * 0.023, color: color)
                }
            case "glasses": symbol("eyeglasses", width: side * glassesWidth, color: AvatarPalette.ink)
            case "sunglasses": symbol("sunglasses.fill", width: side * glassesWidth, color: AvatarPalette.ink)
            case "cap": symbol("baseball.cap.fill", width: side * (style == .doubao ? 0.18 : 0.20), color: color)
            case "beard": symbol("mustache.fill", width: side * 0.11, color: spec.hairColor)
            case "crown": symbol("crown.fill", width: side * 0.13, color: AvatarPalette.gold)
            case "halo":
                let rect = CGRect(x: x - side * 0.08, y: center.y - side * 0.016, width: side * 0.16, height: side * 0.032)
                context.stroke(Path(ellipseIn: rect), with: .color(AvatarPalette.gold), lineWidth: side * 0.012)
            default: break
            }
        }
        .frame(width: side * accessoryWidth, height: side * accessoryCanvasHeight)
        .contentShape(Rectangle())
        .accessibilityLabel(CosmeticCatalog.item("accessory.\(spec.accessory)")?.name ?? CosmeticSlot.accessory.name)
    }

    private var accessoryWidth: CGFloat {
        switch spec.accessory {
        case "glasses", "sunglasses": return glassesWidth + 0.02
        case "headband": return style == .doubao ? 0.17 : 0.20
        case "cap": return 0.22
        case "beard": return 0.13
        case "crown": return 0.15
        case "halo": return 0.18
        case "wristbands": break
        default: return 0.18
        }
        if style == .doubao {
            switch tier {
            case .wood, .bronze, .silver, .gold, .platinum: return 0.27
            case .diamond: return 0.30
            case .champion, .titan: return 0.34
            case .olympian: return 0.38
            }
        }
        return tier < .champion ? 0.50 : 0.55
    }

    private var accessoryCanvasHeight: CGFloat {
        switch spec.accessory {
        case "headband", "wristbands", "halo": 0.06
        default: 0.105
        }
    }

    private var glassesWidth: CGFloat { style == .doubao ? 0.13 : 0.18 }

    private var accessoryHeight: CGFloat {
        if style == .doubao {
            switch spec.accessory {
            case "headband": return 0.14
            case "glasses", "sunglasses": return tier >= .champion ? 0.17 : 0.195
            case "wristbands": return 0.55
            default: break
            }
        }
        return switch spec.accessory {
        case "headband": 0.11
        case "glasses", "sunglasses": tier >= .titan ? 0.11 : (tier <= .bronze ? 0.17 : 0.14)
        case "beard": 0.25
        case "cap", "crown": 0.07
        case "halo": 0.045
        case "wristbands": 0.59
        default: 0.05
        }
    }
}

// MARK: - Painter

/// Draws in a 100×180 unit space (x: 0–100, y: −10–182) and scales to the canvas.
struct AvatarPainter {
    let spec: AvatarSpec
    let muscles: [MuscleGroup: Int]
    let front: Bool
    let physique: AvatarPhysique?

    private typealias P = CGPoint

    func draw(_ ctx: inout GraphicsContext, size: CGSize, bust: Bool, backdrop: Bool) {
        if backdrop { drawBackdrop(&ctx, size: size) }
        let unit = bust ? CGRect(x: 18, y: -8, width: 64, height: 74) : CGRect(x: 0, y: -12, width: 100, height: 194)
        let scale = min(size.width / unit.width, size.height / unit.height)
        ctx.translateBy(x: (size.width - unit.width * scale) / 2 - unit.minX * scale,
                        y: (size.height - unit.height * scale) / 2 - unit.minY * scale)
        ctx.scaleBy(x: scale, y: scale)
        hairBack(&ctx)
        if spec.outfit == "hoodie" { fill(&ctx, ellipse(28, 40, 44, 26), spec.outfitColor) }
        legs(&ctx)
        arms(&ctx)
        torso(&ctx)
        outfit(&ctx)
        shoulders(&ctx)
        head(&ctx)
        hairFront(&ctx)
        if front { face(&ctx) }
        accessory(&ctx)
    }

    // MARK: Colors

    private func tint(_ g: MuscleGroup) -> Color { muscles[g].map { RankTier.tier(for: $0).color } ?? spec.skin }
    /// Clothes are translucent when muscle tiers need to show through; otherwise nearly opaque.
    private func cloth(_ base: Double) -> Double { muscles.isEmpty ? min(1, base * 2.4) : base }
    private var outline: Color { spec.skin.darkened(0.42) }

    private func growth(_ group: MuscleGroup) -> CGFloat { physique?.growth(group) ?? 0 }
    private var build: CGFloat { CGFloat(physique?.build ?? 0) }
    private var upperArm: CGFloat { 3.4 * (0.55 * growth(.biceps) + 0.45 * growth(.triceps)) }
    private var shoulderWidth: CGFloat { 2.6 * build + 4.3 * growth(.shoulders) + 1.2 * growth(.traps) }
    private var chestWidth: CGFloat { 1.4 * build + 3.8 * growth(.chest) + 2.0 * growth(.back) }
    private var waistWidth: CGFloat { 2.2 * build + growth(.abs) + growth(.lowerBack) }

    private var torsoShape: Path {
        smooth([(29 - shoulderWidth, 60), (71 + shoulderWidth, 60),
                (69 + chestWidth, 84), (66 + waistWidth, 106),
                (34 - waistWidth, 106), (31 - chestWidth, 84)])
    }

    private func armPoint(_ x: CGFloat, _ y: CGFloat, _ side: Bool) -> P {
        m(P(x: x - shoulderWidth * max(0, (95 - y) / 29), y: y), side)
    }

    // MARK: Layers

    func drawBackdrop(_ ctx: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let path = Path(roundedRect: rect, cornerRadius: min(size.width, size.height) * 0.12)
        let colors: [Color]
        switch spec.backdrop {
        case "gym": colors = [Color(red: 0.30, green: 0.32, blue: 0.38), Color(red: 0.14, green: 0.15, blue: 0.19)]
        case "sunset": colors = [Color(red: 0.98, green: 0.62, blue: 0.30), Color(red: 0.55, green: 0.25, blue: 0.55)]
        case "dojo": colors = [Color(red: 0.93, green: 0.85, blue: 0.70), Color(red: 0.72, green: 0.45, blue: 0.30)]
        case "galaxy": colors = [Color(red: 0.08, green: 0.06, blue: 0.22), Color(red: 0.30, green: 0.10, blue: 0.45)]
        default: return
        }
        ctx.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        switch spec.backdrop {
        case "gym":
            var bar = Path()
            bar.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.9)); bar.addLine(to: CGPoint(x: size.width * 0.88, y: size.height * 0.9))
            ctx.stroke(bar, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: size.height * 0.02, lineCap: .round))
            for x in [0.16, 0.84] {
                ctx.fill(Path(roundedRect: CGRect(x: size.width * x - size.width * 0.03, y: size.height * 0.84, width: size.width * 0.06, height: size.height * 0.12), cornerRadius: 3), with: .color(.white.opacity(0.22)))
            }
        case "galaxy":
            var seed: UInt32 = 7
            for _ in 0..<28 {
                seed = seed &* 1_103_515_245 &+ 12345
                let x = Double((seed >> 8) % 1000) / 1000 * size.width
                seed = seed &* 1_103_515_245 &+ 12345
                let y = Double((seed >> 8) % 1000) / 1000 * size.height
                let r = Double((seed >> 4) % 3) * 0.5 + 0.8
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.7)))
            }
        case "dojo":
            ctx.fill(Path(CGRect(x: 0, y: size.height * 0.78, width: size.width, height: size.height * 0.06)), with: .color(Color(red: 0.55, green: 0.15, blue: 0.12).opacity(0.6)))
        case "sunset":
            ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.6, y: size.height * 0.08, width: size.width * 0.22, height: size.width * 0.22)), with: .color(.yellow.opacity(0.75)))
        default: break
        }
    }

    private func hairBack(_ ctx: inout GraphicsContext) {
        let c = spec.hairColor
        switch spec.hair {
        case "long":
            fill(&ctx, rounded(23, 18, 11, 44, 5), c); fill(&ctx, rounded(66, 18, 11, 44, 5), c)
        case "ponytail":
            if front { limb(&ctx, P(x: 72, y: 20), P(x: 80, y: 58), 9, c) } else { limb(&ctx, P(x: 50, y: 34), P(x: 50, y: 66), 10, c) }
        default: break
        }
    }

    private func legs(_ ctx: inout GraphicsContext) {
        for side in [false, true] {
            let thigh = front ? tint(.quads) : tint(.hamstrings)
            limb(&ctx, m(P(x: 41, y: 110), side), m(P(x: 39, y: 142), side), 15 + build * 0.35 + 1.6 * max(growth(.quads), growth(.hamstrings)), thigh)
            limb(&ctx, m(P(x: 39, y: 142), side), m(P(x: 38, y: 168), side), 11 + 1.1 * growth(.calves), tint(.calves))
            fill(&ctx, ellipse(side ? 54 : 26, 166, 20, 10), AvatarPalette.ink.opacity(0.85), outlined: false)
        }
        if !front {
            fill(&ctx, Path(ellipseIn: CGRect(x: 33, y: 97, width: 17, height: 18)), tint(.glutes))
            fill(&ctx, Path(ellipseIn: CGRect(x: 50, y: 97, width: 17, height: 18)), tint(.glutes))
        }
        ctx.opacity = cloth(0.5)
        fill(&ctx, rounded(32 - growth(.glutes), 104, 36 + 2 * growth(.glutes), 18, 5), spec.outfitColor.darkened(0.25))
        ctx.opacity = 1
    }

    private func arms(_ ctx: inout GraphicsContext) {
        for side in [false, true] {
            limb(&ctx, armPoint(27, 70, side), armPoint(19, 94, side), 11 + upperArm, front ? tint(.biceps) : tint(.triceps))
            limb(&ctx, armPoint(19, 94, side), armPoint(15, 118, side), 9 + 2.3 * growth(.forearms), tint(.forearms))
            fill(&ctx, Path(ellipseIn: CGRect(x: (side ? 100 - 14 : 14) - 5, y: 116, width: 10, height: 10)), spec.skin)
        }
    }

    private func torso(_ ctx: inout GraphicsContext) {
        fill(&ctx, torsoShape, spec.skin)
        if front {
            if physique != nil {
                var definition = Path()
                for side in [false, true] {
                    definition.move(to: m(P(x: 33 - chestWidth / 2, y: 76), side))
                    definition.addQuadCurve(to: m(P(x: 49, y: 76), side),
                                            control: m(P(x: 40, y: 81 + 3 * growth(.chest)), side))
                }
                ctx.stroke(definition, with: .color(outline.opacity(0.18 + 0.6 * growth(.chest))),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            } else {
                fill(&ctx, rounded(33, 64, 17, 16, 6), tint(.chest))
                fill(&ctx, rounded(50, 64, 17, 16, 6), tint(.chest))
                fill(&ctx, rounded(37, 82, 26, 24, 6), tint(.abs))
            }
            var lines = Path()
            lines.move(to: P(x: 50, y: 84)); lines.addLine(to: P(x: 50, y: 104))
            for y in [90.0, 98.0] { lines.move(to: P(x: 40, y: y)); lines.addLine(to: P(x: 60, y: y)) }
            ctx.stroke(lines, with: .color(outline.opacity(physique == nil ? 0.5 : 0.13 + 0.62 * growth(.abs))), lineWidth: 0.9)
        } else {
            fill(&ctx, smooth([(36, 60), (64, 60), (58, 72), (42, 72)]), tint(.traps))
            fill(&ctx, rounded(32, 68, 36, 22, 7), tint(.back))
            fill(&ctx, rounded(38, 90, 24, 14, 5), tint(.lowerBack))
            var spine = Path(); spine.move(to: P(x: 50, y: 70)); spine.addLine(to: P(x: 50, y: 102))
            ctx.stroke(spine, with: .color(outline.opacity(0.5)), lineWidth: 0.9)
        }
    }

    private func shoulders(_ ctx: inout GraphicsContext) {
        for side in [false, true] {
            let c = armPoint(28, 66, side)
            let radius = 9 + 2.5 * growth(.shoulders)
            fill(&ctx, ellipse(c.x - radius, c.y - radius, 2 * radius, 2 * radius), tint(.shoulders))
            if ["tee", "hoodie", "robe", "armor"].contains(spec.outfit) {
                ctx.opacity = cloth(spec.outfit == "armor" ? 0.7 : 0.32)
                fill(&ctx, ellipse(c.x - radius - 1, c.y - radius - 1, 2 * radius + 2, 2 * radius + 2), spec.outfit == "armor" ? spec.outfitColor.darkened(0.2) : spec.outfitColor, outlined: spec.outfit == "armor")
                ctx.opacity = 1
            }
        }
    }

    private func outfit(_ ctx: inout GraphicsContext) {
        let c = spec.outfitColor
        let body = torsoShape
        switch spec.outfit {
        case "tank":
            ctx.opacity = cloth(0.22); fill(&ctx, body, c, outlined: false); ctx.opacity = 1
            fill(&ctx, rounded(36, 59, 7, 12, 3), c, outlined: false); fill(&ctx, rounded(57, 59, 7, 12, 3), c, outlined: false)
            fill(&ctx, rounded(33, 98, 34, 9, 3), c, outlined: false)
        case "tee":
            ctx.opacity = cloth(0.32); fill(&ctx, body, c, outlined: false)
            for side in [false, true] { limb(&ctx, armPoint(27, 70, side), armPoint(23, 82, side), 13 + upperArm, c, outlined: false) }
            ctx.opacity = 1
            if front { ctx.stroke(ellipse(42, 57, 16, 8), with: .color(c.darkened(0.3)), lineWidth: 1) }
        case "hoodie":
            ctx.opacity = cloth(0.36); fill(&ctx, body, c, outlined: false)
            for side in [false, true] {
                limb(&ctx, armPoint(27, 70, side), armPoint(19, 94, side), 13 + upperArm, c, outlined: false)
                limb(&ctx, armPoint(19, 94, side), armPoint(15, 114, side), 11 + 2.3 * growth(.forearms), c, outlined: false)
            }
            ctx.opacity = 1
            if front {
                ctx.stroke(rounded(40, 92, 20, 10, 3), with: .color(c.darkened(0.3)), lineWidth: 1)
                var cords = Path(); cords.move(to: P(x: 46, y: 62)); cords.addLine(to: P(x: 45, y: 76)); cords.move(to: P(x: 54, y: 62)); cords.addLine(to: P(x: 55, y: 76))
                ctx.stroke(cords, with: .color(.white.opacity(0.8)), lineWidth: 1)
            }
        case "robe":
            ctx.opacity = cloth(0.42); fill(&ctx, body, c, outlined: false)
            for side in [false, true] {
                limb(&ctx, armPoint(27, 70, side), armPoint(19, 94, side), 14 + upperArm, c, outlined: false)
                limb(&ctx, armPoint(19, 94, side), armPoint(15, 112, side), 12 + 2.3 * growth(.forearms), c, outlined: false)
            }
            ctx.opacity = 1
            var trim = Path(); trim.move(to: P(x: 50, y: 61)); trim.addLine(to: P(x: 50, y: 105))
            ctx.stroke(trim, with: .color(AvatarPalette.gold), lineWidth: 1.6)
            fill(&ctx, rounded(33, 96, 34, 5, 2), AvatarPalette.gold, outlined: false)
        case "armor":
            ctx.opacity = cloth(0.55); fill(&ctx, body, c.darkened(0.1)); ctx.opacity = 1
            var plates = Path()
            plates.move(to: P(x: 50, y: 62)); plates.addLine(to: P(x: 50, y: 104))
            plates.move(to: P(x: 34, y: 82)); plates.addLine(to: P(x: 66, y: 82))
            ctx.stroke(plates, with: .color(c.darkened(0.45)), lineWidth: 1.2)
            fill(&ctx, smooth([(50, 66), (56, 72), (50, 78), (44, 72)]), AvatarPalette.gold)
        default: break
        }
    }

    private func head(_ ctx: inout GraphicsContext) {
        fill(&ctx, rounded(44, 54, 12, 10, 4), spec.skin)
        fill(&ctx, Path(ellipseIn: CGRect(x: 22, y: 30, width: 9, height: 9)), spec.skin)
        fill(&ctx, Path(ellipseIn: CGRect(x: 69, y: 30, width: 9, height: 9)), spec.skin)
        fill(&ctx, ellipse(26, 6, 48, 52), spec.skin)
    }

    private func hairFront(_ ctx: inout GraphicsContext) {
        let c = spec.hairColor
        if !front {
            switch spec.hair {
            case "none": break
            case "buzz": ctx.opacity = 0.55; fill(&ctx, ellipse(26, 6, 48, 44), c); ctx.opacity = 1
            case "mohawk":
                ctx.opacity = 0.55; fill(&ctx, ellipse(26, 6, 48, 44), c); ctx.opacity = 1
                fill(&ctx, rounded(45, -6, 10, 46, 5), c)
            default: fill(&ctx, ellipse(26, 6, 48, 44), c)
            }
            if spec.hair == "bun" { fill(&ctx, Path(ellipseIn: CGRect(x: 42, y: 0, width: 16, height: 16)), c) }
            if spec.hair == "curly" { curls(&ctx, c) }
            if spec.hair == "spiky" { spikes(&ctx, c) }
            return
        }
        switch spec.hair {
        case "none": return
        case "buzz": ctx.opacity = 0.55; fill(&ctx, ellipse(26, 6, 48, 22), c); ctx.opacity = 1
        case "short":
            fill(&ctx, ellipse(26, 6, 48, 22), c)
            fill(&ctx, rounded(26, 20, 6, 11, 2), c); fill(&ctx, rounded(68, 20, 6, 11, 2), c)
        case "spiky": fill(&ctx, ellipse(26, 6, 48, 22), c); spikes(&ctx, c)
        case "long":
            fill(&ctx, ellipse(26, 6, 48, 22), c)
            fill(&ctx, smooth([(26, 16), (36, 12), (34, 30), (28, 34)]), c); fill(&ctx, smooth([(74, 16), (64, 12), (66, 30), (72, 34)]), c)
        case "bun": fill(&ctx, ellipse(26, 6, 48, 22), c); fill(&ctx, Path(ellipseIn: CGRect(x: 42, y: -4, width: 16, height: 16)), c)
        case "curly": fill(&ctx, ellipse(26, 6, 48, 22), c); curls(&ctx, c)
        case "ponytail": fill(&ctx, ellipse(26, 6, 48, 22), c); fill(&ctx, Path(ellipseIn: CGRect(x: 66, y: 14, width: 10, height: 10)), c)
        case "mohawk":
            ctx.opacity = 0.55; fill(&ctx, ellipse(26, 6, 48, 22), c); ctx.opacity = 1
            fill(&ctx, rounded(45, -6, 10, 30, 5), c)
        default: fill(&ctx, ellipse(26, 6, 48, 22), c)
        }
    }

    private func spikes(_ ctx: inout GraphicsContext, _ c: Color) {
        let spikes: [[(CGFloat, CGFloat)]] = [[(31, 14), (36, -2), (43, 12)], [(43, 11), (50, -8), (57, 11)], [(57, 12), (64, -2), (69, 14)]]
        for pts in spikes {
            fill(&ctx, smooth(pts), c)
        }
    }

    private func curls(_ ctx: inout GraphicsContext, _ c: Color) {
        for (x, y) in [(24, 14), (31, 5), (42, 0), (54, 0), (64, 5), (71, 14)] {
            fill(&ctx, Path(ellipseIn: CGRect(x: x, y: y, width: 14, height: 14)), c)
        }
    }

    private func face(_ ctx: inout GraphicsContext) {
        let ink = AvatarPalette.ink
        func dot(_ x: CGFloat) {
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3.2, y: 32, width: 6.4, height: 6.4)), with: .color(ink))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 0.4, y: 32.6, width: 2, height: 2)), with: .color(.white))
        }
        func hump(_ x: CGFloat) {
            var p = Path(); p.move(to: P(x: x - 3.6, y: 37)); p.addQuadCurve(to: P(x: x + 3.6, y: 37), control: P(x: x, y: 30.5))
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
        }
        switch spec.eyes {
        case "happy": hump(41); hump(59)
        case "cool":
            for x in [41.0, 59.0] { ctx.fill(Path(roundedRect: CGRect(x: x - 4.5, y: 33.5, width: 9, height: 3), cornerRadius: 1.5), with: .color(ink)) }
        case "determined":
            dot(41); dot(59)
            var brows = Path()
            brows.move(to: P(x: 36, y: 28)); brows.addLine(to: P(x: 45, y: 30.5))
            brows.move(to: P(x: 64, y: 28)); brows.addLine(to: P(x: 55, y: 30.5))
            ctx.stroke(brows, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        case "wink": dot(41); hump(59)
        default: dot(41); dot(59)
        }
        var mouth = Path()
        switch spec.eyes {
        case "happy": mouth.move(to: P(x: 44, y: 44)); mouth.addQuadCurve(to: P(x: 56, y: 44), control: P(x: 50, y: 52))
        case "cool": mouth.move(to: P(x: 46, y: 46)); mouth.addLine(to: P(x: 54, y: 46))
        default: mouth.move(to: P(x: 45, y: 45)); mouth.addQuadCurve(to: P(x: 55, y: 45), control: P(x: 50, y: 50))
        }
        ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        if spec.accessory == "beard" { fill(&ctx, rounded(36, 43, 28, 12, 6), spec.hairColor) }
    }

    private func accessory(_ ctx: inout GraphicsContext) {
        let c = spec.accessoryColor
        switch spec.accessory {
        case "headband": fill(&ctx, rounded(26, 23, 48, 5, 1.5), c, outlined: false)
        case "cap":
            fill(&ctx, ellipse(25, 2, 50, 26), c)
            if front { fill(&ctx, rounded(26, 23, 48, 5, 2), c.darkened(0.2)) }
            fill(&ctx, Path(ellipseIn: CGRect(x: 48, y: 0, width: 4, height: 4)), c.darkened(0.3), outlined: false)
        case "glasses" where front:
            var g = Path()
            g.addEllipse(in: CGRect(x: 34, y: 28.5, width: 14, height: 13)); g.addEllipse(in: CGRect(x: 52, y: 28.5, width: 14, height: 13))
            g.move(to: P(x: 48, y: 35)); g.addLine(to: P(x: 52, y: 35))
            ctx.stroke(g, with: .color(AvatarPalette.ink), lineWidth: 1.4)
        case "sunglasses" where front:
            fill(&ctx, rounded(33, 30, 15, 9, 3), AvatarPalette.ink, outlined: false); fill(&ctx, rounded(52, 30, 15, 9, 3), AvatarPalette.ink, outlined: false)
            var b = Path(); b.move(to: P(x: 48, y: 33)); b.addLine(to: P(x: 52, y: 33)); ctx.stroke(b, with: .color(AvatarPalette.ink), lineWidth: 1.6)
        case "wristbands":
            for side in [false, true] {
                let p = m(P(x: 16, y: 113), side)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11)), with: .color(c), lineWidth: 3)
            }
        case "crown":
            fill(&ctx, smooth([(34, 12), (34, -2), (42, 5), (50, -8), (58, 5), (66, -2), (66, 12)]), AvatarPalette.gold)
            for (x, col) in [(42.0, Color.red), (50.0, Color.blue), (58.0, Color.green)] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: 5, width: 3.2, height: 3.2)), with: .color(col))
            }
        case "halo":
            ctx.stroke(ellipse(33, -10, 34, 10), with: .color(AvatarPalette.gold), lineWidth: 2.2)
        default: break
        }
    }

    // MARK: Primitives

    private func m(_ p: CGPoint, _ mirrored: Bool) -> CGPoint { mirrored ? CGPoint(x: 100 - p.x, y: p.y) : p }
    private func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)) }
    private func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path { Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r) }

    private func smooth(_ points: [(CGFloat, CGFloat)]) -> Path {
        let p = points.map { CGPoint(x: $0.0, y: $0.1) }
        var path = Path()
        guard let first = p.first, let last = p.last else { return path }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: mid(last, first))
        for (i, pt) in p.enumerated() { path.addQuadCurve(to: mid(pt, p[(i + 1) % p.count]), control: pt) }
        path.closeSubpath()
        return path
    }

    private func fill(_ ctx: inout GraphicsContext, _ path: Path, _ color: Color, outlined: Bool = true) {
        ctx.fill(path, with: .color(color))
        if outlined { ctx.stroke(path, with: .color(color.darkened(0.42)), lineWidth: 1.1) }
    }

    private func limb(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ width: CGFloat, _ color: Color, outlined: Bool = true) {
        var p = Path(); p.move(to: a); p.addLine(to: b)
        if outlined { ctx.stroke(p, with: .color(color.darkened(0.42)), style: StrokeStyle(lineWidth: width + 2.2, lineCap: .round)) }
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

extension Color {
    func darkened(_ amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return Color(hue: h, saturation: s, brightness: max(0, b * (1 - amount)), opacity: a)
    }
}

// MARK: - Natural-language → avatar

/// Turns a description such as "粉色长发、戴墨镜、穿黑色连帽衫的女生" into cosmetic ids. Works offline; the AI backend refines it when available.
enum AvatarDescriber {
    static let jsonKeys = ["skin", "hair", "hairColor", "eyes", "outfit", "outfitColor", "accessory", "backdrop"]

    /// Allowed values per slot, for prompts.
    static var optionList: String {
        CosmeticSlot.avatarSlots.map { slot in
            "\(slot.rawValue): " + CosmeticCatalog.items(for: slot).map { "\($0.optionKey)(\($0.name))" }.joined(separator: "/")
        }.joined(separator: "\n")
    }

    private static let colorWords: [(String, String)] = [
        ("black", "黑|black"), ("brown", "棕|褐|栗|brown|brunette"), ("blonde", "金|黄|blond|blonde|golden|yellow"), ("red", "红|red|ginger"), ("white", "白|银|white|silver"), ("blue", "蓝|blue"),
        ("pink", "粉|pink"), ("green", "绿|green"), ("purple", "紫|purple|violet"), ("gray", "灰|gray|grey"), ("orange", "橙|橘|orange"),
    ]
    private static let rules: [(CosmeticSlot, String, String)] = [
        // Chinese and English keywords; matching is case-insensitive.
        (.hair, "none", "光头|没有头发|秃|bald|shaved head|no hair"), (.hair, "buzz", "寸头|板寸|平头|buzz ?cut|crew ?cut"), (.hair, "mohawk", "莫西干|鸡冠头|mohawk"), (.hair, "spiky", "刺猬|竖起|炸毛|尖发|spiky|spiked"),
        (.hair, "bun", "丸子|发髻|盘发|\\bbun\\b|top ?knot"), (.hair, "ponytail", "马尾|ponytail|pony ?tail"), (.hair, "curly", "卷发|卷毛|curly|curls|afro"), (.hair, "long", "长发|long hair"), (.hair, "short", "短发|short hair"),
        (.skin, "light", "白皙|皮肤白|肤色浅|pale|fair skin|light skin"), (.skin, "tan", "小麦|古铜|健康肤色|晒黑|tan|tanned|bronze skin"), (.skin, "dark", "黑皮肤|深色皮肤|肤色深|dark skin|black skin"), (.skin, "brown", "棕色皮肤|棕皮|brown skin"),
        (.eyes, "happy", "开心|微笑|笑眯眯|爱笑|可爱|happy|smil|cheerful|cute"), (.eyes, "cool", "冷酷|很酷|酷酷|眯眼|高冷|\\bcool\\b|chill"), (.eyes, "determined", "坚定|认真|严肃|凶|determined|serious|fierce|intense"), (.eyes, "wink", "眨眼|wink|俏皮|playful"),
        (.outfit, "none", "赤膊|不穿上衣|光膀子|裸上身|shirtless|topless|no shirt"), (.outfit, "armor", "盔甲|铠甲|战甲|armou?r"), (.outfit, "robe", "长袍|道袍|斗篷|袍子|robe|cloak|cape"), (.outfit, "hoodie", "连帽|卫衣|hoodie|hooded"),
        (.outfit, "tee", "T恤|t恤|短袖|体恤|t-?shirt|\\btee\\b"), (.outfit, "tank", "背心|tank ?top|singlet|vest"),
        (.accessory, "sunglasses", "墨镜|太阳镜|sunglasses|shades"), (.accessory, "glasses", "眼镜|glasses|spectacles"), (.accessory, "cap", "棒球帽|鸭舌帽|帽子|\\bcap\\b|\\bhat\\b"), (.accessory, "headband", "发带|头带|头巾|headband|bandana"),
        (.accessory, "wristbands", "护腕|wristband|wrist wraps"), (.accessory, "crown", "皇冠|王冠|crown|tiara"), (.accessory, "halo", "光环|天使|halo|angel"), (.accessory, "beard", "胡子|胡须|络腮|beard|stubble|moustache|mustache"),
        (.backdrop, "gym", "健身房|\\bgym\\b"), (.backdrop, "dojo", "道场|武馆|dojo"), (.backdrop, "galaxy", "星空|宇宙|银河|太空|galaxy|space|stars|starry"), (.backdrop, "sunset", "夕阳|日落|黄昏|sunset|dusk"),
    ]

    /// Limit the chat fallback to explicit appearance requests; general chat still needs a backend.
    static func offlineChatLook(_ text: String, base: [String]) -> [String]? {
        let request = "^(请|帮我|能不能|可以|麻烦)*(把|给|让|改|换|染|穿|戴|变|留|剪|弄|设置)|^(please |can you |could you )?(change|make|give|put|wear|dye|set|switch|turn|use|try)"
        let excluded = "不要|别|不用|不想|如果|假如|是否|能否|会不会|可以吗|好不好|don'?t|do not|should i|whether"
        let appearance = "形象|头像|外观|头发|发型|发色|[长短卷]发|马尾|光头|墨镜|眼镜|肤色|皮肤|帽子|衣|连帽|卫衣|T恤|t恤|背心|服装|背景|护腕|发带|胡子|盔甲|hair|glasses|shades|skin|hat|cap|hoodie|shirt|tee|tank|outfit|robe|armou?r|background|backdrop|wristband|headband|beard|crown|halo|look|avatar|appearance"
        guard text.range(of: request, options: [.regularExpression, .caseInsensitive]) != nil,
              text.range(of: excluded, options: [.regularExpression, .caseInsensitive]) == nil,
              text.range(of: appearance, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return parse(text, base: base)
    }

    static func parse(_ text: String, base: [String]) -> [String] {
        var ids = base
        var touched: Set<CosmeticSlot> = []
        for (slot, key, pattern) in rules where !touched.contains(slot) {
            if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { ids = replacing(ids, slot: slot, key: key); touched.insert(slot) }
        }
        let hairTarget = "(头发|发色|长发|短发|卷发|马尾|hair|ponytail|bun|curls)"
        let clothTarget = "(衣服|服装|背心|[Tt]恤|短袖|连帽衫|卫衣|外套|长袍|盔甲|铠甲|上衣|衬衫|hoodie|shirt|tee|tank|top|robe|armou?r|outfit|clothes)"
        for (key, words) in colorWords {
            let color = "(\(words))(色)?"
            let connector = "(改成|染成|换成|变成|调成|设成|弄成|变为|改为|换为|用)"
            // "蓝色的头发" / "头发改成蓝色" / "blue hair" / "pink long hair"
            let hairPattern = "\(color)的?\(hairTarget)|\(hairTarget)\\s*\(connector)\\s*\(color)|\(color)\\s+(\\w+\\s+)?\(hairTarget)"
            if !touched.contains(.hairColor), text.range(of: hairPattern, options: [.regularExpression, .caseInsensitive]) != nil,
               CosmeticCatalog.item("hairColor.\(key)") != nil {
                ids = replacing(ids, slot: .hairColor, key: key); touched.insert(.hairColor)
            }
            let clothKey = key == "blonde" ? "gold" : key
            let clothPattern = "\(color)的?\(clothTarget)|\(clothTarget)\\s*\(connector)\\s*\(color)|\(color)\\s+(\\w+\\s+)?\(clothTarget)"
            if !touched.contains(.outfitColor), text.range(of: clothPattern, options: [.regularExpression, .caseInsensitive]) != nil,
               CosmeticCatalog.item("outfitColor.\(clothKey)") != nil {
                ids = replacing(ids, slot: .outfitColor, key: clothKey); touched.insert(.outfitColor)
            }
        }
        if !touched.contains(.hair) {
            if text.range(of: "女|\\b(girl|woman|female|lady)\\b", options: [.regularExpression, .caseInsensitive]) != nil { ids = replacing(ids, slot: .hair, key: "long") }
            else if text.range(of: "男|\\b(boy|man|male|guy|dude)\\b", options: [.regularExpression, .caseInsensitive]) != nil { ids = replacing(ids, slot: .hair, key: "short") }
        }
        return ids
    }

    static func name(in text: String) -> String? {
        if let r = text.range(of: "(叫|名字是|名为|名叫|称呼)([\\p{Han}A-Za-z0-9]{1,8})", options: .regularExpression) {
            let match = String(text[r])
            for p in ["名字是", "名为", "名叫", "称呼", "叫"] where match.hasPrefix(p) { return String(match.dropFirst(p.count)) }
        }
        // "named Max" / "called Nova" / "her name is Lily"
        if let r = text.range(of: "(?:named|called|name is)\\s+([A-Za-z][A-Za-z0-9]{0,11})", options: [.regularExpression, .caseInsensitive]) {
            return text[r].split(separator: " ").last.map(String.init)
        }
        return nil
    }

    /// Applies a JSON object produced by the model ({"hair":"spiky", ...}) on top of existing ids.
    static func ids(from json: [String: Any], base: [String]) -> [String] {
        var ids = base
        for slot in CosmeticSlot.avatarSlots {
            guard let key = json[slot.rawValue] as? String, CosmeticCatalog.item("\(slot.rawValue).\(key)") != nil else { continue }
            ids = replacing(ids, slot: slot, key: key)
        }
        return ids
    }

    static func replacing(_ ids: [String], slot: CosmeticSlot, key: String) -> [String] {
        var out = ids.filter { !$0.hasPrefix(slot.rawValue + ".") }
        out.append("\(slot.rawValue).\(key)")
        return out
    }

    /// Offline parse first, then the AI backend (when configured) refines the result.
    static func describe(_ text: String, base: [String]) async -> (ids: [String], name: String?, usedAI: Bool) {
        var ids = parse(text, base: base)
        var name = name(in: text)
        guard let config = AIBackend.config else { return (ids, name, false) }
        let system = """
        你负责把用户对一个卡通健身助手外观的描述转换成 JSON。只输出一个 JSON 对象，不要其他文字。
        字段：name（可选，助手名字，用户没提就省略）以及以下字段，值必须从给定选项里选，用户没提到的字段省略：
        \(optionList)
        """
        if let reply = try? await AIService.complete(system: system, messages: [AIChatMessage(role: .user, text: text)], config: config, maxTokens: 400),
           let obj = AIJSON.extractObject(from: reply) {
            ids = self.ids(from: obj, base: ids)
            if let n = obj["name"] as? String, !n.isEmpty { name = n }
            return (ids, name, true)
        }
        return (ids, name, false)
    }
}
