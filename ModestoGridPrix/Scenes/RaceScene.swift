// RaceScene.swift
// ModestoGridPrix
//
// The gameplay scene. Layout:
//   • A `worldNode` holds the track + car nodes in world coordinates; the camera
//     follows the player so the world scrolls.
//   • A `hud` layer is pinned to the camera (fixed on screen) for the lap/time/
//     position readouts, the countdown, and the on-screen accelerate/brake
//     buttons.
// Each frame: read inputs → RaceEngine.update → sync node transforms → update HUD.

import SpriteKit

final class RaceScene: SKScene {

    // Simulation
    private let engine: RaceEngine
    private let motion = MotionManager()

    // Nodes
    private let worldNode = SKNode()
    private let cam = SKCameraNode()
    private var carNodes: [Int: CarNode] = [:]   // car.id -> node

    // HUD
    private let hud = SKNode()
    private let lapLabel = SKLabelNode()
    private let posLabel = SKLabelNode()
    private let timeLabel = SKLabelNode()
    private let bestLabel = SKLabelNode()
    private let speedLabel = SKLabelNode()
    private let countdownLabel = SKLabelNode()
    private var accelButton: SKShapeNode!
    private var brakeButton: SKShapeNode!

    // Input state (set by touches on the buttons)
    private var accelHeld = false
    private var brakeHeld = false
    private var accelTouches = Set<UITouch>()
    private var brakeTouches = Set<UITouch>()

    private var lastTime: TimeInterval = 0
    private var didFinish = false
    private var countdownShownGo = false

    override init(size: CGSize) {
        self.engine = RaceEngine(track: TrackBuilder.defaultTrack(),
                                 config: .default)
        super.init(size: size)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.20, green: 0.45, blue: 0.22, alpha: 1)

        addChild(worldNode)
        addChild(cam)
        camera = cam
        cam.setScale(GameConstants.cameraZoom)
        cam.addChild(hud)

        // Track art.
        worldNode.addChild(TrackRenderer.buildNode(for: engine.track))

        // Car nodes.
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
        // Calibrate neutral tilt shortly after start (gives the player a moment
        // to settle into a comfortable hold).
        run(.sequence([.wait(forDuration: 0.3), .run { [weak self] in self?.motion.calibrate() }]))

        // Center camera on player immediately.
        cam.position = engine.player.position
    }

    override func willMove(from view: SKView) {
        motion.stop()
    }

    // MARK: HUD

    private func buildHUD() {
        func label(_ node: SKLabelNode, _ font: CGFloat, _ align: SKLabelHorizontalAlignmentMode) {
            node.fontName = "AvenirNext-Bold"
            node.fontSize = font
            node.fontColor = .white
            node.horizontalAlignmentMode = align
            node.verticalAlignmentMode = .top
            hud.addChild(node)
        }
        let halfW = size.width / 2
        let halfH = size.height / 2
        let m: CGFloat = 20

        label(lapLabel, 22, .left)
        lapLabel.position = CGPoint(x: -halfW + m, y: halfH - m)

        label(posLabel, 22, .left)
        posLabel.position = CGPoint(x: -halfW + m, y: halfH - m - 30)

        label(timeLabel, 20, .right)
        timeLabel.position = CGPoint(x: halfW - m, y: halfH - m)

        label(bestLabel, 16, .right)
        bestLabel.fontColor = SKColor(white: 0.8, alpha: 1)
        bestLabel.position = CGPoint(x: halfW - m, y: halfH - m - 28)

        label(speedLabel, 16, .right)
        speedLabel.fontColor = SKColor(white: 0.8, alpha: 1)
        speedLabel.position = CGPoint(x: halfW - m, y: halfH - m - 52)

        // Countdown (center, big).
        countdownLabel.fontName = "AvenirNext-Heavy"
        countdownLabel.fontSize = 120
        countdownLabel.fontColor = .white
        countdownLabel.horizontalAlignmentMode = .center
        countdownLabel.verticalAlignmentMode = .center
        countdownLabel.position = .zero
        hud.addChild(countdownLabel)

        // Accelerate / brake buttons (bottom corners).
        let btnR: CGFloat = min(64, size.height * 0.18)
        accelButton = pedal(symbol: "▶", at: CGPoint(x: halfW - m - btnR, y: -halfH + m + btnR),
                            radius: btnR, color: SKColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 0.85))
        brakeButton = pedal(symbol: "◀", at: CGPoint(x: -halfW + m + btnR, y: -halfH + m + btnR),
                            radius: btnR, color: SKColor(red: 0.85, green: 0.2, blue: 0.2, alpha: 0.85))
        hud.addChild(accelButton)
        hud.addChild(brakeButton)
    }

    private func pedal(symbol: String, at pos: CGPoint, radius: CGFloat, color: SKColor) -> SKShapeNode {
        let b = SKShapeNode(circleOfRadius: radius)
        b.fillColor = color
        b.strokeColor = SKColor(white: 1, alpha: 0.4)
        b.lineWidth = 2
        b.position = pos
        let l = SKLabelNode(text: symbol)
        l.fontName = "AvenirNext-Bold"
        l.fontSize = radius
        l.verticalAlignmentMode = .center
        l.horizontalAlignmentMode = .center
        b.addChild(l)
        return b
    }

    // MARK: Touch handling (pedals)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { routeTouch(t, began: true) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { endTouch(t) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { endTouch(t) }
    }

    private func routeTouch(_ t: UITouch, began: Bool) {
        // Convert to HUD space (hud is child of camera).
        let p = t.location(in: hud)
        if accelButton.contains(p) {
            accelTouches.insert(t); accelHeld = true
            accelButton.alpha = 0.6
        } else if brakeButton.contains(p) {
            brakeTouches.insert(t); brakeHeld = true
            brakeButton.alpha = 0.6
        }
    }

    private func endTouch(_ t: UITouch) {
        if accelTouches.remove(t) != nil, accelTouches.isEmpty {
            accelHeld = false; accelButton.alpha = 1
        }
        if brakeTouches.remove(t) != nil, brakeTouches.isEmpty {
            brakeHeld = false; brakeButton.alpha = 1
        }
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 60.0 : min(1.0 / 20.0, currentTime - lastTime)
        lastTime = currentTime

        let steer = motion.steer
        engine.update(dt: dt,
                      playerThrottle: accelHeld ? 1 : 0,
                      playerBrake: brakeHeld ? 1 : 0,
                      playerSteer: steer)

        // Sync car nodes.
        for car in engine.cars {
            if let node = carNodes[car.id] {
                node.position = car.position
                node.zRotation = car.heading
            }
        }

        // Camera follow (smooth).
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
            // On the first racing frame, flash GO! then hide it.
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
        speedLabel.text = "\(Int(p.speed / 5)) km/h"   // arbitrary readout scaling
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
