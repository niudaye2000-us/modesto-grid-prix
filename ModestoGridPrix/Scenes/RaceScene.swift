// RaceScene.swift
// ModestoGridPrix
//
// Controls (two-thumb):
//   LEFT side  = steering: ◀ (left) and ▶ (right)
//   RIGHT side = pedals:   ▲ accelerate (top) / ▼ brake (bottom)
//   Tilt also steers when no steer button is held.

import SpriteKit

final class RaceScene: SKScene {

    private let engine: RaceEngine
    private let motion = MotionManager()

    private let worldNode = SKNode()
    private let cam = SKCameraNode()
    private var carNodes: [Int: CarNode] = [:]

    private let hud = SKNode()
    private let lapLabel = SKLabelNode()
    private let posLabel = SKLabelNode()
    private let timeLabel = SKLabelNode()
    private let bestLabel = SKLabelNode()
    private let speedLabel = SKLabelNode()
    private let countdownLabel = SKLabelNode()
    private let debugLabel = SKLabelNode()
    private var accelButton: SKShapeNode!
    private var brakeButton: SKShapeNode!
    private var leftButton: SKShapeNode!
    private var rightButton: SKShapeNode!

    private var accelHeld = false
    private var brakeHeld = false
    private var leftHeld = false
    private var rightHeld = false
    private var accelTouches = Set<UITouch>()
    private var brakeTouches = Set<UITouch>()
    private var leftTouches = Set<UITouch>()
    private var rightTouches = Set<UITouch>()
    private var buttonSteer: CGFloat = 0

    private var screenSize: CGSize = .zero
    private var lastTime: TimeInterval = 0
    private var didFinish = false
    private var countdownShownGo = false

    override init(size: CGSize) {
        self.engine = RaceEngine(track: TrackBuilder.defaultTrack(), config: .default)
        super.init(size: size)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.20, green: 0.45, blue: 0.22, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        screenSize = view.bounds.size

        addChild(worldNode)
        addChild(cam)
        camera = cam
        cam.setScale(GameConstants.cameraZoom)
        hud.setScale(1.0 / GameConstants.cameraZoom)
        hud.zPosition = 1000
        cam.addChild(hud)

        worldNode.addChild(TrackRenderer.buildNode(for: engine.track))

        for car in engine.cars {
            let node = CarNode(carId: car.id, livery: car.livery)
            node.position = car.position
            node.zRotation = car.heading
            node.zPosition = car.isPlayer ? 10 : 9
            worldNode.addChild(node)
            carNodes[car.id] = node
        }

        buildHUD()
        motion.start()
        run(.sequence([.wait(forDuration: 0.3), .run { [weak self] in self?.motion.calibrate() }]))
        cam.position = engine.player.position
    }

    override func willMove(from view: SKView) { motion.stop() }

