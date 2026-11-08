import SpriteKit
import SwiftUI

@MainActor
final class GymScene: SKScene, ObservableObject {
    nonisolated static let roomSize = CGSize(width: 780, height: 520)
    private static let floorOrigin = CGPoint(x: 360, y: 421)
    private static let roomCenter = CGPoint(x: roomSize.width / 2, y: roomSize.height / 2)
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
        roomCamera.position = Self.roomCenter
        buildRoom()
    }
    required init?(coder aDecoder: NSCoder) { fatalError("Use init(size:)") }
    override func didChangeSize(_ oldSize: CGSize) { fitViewport(size) }
    func fitViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0, viewportSize != size else { return }
        viewportSize = size
        roomCamera.setScale(GymCamera.fitScale(size) / zoomLevel)
        clampCamera()
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
    var canPan: Bool { zoomLevel > 1 }

    func pan(by translation: CGPoint) {
        roomCamera.position.x -= translation.x * roomCamera.xScale
        roomCamera.position.y += translation.y * roomCamera.yScale
        clampCamera()
    }
    func resetCamera() {
        zoomLevel = 1; roomCamera.position = Self.roomCenter
        roomCamera.setScale(GymCamera.fitScale(viewportSize))
    }
    private func clampCamera() {
        let travelX = max(0, Self.roomSize.width - viewportSize.width * roomCamera.xScale) / 2
        let travelY = max(0, Self.roomSize.height - viewportSize.height * roomCamera.yScale) / 2
        let center = Self.roomCenter
        roomCamera.position.x = min(center.x + travelX, max(center.x - travelX, roomCamera.position.x))
        roomCamera.position.y = min(center.y + travelY, max(center.y - travelY, roomCamera.position.y))
    }

    func configure(plain: Bool) {
        guard plainSpace != plain else { return }
        plainSpace = plain
        cancelMovement()
        for node in world.children where node.name?.hasPrefix("station:") == true { node.isHidden = plain }
    }
    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: Self.floorOrigin.x + (x - y) * 30, y: Self.floorOrigin.y - (x + y) * 16)
    }

    private func cell(at p: CGPoint) -> GymLayout.Cell {
        let a = (p.x - Self.floorOrigin.x) / 30, b = (Self.floorOrigin.y - p.y) / 16
        return GymLayout.Cell(x: Int(((a + b) / 2).rounded()), y: Int(((b - a) / 2).rounded()))
    }

    private func label(_ text: String, size: CGFloat, color: UIColor = .white) -> SKLabelNode {
        let node = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        node.text = text; node.fontSize = size; node.fontColor = color; node.verticalAlignmentMode = .center
        return node
    }
    private func buildRoom() {
        let left = point(-0.5, Double(GymLayout.height) - 0.5)
        let back = point(-0.5, -0.5)
        let right = point(Double(GymLayout.width) - 0.5, -0.5)
        let front = point(Double(GymLayout.width) - 0.5, Double(GymLayout.height) - 0.5)
        addSurface(floorTexture(), corners: [left, front, back, right], depth: -100)

        let wall = SKTexture(imageNamed: "GymWall")
        for (start, end) in [(left, back), (back, right)] {
            let topStart = CGPoint(x: start.x, y: start.y + 66)
            let topEnd = CGPoint(x: end.x, y: end.y + 66)
            addSurface(wall, corners: [start, end, topStart, topEnd], depth: -90)
        }

        equipment("rack", x: 1, y: 1, width: 105, color: .systemCyan)
        equipment("bench", x: 4, y: 2, width: 98, color: .systemOrange)
        equipment("cardio", x: 8, y: 1, width: 105, color: .systemMint)
        equipment("platform", x: 8, y: 5, width: 106, color: .systemPurple)
        equipment("lounge", x: 1, y: 8, width: 87, color: .systemIndigo)

        let coach = makePerson(profile: SocialProfile(uid: "trainer", name: L("AI trainer"), gsr: 0, cosmetics: [], interests: "", avatar: AvatarAppearance(preset: "star", color: "green")), portrait: nil)
        coach.name = "trainer"; coach.position = point(4, 7); coach.zPosition = 30
        world.addChild(coach); trainer = coach
    }

    private func floorTexture() -> SKTexture {
        let tileSize: CGFloat = 64
        let width = CGFloat(GymLayout.width) * tileSize
        let height = CGFloat(GymLayout.height) * tileSize
        let tile = UIImage(named: "GymFloor")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            for x in 0..<GymLayout.width {
                for y in 0..<GymLayout.height {
                    let rect = CGRect(x: CGFloat(x) * tileSize, y: CGFloat(y) * tileSize, width: tileSize, height: tileSize)
                    UIColor(red: 0.09, green: 0.12, blue: 0.17, alpha: 1).setFill()
                    context.fill(rect)
                    tile?.draw(in: rect)
                    UIColor.white.withAlphaComponent((x + y).isMultiple(of: 2) ? 0.035 : 0.005).setFill()
                    context.fill(rect)
                    UIColor(red: 0.38, green: 0.53, blue: 0.68, alpha: 0.26).setStroke()
                    context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
                }
            }
        }
        return SKTexture(image: image)
    }

    // The visual surfaces use the same projection as taps, paths, and station positions.
    private func addSurface(_ texture: SKTexture, corners: [CGPoint], depth: CGFloat) {
        let path = CGMutablePath()
        path.addLines(between: corners)
        let bounds = path.boundingBox
        let node = SKSpriteNode(texture: texture, size: bounds.size)
        let source = [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 1), SIMD2<Float>(1, 1)]
        let destination = corners.map {
            SIMD2(Float(($0.x - bounds.minX) / bounds.width), Float(($0.y - bounds.minY) / bounds.height))
        }
        node.warpGeometry = SKWarpGeometryGrid(columns: 1, rows: 1, sourcePositions: source, destinationPositions: destination)
        node.position = CGPoint(x: bounds.midX, y: bounds.midY)
        node.zPosition = depth
        world.addChild(node)
    }

    private func equipment(_ kind: String, x: Double, y: Double, width: CGFloat, color: UIColor) {
        let node = SKNode()
        node.position = point(x + 0.5, y)
        node.name = "station:\(kind)"
        node.zPosition = x + y + 0.5
        let shadow = SKShapeNode(ellipseOf: CGSize(width: width * 0.72, height: 20))
        shadow.fillColor = .black.withAlphaComponent(0.38)
        shadow.strokeColor = .clear
        node.addChild(shadow)

        let texture = SKTexture(imageNamed: "Gym\(kind.capitalized)")
        let sprite = SKSpriteNode(texture: texture)
        let aspectRatio = texture.size().height / max(texture.size().width, 1)
        sprite.size = CGSize(width: width, height: width * aspectRatio)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.position.y = -14
        node.addChild(sprite)

        let caption = label(L(kind.capitalized), size: 15, color: color)
        caption.position.y = -24
        node.addChild(caption)
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
                    tag.name = "occupancy"; tag.position = CGPoint(x: 0, y: -38); node.addChild(tag)
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
    /// Equipment accessibility targets follow the same camera as the rendered machines.
    func equipmentFrames() -> [(String, CGRect)] {
        guard !plainSpace, view != nil else { return [] }
        return GymLayout.stations.compactMap { station in
            guard let node = world.childNode(withName: "station:\(station)"), !node.isHidden else { return nil }
            let frame = node.calculateAccumulatedFrame()
            let a = convertPoint(toView: world.convert(CGPoint(x: frame.minX, y: frame.minY), to: self))
            let b = convertPoint(toView: world.convert(CGPoint(x: frame.maxX, y: frame.maxY), to: self))
            return (station, CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)))
        }
    }
    func select(at scenePoint: CGPoint) {
        let p = world.convert(scenePoint, from: self)
        let hits = world.nodes(at: p).compactMap { hit -> SKNode? in
            var node = hit
            while let parent = node.parent, parent !== world { node = parent }
            return node.parent === world && !node.isHidden ? node : nil
        }
        for hit in hits.sorted(by: { $0.zPosition > $1.zPosition }) {
            guard let name = hit.name else { continue }
            if name == "trainer" { onTrainer?(); return }
            if name.hasPrefix("avatar:") { onProfile?(String(name.dropFirst(7))); return }
            if name.hasPrefix("station:") { onStation?(String(name.dropFirst(8))); return }
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
