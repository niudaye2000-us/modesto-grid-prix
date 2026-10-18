// RaceOverlayScene.swift
// ModestoGridPrix
//
// 2D heads-up overlay drawn on top of the SceneKit 3D race via
// SCNView.overlaySKScene. Carries over the working two-thumb controls:
//   bottom-left  = steering ◀ ▶
//   top-right    = pedals ▲ accelerate / ▼ brake
// plus lap/position/speed labels and the countdown. It writes button state
// into a shared RaceInput that the 3D controller reads each frame.
//
// Overlay scenes use a bottom-left origin (anchorPoint 0,0), so positions here
// are straightforward screen coordinates — no camera counter-scaling needed.

import SpriteKit

final class RaceOverlayScene: SKScene {

    weak var input: RaceInput?

    private let lapLabel = SKLabelNode()
    private let posLabel = SKLabelNode()
    private let speedLabel = SKLabelNode()
    private let countdownLabel = SKLabelNode()

    private var accelButton: SKShapeNode!
    private var brakeButton: SKShapeNode!
    private var leftButton: SKShapeNode!
    private var rightButton: SKShapeNode!

    private var accelTouches = Set<UITouch>()
    private var brakeTouches = Set<UITouch>()
    private var leftTouches = Set<UITouch>()
    private var rightTouches = Set<UITouch>()

    private var built = false

    override init(size: CGSize) {
        super.init(size: size)
        anchorPoint = CGPoint(x: 0, y: 0)
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        if !built { buildUI(); built = true }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard built else { return }
        removeAllChildren()
        buildUI()
    }

    private func buildUI() {
        let w = size.width, h = size.height

        func label(_ node: SKLabelNode, _ font: CGFloat, _ align: SKLabelHorizontalAlignmentMode) {
            node.fontName = "AvenirNext-Bold"
            node.fontSize = font
            node.fontColor = .white
            node.horizontalAlignmentMode = align
            node.verticalAlignmentMode = .top
            addChild(node)
        }
        let m: CGFloat = 20
        label(lapLabel, 22, .left);  lapLabel.position = CGPoint(x: m, y: h - m)
        label(posLabel, 22, .left);  posLabel.position = CGPoint(x: m, y: h - m - 28)
        label(speedLabel, 18, .left); speedLabel.fontColor = SKColor(white: 0.85, alpha: 1)
        speedLabel.position = CGPoint(x: m, y: h - m - 58)

        countdownLabel.fontName = "AvenirNext-Heavy"
        countdownLabel.fontSize = 120
        countdownLabel.fontColor = .white
        countdownLabel.horizontalAlignmentMode = .center
        countdownLabel.verticalAlignmentMode = .center
        countdownLabel.position = CGPoint(x: w / 2, y: h / 2)
        countdownLabel.zPosition = 100
        addChild(countdownLabel)

        let r: CGFloat = min(58, h * 0.16)
        let gap: CGFloat = 22
        let green = SKColor(red: 0.2, green: 0.72, blue: 0.33, alpha: 0.9)
        let red = SKColor(red: 0.86, green: 0.22, blue: 0.22, alpha: 0.9)
        let blue = SKColor(red: 0.26, green: 0.52, blue: 0.95, alpha: 0.9)
        let edge = r + 10

        // Steering: bottom-left.
        leftButton  = pedal("◀", CGPoint(x: edge, y: edge), r, blue)
        rightButton = pedal("▶", CGPoint(x: edge + r * 2 + gap, y: edge), r, blue)
        leftButton.name = "left"; rightButton.name = "right"
        addChild(leftButton); addChild(rightButton)

        // Pedals: top-right (accelerate on top).
        accelButton = pedal("▲", CGPoint(x: w - edge, y: h - edge), r, green)
        brakeButton = pedal("▼", CGPoint(x: w - edge, y: h - edge - r * 2 - gap), r, red)
        accelButton.name = "accel"; brakeButton.name = "brake"
        addChild(accelButton); addChild(brakeButton)
    }

    private func pedal(_ symbol: String, _ pos: CGPoint, _ radius: CGFloat, _ color: SKColor) -> SKShapeNode {
        let b = SKShapeNode(circleOfRadius: radius)
        b.fillColor = color
        b.strokeColor = SKColor(white: 1, alpha: 0.5)
        b.lineWidth = 2
        b.position = pos
        b.zPosition = 50
        let l = SKLabelNode(text: symbol)
        l.fontName = "AvenirNext-Bold"
        l.fontSize = radius
        l.fontColor = .white
        l.verticalAlignmentMode = .center
        l.horizontalAlignmentMode = .center
        b.addChild(l)
        return b
    }

    // MARK: HUD refresh (called by the 3D controller each frame)

    func update(engine: RaceEngine) {
        let p = engine.player
        lapLabel.text = "LAP \(min(max(p.lap, 1), engine.config.laps))/\(engine.config.laps)"
        posLabel.text = "POS \(p.livePosition)/\(engine.totalCars)"
        speedLabel.text = "\(Int(p.speed)) u/s"

        switch engine.phase {
        case .countdown(let n):
            countdownLabel.isHidden = false
            countdownLabel.text = "\(n)"
        case .racing:
            if countdownLabel.text != "" && countdownLabel.text != "GO!" && !countdownLabel.isHidden {
                countdownLabel.text = "GO!"
                countdownLabel.run(.sequence([.wait(forDuration: 0.7),
                                              .fadeOut(withDuration: 0.3),
                                              .run { [weak self] in self?.countdownLabel.isHidden = true }]))
            }
        case .finished:
            countdownLabel.isHidden = true
        }
    }

    // MARK: Touch routing (scene-space hit test, same approach that worked in 2D)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { route(t) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { end(t) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { end(t) }
    }

    private func route(_ t: UITouch) {
        let loc = t.location(in: self)
        // Climb from the hit node to a named button; fall back to nearest.
        var name: String?
        var cur: SKNode? = atPoint(loc)
        while let c = cur {
            if let nm = c.name, ["accel", "brake", "left", "right"].contains(nm) { name = nm; break }
            cur = c.parent
        }
        if name == nil {
            // Nearest-button fallback with padding.
            let pad: CGFloat = 24
            var best: (String, CGFloat)?
            for b in [accelButton!, brakeButton!, leftButton!, rightButton!] {
                let d = loc.distance(to: b.position)
                if d < b.frame.width / 2 + pad, best == nil || d < best!.1 {
                    best = (b.name ?? "", d)
                }
            }
            name = best?.0
        }
        guard let n = name, let input = input else { return }
        switch n {
        case "accel": accelTouches.insert(t); input.accel = true; accelButton.alpha = 0.6
        case "brake": brakeTouches.insert(t); input.brake = true; brakeButton.alpha = 0.6
        case "left":  leftTouches.insert(t);  input.left = true;  leftButton.alpha = 0.6
        case "right": rightTouches.insert(t); input.right = true; rightButton.alpha = 0.6
        default: break
        }
    }

    private func end(_ t: UITouch) {
        guard let input = input else { return }
        if accelTouches.remove(t) != nil, accelTouches.isEmpty { input.accel = false; accelButton.alpha = 1 }
        if brakeTouches.remove(t) != nil, brakeTouches.isEmpty { input.brake = false; brakeButton.alpha = 1 }
        if leftTouches.remove(t) != nil, leftTouches.isEmpty { input.left = false; leftButton.alpha = 1 }
        if rightTouches.remove(t) != nil, rightTouches.isEmpty { input.right = false; rightButton.alpha = 1 }
    }
}
