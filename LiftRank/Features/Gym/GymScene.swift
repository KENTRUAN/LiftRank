import SpriteKit
import SwiftUI

@MainActor
final class GymScene: SKScene {
    var onMove: ((Double, Double) -> Void)?
    var onProfile: ((String) -> Void)?
    var onTrainer: (() -> Void)?
    var onStation: ((String) -> Void)?
    private var people: [String: SKNode] = [:]
    private var appearances: [String: String] = [:]
    private var completionTimes: [String: Double] = [:]
    private var localID = ""
    private var localPosition = CGPoint(x: 2, y: 7)
    private var route: [GymLayout.Cell] = []
    private var lastTime: TimeInterval = 0
    private var trainer: SKNode?
    private let world = SKNode()
    private let roomCamera = SKCameraNode()
    private var zoomLevel: CGFloat = 1
    private var viewportSize = CGSize.zero
    private(set) var plainSpace = false

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.055, green: 0.08, blue: 0.13, alpha: 1)
        addChild(world)
        addChild(roomCamera); camera = roomCamera
        roomCamera.position = CGPoint(x: 390, y: 305)
        buildRoom()
    }
    required init?(coder aDecoder: NSCoder) { fatalError("Use init(size:)") }
    override func didChangeSize(_ oldSize: CGSize) { fitViewport(size) }
    func fitViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0, viewportSize != size else { return }
        viewportSize = size
        roomCamera.setScale(GymCamera.fitScale(size) / zoomLevel)
    }
    func zoom(by factor: CGFloat, around anchor: CGPoint? = nil) {
        guard factor.isFinite, factor > 0 else { return }
        let before = anchor.map { convertPoint(fromView: $0) }
        zoomLevel = GymCamera.zoom(zoomLevel * factor)
        roomCamera.setScale(GymCamera.fitScale(viewportSize) / zoomLevel)
        if let anchor, let before {
            let after = convertPoint(fromView: anchor)
            roomCamera.position.x += before.x - after.x; roomCamera.position.y += before.y - after.y
        }
        clampCamera()
    }
    func pan(by translation: CGPoint) {
        roomCamera.position.x -= translation.x * roomCamera.xScale
        roomCamera.position.y += translation.y * roomCamera.yScale
        clampCamera()
    }
    func resetCamera() {
        zoomLevel = 1; roomCamera.position = CGPoint(x: 390, y: 305)
        roomCamera.setScale(GymCamera.fitScale(viewportSize))
    }
    private func clampCamera() {
        roomCamera.position.x = min(650, max(130, roomCamera.position.x))
        roomCamera.position.y = min(500, max(110, roomCamera.position.y))
    }
    func configure(plain: Bool) {
        guard plainSpace != plain else { return }
        plainSpace = plain; cancelMovement()
        for node in world.children where node.name?.hasPrefix("station:") == true { node.isHidden = plain }
        (childNode(withName: "roomHeading") as? SKLabelNode)?.text = plain ? L("YOUR WORKOUT SPACE") : L("LIFT / SOCIAL CLUB")
        (childNode(withName: "roomHint") as? SKLabelNode)?.text = plain ? L("Tap to walk · Choose any workout below") : L("Tap equipment to train · Tap a lifter to connect")
    }
    private func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: 370 + (x - y) * 30, y: 470 - (x + y) * 16) }
    private func cell(at p: CGPoint) -> GymLayout.Cell {
        let a = (p.x - 370) / 30, b = (470 - p.y) / 16
        return GymLayout.Cell(x: Int(((a + b) / 2).rounded()), y: Int(((b - a) / 2).rounded()))
    }
    private func polygon(_ vertices: [CGPoint], fill: UIColor, stroke: UIColor = .clear) -> SKShapeNode {
        let path = CGMutablePath(); path.addLines(between: vertices); path.closeSubpath()
        let node = SKShapeNode(path: path); node.fillColor = fill; node.strokeColor = stroke; node.lineWidth = 1
        return node
    }
    private func label(_ text: String, size: CGFloat, color: UIColor = .white) -> SKLabelNode {
        let node = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        node.text = text; node.fontSize = size; node.fontColor = color; node.verticalAlignmentMode = .center
        return node
    }
    private func buildRoom() {
        let title = label(L("LIFT / SOCIAL CLUB"), size: 20, color: .white)
        title.name = "roomHeading"
        title.position = CGPoint(x: 390, y: 555); addChild(title)
        let subtitle = label(L("YOUR PEOPLE. YOUR PACE."), size: 10, color: .systemMint)
        subtitle.position = CGPoint(x: 390, y: 529); addChild(subtitle)
        for x in 0..<GymLayout.width {
            for y in 0..<GymLayout.height {
                let p = point(Double(x), Double(y))
                let tint = (x + y) % 2 == 0 ? UIColor(white: 0.18, alpha: 1) : UIColor(white: 0.21, alpha: 1)
                let tile = polygon([CGPoint(x: p.x, y: p.y + 16), CGPoint(x: p.x + 30, y: p.y), CGPoint(x: p.x, y: p.y - 16), CGPoint(x: p.x - 30, y: p.y)], fill: tint, stroke: UIColor.white.withAlphaComponent(0.05))
                tile.zPosition = -100; world.addChild(tile)
            }
        }
        for (start, end) in [(point(-0.5, -0.5), point(11.5, -0.5)), (point(-0.5, -0.5), point(-0.5, 9.5))] {
            let wall = polygon([start, end, CGPoint(x: end.x, y: end.y + 45), CGPoint(x: start.x, y: start.y + 45)], fill: UIColor(red: 0.12, green: 0.17, blue: 0.23, alpha: 1), stroke: .darkGray)
            wall.zPosition = -90; world.addChild(wall)
            let neon = SKShapeNode(); let line = CGMutablePath()
            line.move(to: CGPoint(x: start.x, y: start.y + 44)); line.addLine(to: CGPoint(x: end.x, y: end.y + 44))
            neon.path = line; neon.strokeColor = .systemMint; neon.lineWidth = 2; neon.glowWidth = 3; neon.zPosition = -89; world.addChild(neon)
        }
        equipment("rack", x: 1, y: 1, color: .systemCyan)
        equipment("bench", x: 4, y: 2, color: .systemOrange)
        equipment("cardio", x: 8, y: 1, color: .systemMint)
        equipment("platform", x: 8, y: 5, color: .systemPurple)
        equipment("lounge", x: 1, y: 8, color: .systemIndigo)
        let helper = label(L("Tap equipment to train · Tap a lifter to connect"), size: 12, color: .lightGray)
        helper.name = "roomHint"
        helper.position = CGPoint(x: 390, y: 91); addChild(helper)
        let coach = makePerson(profile: SocialProfile(uid: "trainer", name: L("AI trainer"), gsr: 0, cosmetics: [], interests: "", avatar: AvatarAppearance(preset: "star", color: "green")), portrait: nil)
        coach.name = "trainer"; coach.position = point(4, 7); coach.zPosition = 30
        world.addChild(coach); trainer = coach
    }
    private func equipment(_ kind: String, x: Double, y: Double, color: UIColor) {
        let node = SKNode(); node.position = point(x, y); node.name = "station:\(kind)"; node.zPosition = CGFloat(x + y)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 70, height: 28)); shadow.fillColor = .black.withAlphaComponent(0.4); shadow.strokeColor = .clear; node.addChild(shadow)
        let base = polygon([CGPoint(x: -20, y: 4), CGPoint(x: 15, y: 22), CGPoint(x: 50, y: 4), CGPoint(x: 15, y: -14)], fill: color.withAlphaComponent(0.7), stroke: color)
        node.addChild(base)
        switch kind {
        case "rack":
            for x in [-14.0, 40.0] {
                let bar = SKShapeNode(rectOf: CGSize(width: 5, height: 53), cornerRadius: 2); bar.position = CGPoint(x: x, y: 24); bar.fillColor = .lightGray; bar.strokeColor = .clear; node.addChild(bar)
            }
            let weight = SKShapeNode(rectOf: CGSize(width: 70, height: 5), cornerRadius: 2); weight.position = CGPoint(x: 13, y: 42); weight.fillColor = .white; node.addChild(weight)
        case "bench":
            let pad = SKShapeNode(rectOf: CGSize(width: 58, height: 16), cornerRadius: 5); pad.fillColor = color; pad.strokeColor = .clear; pad.zRotation = -0.45; pad.position = CGPoint(x: 14, y: 14); node.addChild(pad)
            let bar = SKShapeNode(rectOf: CGSize(width: 66, height: 4)); bar.position = CGPoint(x: 12, y: 33); bar.fillColor = .white; node.addChild(bar)
            for x in [-17.0, 40.0] { let plate = SKShapeNode(rectOf: CGSize(width: 7, height: 19), cornerRadius: 2); plate.fillColor = .darkGray; plate.position = CGPoint(x: x, y: 33); node.addChild(plate) }
        case "cardio":
            for x in [0.0, 25.0] { let rail = SKShapeNode(rectOf: CGSize(width: 4, height: 34)); rail.position = CGPoint(x: x, y: 23); rail.fillColor = .lightGray; node.addChild(rail) }
            let screen = SKShapeNode(rectOf: CGSize(width: 32, height: 17), cornerRadius: 3); screen.fillColor = .black; screen.strokeColor = color; screen.position = CGPoint(x: 13, y: 42); node.addChild(screen)
        case "lounge":
            let seat = SKShapeNode(rectOf: CGSize(width: 62, height: 23), cornerRadius: 8); seat.fillColor = color; seat.position = CGPoint(x: 13, y: 15); node.addChild(seat)
        default:
            let bar = SKShapeNode(rectOf: CGSize(width: 60, height: 5)); bar.fillColor = .lightGray; bar.position = CGPoint(x: 14, y: 14); node.addChild(bar)
            for x in [-10.0, 38.0] { let plate = SKShapeNode(circleOfRadius: 9); plate.fillColor = .darkGray; plate.strokeColor = color; plate.position = CGPoint(x: x, y: 14); node.addChild(plate) }
        }
        let caption = label(kind.uppercased(), size: 9, color: color); caption.position = CGPoint(x: 15, y: -26); node.addChild(caption)
        world.addChild(node)
    }
    private func makePerson(profile: SocialProfile, portrait: UIImage?) -> SKNode {
        let node = SKNode(); node.name = "avatar:\(profile.uid)"
        let color = UIColor(profile.avatar.tint)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 30, height: 12)); shadow.fillColor = .black.withAlphaComponent(0.4); shadow.strokeColor = .clear; node.addChild(shadow)
        for x in [-5.0, 5.0] {
            let leg = SKShapeNode(rectOf: CGSize(width: 7, height: 15), cornerRadius: 3); leg.position = CGPoint(x: x, y: 8); leg.fillColor = .darkGray; leg.strokeColor = .clear; leg.name = x < 0 ? "leftLeg" : "rightLeg"; node.addChild(leg)
        }
        let body = SKShapeNode(rectOf: CGSize(width: 23, height: 23), cornerRadius: 7); body.fillColor = color; body.strokeColor = .clear; body.position.y = 23; node.addChild(body)
        let emblem = label(profile.visibility == "anonymous" ? "?" : profile.avatar.preset == "star" ? "★" : profile.avatar.preset == "leaf" ? "✦" : "ϟ", size: 14, color: .white); emblem.position.y = 24; node.addChild(emblem)
        let head = SKShapeNode(circleOfRadius: 13); head.name = "head"; head.position.y = 43; head.fillColor = profile.visibility == "anonymous" ? .lightGray : UIColor(red: 0.94, green: 0.74, blue: 0.56, alpha: 1); head.strokeColor = UIColor(RankTier.tier(for: profile.gsr).color); head.lineWidth = 2.5; node.addChild(head)
        let crop = SKCropNode()
        let mask = SKShapeNode(circleOfRadius: 13 - head.lineWidth / 2)
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask
        head.addChild(crop)
        if let portrait, profile.visibility != "anonymous" {
            let sprite = SKSpriteNode(texture: SKTexture(image: portrait)); sprite.size = CGSize(width: 26, height: 26); crop.addChild(sprite)
        } else {
            for x in [-4.0, 4.0] { let eye = SKShapeNode(circleOfRadius: 1.5); eye.fillColor = .black; eye.strokeColor = .clear; eye.position = CGPoint(x: x, y: 1); crop.addChild(eye) }
            let hair = SKShapeNode(ellipseOf: CGSize(width: 24, height: 9)); hair.fillColor = .brown; hair.strokeColor = .clear; hair.position.y = 9; crop.addChild(hair)
        }
        let halo = SKShapeNode(ellipseOf: CGSize(width: 48, height: 22))
        halo.name = "activityHalo"; halo.strokeColor = .systemMint; halo.fillColor = .clear; halo.lineWidth = 3.5; halo.position.y = 1; node.addChild(halo)
        let name = label(profile.name, size: 10); name.position.y = 65; node.addChild(name)
        return node
    }
    func sync(uid: String, members: [RoomPresence], profiles: [String: SocialProfile], portraits: [String: UIImage]) {
        localID = uid
        for station in GymLayout.stations where station != "lounge" {
            if let node = world.childNode(withName: "station:\(station)") {
                node.childNode(withName: "occupancy")?.removeFromParent()
                let count = members.filter { $0.station == station }.count
                if count > 0 {
                    let tag = label(station == "cardio" ? L("IN USE") : L("IN USE · %lld/2", count), size: 9, color: .systemOrange)
                    tag.name = "occupancy"; tag.position = CGPoint(x: 10, y: 34); node.addChild(tag)
                }
            }
        }
        let ids = Set(members.map(\.uid))
        for id in Array(people.keys) where !ids.contains(id) { people[id]?.removeFromParent(); people[id] = nil; appearances[id] = nil }
        for member in members {
            guard let profile = profiles[member.uid] else { continue }
            let signature = "\(profile.name)|\(profile.gsr)|\(profile.avatar)|\(profile.cosmetics)|\(portraits[member.uid] != nil)"
            let isNew = people[member.uid] == nil
            if isNew || appearances[member.uid] != signature {
                let prior = people[member.uid]?.position
                people[member.uid]?.removeFromParent()
                let node = makePerson(profile: profile, portrait: portraits[member.uid]); people[member.uid] = node
                appearances[member.uid] = signature; world.addChild(node)
                node.position = prior ?? point(member.x, member.y)
                if member.uid == uid, isNew { localPosition = CGPoint(x: member.x, y: member.y) }
            }
            guard let node = people[member.uid] else { continue }
            let activityColor: UIColor = member.status == "Training" ? .systemOrange : member.status == "Resting" ? .systemCyan : .systemMint
            (node.childNode(withName: "activityHalo") as? SKShapeNode)?.strokeColor = activityColor
            (node.childNode(withName: "head") as? SKShapeNode)?.strokeColor = activityColor
            if node.userData?["status"] as? String != member.status {
                node.userData = ["status": member.status]
                let halo = node.childNode(withName: "activityHalo")
                halo?.removeAllActions(); halo?.alpha = 1
                if member.status == "Training" { halo?.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)]))) }
            }
            let completed = member.setCompletedAt ?? 0
            if completed > (completionTimes[member.uid] ?? 0) {
                completionTimes[member.uid] = completed
                if Date().timeIntervalSince1970 * 1000 - completed < 8000 {
                    let popup = label(L("SET COMPLETE ✓"), size: 12, color: .systemMint)
                    popup.position.y = 100; popup.zPosition = 100; node.addChild(popup)
                    popup.run(.sequence([.group([.moveBy(x: 0, y: 22, duration: 2), .sequence([.wait(forDuration: 1.2), .fadeOut(withDuration: 0.8)])]), .removeFromParent()]))
                }
            }
            node.childNode(withName: "activity")?.removeFromParent()
            let state = label(L(member.status), size: 8, color: member.status == "Training" ? .systemOrange : .systemMint)
            state.name = "activity"; state.position.y = 78; node.addChild(state)
            if member.uid != uid {
                node.removeAction(forKey: "move")
                node.run(.move(to: point(member.x, member.y), duration: 0.2), withKey: "move")
            }
            node.zPosition = CGFloat(member.x + member.y + 0.5)
        }
    }
    func walkToStation(_ station: String, partner: Bool = false) {
        guard var cell = GymLayout.stationCells[station] else { return }
        if partner && station != "lounge" && station != "cardio" { cell.x += 1 }
        walk(to: cell)
    }
    func cancelMovement() { route = [] }
    func confirmSet(at station: String) {
        guard let cell = GymLayout.stationCells[station] else { return }
        let note = label(L("SET SAVED ✓"), size: 15, color: .systemMint)
        note.position = point(Double(cell.x), Double(cell.y)); note.position.y += 65; note.zPosition = 100
        world.addChild(note)
        note.run(.sequence([.group([.moveBy(x: 0, y: 30, duration: 1.5), .fadeOut(withDuration: 1.5)]), .removeFromParent()]))
    }
    private func walk(to cell: GymLayout.Cell) {
        let start = GymLayout.Cell(x: Int(localPosition.x.rounded()), y: Int(localPosition.y.rounded()))
        route = GymLayout.path(from: start, to: cell, plain: plainSpace)
    }
    func select(at scenePoint: CGPoint) {
        let p = world.convert(scenePoint, from: self)
        for hit in world.nodes(at: p) {
            guard !hit.isHidden, hit.parent?.isHidden != true else { continue }
            var node: SKNode? = hit
            while let n = node, n !== world {
                if let name = n.name {
                    if name == "trainer" { onTrainer?(); return }
                    if name.hasPrefix("avatar:") { onProfile?(String(name.dropFirst(7))); return }
                    if name.hasPrefix("station:") { let station = String(name.dropFirst(8)); onStation?(station); return }
                }
                node = n.parent
            }
        }
        walk(to: cell(at: p))
    }
    override func update(_ currentTime: TimeInterval) {
        let delta = min(max(currentTime - lastTime, 0), 0.05); lastTime = currentTime
        guard let node = people[localID] else { return }
        if let next = route.first {
            let dx = Double(next.x) - localPosition.x, dy = Double(next.y) - localPosition.y
            let distance = hypot(dx, dy), step = delta * 3.5
            if distance <= step { localPosition = CGPoint(x: next.x, y: next.y); route.removeFirst() }
            else { localPosition.x += dx / distance * step; localPosition.y += dy / distance * step }
            node.position = point(localPosition.x, localPosition.y)
            node.zPosition = localPosition.x + localPosition.y + 0.5
            node.childNode(withName: "leftLeg")?.position.y = 8 + sin(currentTime * 20) * 3
            node.childNode(withName: "rightLeg")?.position.y = 8 - sin(currentTime * 20) * 3
            onMove?(localPosition.x, localPosition.y)
        } else {
            node.childNode(withName: "leftLeg")?.position.y = 8
            node.childNode(withName: "rightLeg")?.position.y = 8
        }
        node.childNode(withName: "head")?.position.y = 43 + sin(currentTime * 2.4) * 0.8
        if let trainer {
            let target = point(min(11, localPosition.x + 1.5), localPosition.y)
            trainer.position.x += (target.x - trainer.position.x) * delta * 2
            trainer.position.y += (target.y - trainer.position.y) * delta * 2
            trainer.zPosition = node.zPosition - 0.5
        }
    }
}