    private func buildHUD() {
        let sz = screenSize.width > 0 ? screenSize : size
        // The HUD is a child of the camera and counter-scaled by 1/cameraZoom so
        // it reads at screen size. That means HUD-local coordinates are compressed
        // by cameraZoom on screen, so to reach the true screen edge we must scale
        // the half-extents by cameraZoom.
        let halfW = sz.width / 2 * GameConstants.cameraZoom
        let halfH = sz.height / 2 * GameConstants.cameraZoom
        let m: CGFloat = 24

        func label(_ node: SKLabelNode, _ font: CGFloat, _ align: SKLabelHorizontalAlignmentMode) {
            node.fontName = "AvenirNext-Bold"
            node.fontSize = font
            node.fontColor = .white
            node.horizontalAlignmentMode = align
            node.verticalAlignmentMode = .top
            hud.addChild(node)
        }

        label(lapLabel, 22, .left);  lapLabel.position = CGPoint(x: -halfW + m, y: halfH - m)
        label(posLabel, 22, .left);  posLabel.position = CGPoint(x: -halfW + m, y: halfH - m - 30)
        label(timeLabel, 20, .right); timeLabel.position = CGPoint(x: halfW - m, y: halfH - m)
        label(bestLabel, 16, .right); bestLabel.fontColor = SKColor(white: 0.8, alpha: 1)
        bestLabel.position = CGPoint(x: halfW - m, y: halfH - m - 28)
        label(speedLabel, 16, .right); speedLabel.fontColor = SKColor(white: 0.8, alpha: 1)
        speedLabel.position = CGPoint(x: halfW - m, y: halfH - m - 52)

        countdownLabel.fontName = "AvenirNext-Heavy"
        countdownLabel.fontSize = 120
        countdownLabel.fontColor = .white
        countdownLabel.horizontalAlignmentMode = .center
        countdownLabel.verticalAlignmentMode = .center
        countdownLabel.position = .zero
        hud.addChild(countdownLabel)

        debugLabel.fontName = "Menlo-Bold"
        debugLabel.fontSize = 20
        debugLabel.fontColor = .yellow
        debugLabel.horizontalAlignmentMode = .center
        debugLabel.verticalAlignmentMode = .bottom
        debugLabel.position = CGPoint(x: 0, y: -halfH + 8)
        debugLabel.zPosition = 2000
        hud.addChild(debugLabel)

        let r: CGFloat = min(56, halfH * 0.30)
        let gap: CGFloat = 20
        let green = SKColor(red: 0.2, green: 0.72, blue: 0.33, alpha: 0.9)
        let red = SKColor(red: 0.86, green: 0.22, blue: 0.22, alpha: 0.9)
        let blue = SKColor(red: 0.26, green: 0.52, blue: 0.95, alpha: 0.9)

        let edge: CGFloat = r + 2   // just enough so a button sits flush against the physical edge

        // Steering: hard into the bottom-left corner, side by side.
        let steerY = -halfH + edge
        leftButton = pedal("◀", CGPoint(x: -halfW + edge, y: steerY), r, blue)
        rightButton = pedal("▶", CGPoint(x: -halfW + edge + r * 2 + gap, y: steerY), r, blue)
        leftButton.name = "left"; rightButton.name = "right"
        hud.addChild(leftButton); hud.addChild(rightButton)

        // Pedals: hard into the top-right corner, stacked (accelerate on top).
        accelButton = pedal("▲", CGPoint(x: halfW - edge, y: halfH - edge), r, green)
        brakeButton = pedal("▼", CGPoint(x: halfW - edge, y: halfH - edge - r * 2 - gap), r, red)
        accelButton.name = "accel"; brakeButton.name = "brake"
        hud.addChild(accelButton); hud.addChild(brakeButton)
    }

