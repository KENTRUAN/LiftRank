import SwiftUI
import SpriteKit

/// A camera keeps zoom independent of avatar coordinates and movement messages.
enum GymCamera {
    static func zoom(_ value: CGFloat) -> CGFloat { min(3, max(0.8, value.isFinite ? value : 1)) }
    static func fitScale(_ size: CGSize) -> CGFloat {
        max(GymScene.roomSize.width / max(1, size.width), GymScene.roomSize.height / max(1, size.height))
    }
}

struct GymSceneView: UIViewRepresentable {
    let scene: GymScene
    func makeCoordinator() -> Coordinator { Coordinator(scene: scene) }
    func makeUIView(context: Context) -> SKView {
        let view = AccessibleGymView()
        view.isAccessibilityElement = false
        view.isMultipleTouchEnabled = true
        view.presentScene(scene)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pinch.delegate = context.coordinator; pan.delegate = context.coordinator
        tap.require(toFail: pinch); tap.require(toFail: pan)
        [tap, pinch, pan].forEach { view.addGestureRecognizer($0) }
        return view
    }
    func updateUIView(_ view: SKView, context: Context) { scene.fitViewport(view.bounds.size) }
    static func dismantleUIView(_ view: SKView, coordinator: Coordinator) { view.presentScene(nil) }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let scene: GymScene
        init(scene: GymScene) { self.scene = scene }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            scene.select(at: scene.convertPoint(fromView: gesture.location(in: gesture.view)))
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            if gesture.state == .began { scene.cancelMovement() }
            scene.zoom(by: gesture.scale, around: gesture.location(in: gesture.view))
            gesture.scale = 1
        }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            guard gesture.numberOfTouches == 1 else { return }
            if gesture.state == .began { scene.cancelMovement() }
            scene.pan(by: translation)
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            !(gestureRecognizer is UIPanGestureRecognizer) || scene.canPan
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UIPanGestureRecognizer && (other.view as? UIScrollView)?.panGestureRecognizer === other
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer)
                || (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
        }
    }
}

private final class AccessibleGymView: SKView {
    private var equipmentElements: [String: GymEquipmentElement] = [:]
    override var accessibilityElements: [Any]? {
        get {
            guard let scene = scene as? GymScene else { return nil }
            return scene.equipmentFrames().compactMap { station, frame in
                let visible = frame.intersection(bounds)
                guard !visible.isNull, !visible.isEmpty else { return nil }
                let element = equipmentElements[station] ?? GymEquipmentElement(accessibilityContainer: self)
                equipmentElements[station] = element
                element.accessibilityLabel = GymEquipment.title(station)
                element.accessibilityIdentifier = "gymEquipment.\(station)"
                element.accessibilityTraits = .button
                element.accessibilityFrameInContainerSpace = visible
                element.activate = { [weak scene] in scene?.onStation?(station) }
                return element
            }
        }
        set { }
    }
}

private final class GymEquipmentElement: UIAccessibilityElement {
    var activate: (() -> Void)?
    override func accessibilityActivate() -> Bool { activate?(); return activate != nil }
}