    private func pedal(_ symbol: String, _ pos: CGPoint, _ radius: CGFloat, _ color: SKColor) -> SKShapeNode {
        let b = SKShapeNode(circleOfRadius: radius)
        b.fillColor = color
        b.strokeColor = SKColor(white: 1, alpha: 0.5)
        b.lineWidth = 2
        b.position = pos
        b.name = "pedal"
        let l = SKLabelNode(text: symbol)
        l.fontName = "AvenirNext-Bold"
        l.fontSize = radius
        l.verticalAlignmentMode = .center
        l.horizontalAlignmentMode = .center
        b.addChild(l)
        return b
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { routeTouch(t) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { endTouch(t) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { endTouch(t) }
    }

    private func routeTouch(_ t: UITouch) {
        // Convert the touch into SCENE space and let SpriteKit's node hit test
        // handle the full camera/hud transform. We then climb from whatever node
        // was hit (often the arrow label) up to its named pedal parent, and also
        // fall back to a nearest-button test for easy pressing.
        let scenePoint = t.location(in: self)
        var name: String? = nil
        for node in nodes(at: scenePoint) {
            var n: SKNode? = node
            while let cur = n {
                if let nm = cur.name, ["accel", "brake", "left", "right"].contains(nm) {
                    name = nm; break
                }
                n = cur.parent
            }
            if name != nil { break }
        }

        // Fallback: nearest button in hud space (padded) if nothing was hit
        // directly — makes the round buttons forgiving to press.
        if name == nil {
            let p = t.location(in: hud)
            let r: CGFloat = min(56, (screenSize.height > 0 ? screenSize.height : size.height) / 2 * 0.30)
            let hitR = r + 36
            var bestD = CGFloat.greatestFiniteMagnitude
            for b in [accelButton!, brakeButton!, leftButton!, rightButton!] {
                let d = p.distance(to: b.position)
                if d <= hitR && d < bestD { bestD = d; name = b.name }
            }
        }

        switch name {
        case "accel": accelTouches.insert(t); accelHeld = true; accelButton.alpha = 0.6
        case "brake": brakeTouches.insert(t); brakeHeld = true; brakeButton.alpha = 0.6
        case "left":  leftTouches.insert(t);  leftHeld = true;  leftButton.alpha = 0.6
        case "right": rightTouches.insert(t); rightHeld = true; rightButton.alpha = 0.6
        default: break
        }
    }

    private func endTouch(_ t: UITouch) {
        if accelTouches.remove(t) != nil, accelTouches.isEmpty { accelHeld = false; accelButton.alpha = 1 }
        if brakeTouches.remove(t) != nil, brakeTouches.isEmpty { brakeHeld = false; brakeButton.alpha = 1 }
        if leftTouches.remove(t) != nil, leftTouches.isEmpty { leftHeld = false; leftButton.alpha = 1 }
        if rightTouches.remove(t) != nil, rightTouches.isEmpty { rightHeld = false; rightButton.alpha = 1 }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 60.0 : min(1.0 / 20.0, currentTime - lastTime)
        lastTime = currentTime

        // Steering is driven purely by the on-screen buttons. Tilt is disabled so
        // a naturally-held phone can't feed a constant steer input (which spun the
        // car at high speed). Release both buttons = go straight.
        let steerTarget: CGFloat = (leftHeld ? -1 : 0) + (rightHeld ? 1 : 0)
        let ease = min(1, 12 * CGFloat(dt))
        buttonSteer += (steerTarget - buttonSteer) * ease
        let steer = buttonSteer

        engine.update(dt: dt,
                      playerThrottle: accelHeld ? 1 : 0,
                      playerBrake: brakeHeld ? 1 : 0,
                      playerSteer: steer)

        for car in engine.cars {
            if let node = carNodes[car.id] {
                node.position = car.position
                node.zRotation = car.heading
            }
        }

        let target = engine.player.position
        cam.position = CGPoint(
            x: cam.position.x + (target.x - cam.position.x) * GameConstants.cameraLerp,
            y: cam.position.y + (target.y - cam.position.y) * GameConstants.cameraLerp
        )

        updateHUD()

        if case .finished = engine.phase, !didFinish {
            didFinish = true
            goToResults()
        }
    }

    private func updateHUD() {
        let p = engine.player
        switch engine.phase {
        case .countdown(let n):
            countdownLabel.isHidden = false
            countdownLabel.text = "\(n)"
        case .racing:
            if !countdownShownGo {
                countdownShownGo = true
                countdownLabel.isHidden = false
                countdownLabel.text = "GO!"
                countdownLabel.run(.sequence([.wait(forDuration: 0.7),
                                              .fadeOut(withDuration: 0.3),
                                              .run { [weak self] in self?.countdownLabel.isHidden = true }]))
            }
        case .finished:
            countdownLabel.isHidden = true
        }

        lapLabel.text = "LAP \(min(max(p.lap, 1), engine.config.laps))/\(engine.config.laps)"
        posLabel.text = "POS \(p.livePosition)/\(engine.totalCars)"
        timeLabel.text = formatTime(engine.raceElapsed)
        bestLabel.text = "Best " + formatTime(p.bestLapTime)
        speedLabel.text = "\(Int(p.speed / 5)) km/h"
        debugLabel.text = String(format: "L%@ R%@ A%@ B%@  steer=%.2f spd=%d",
            leftHeld ? "1" : "0", rightHeld ? "1" : "0",
            accelHeld ? "1" : "0", brakeHeld ? "1" : "0",
            Double(p.steer), Int(p.speed))
    }

    private func formatTime(_ t: TimeInterval) -> String {
        if t <= 0 || t == .greatestFiniteMagnitude { return "--:--.---" }
        let m = Int(t) / 60, s = Int(t) % 60, ms = Int((t - floor(t)) * 1000)
        return String(format: "%d:%02d.%03d", m, s, ms)
    }

    private func goToResults() {
        let results = ResultsScene(size: size,
                                   finishingOrder: engine.finishingOrder,
                                   playerId: engine.player.id)
        results.scaleMode = .resizeFill
        view?.presentScene(results, transition: .fade(withDuration: 0.6))
    }
}
