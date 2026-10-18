// MenuScene.swift
// ModestoGridPrix
//
// The main menu: title, a tappable "Start Race" button, and a short controls
// hint. Tapping Start transitions to the RaceScene.

import SpriteKit

final class MenuScene: SKScene {

    private let startButtonName = "startButton"
    /// Set by GameView; called when the player taps Start.
    var onStart: (() -> Void)?

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)
        buildUI()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard children.count > 0 else { return }
        removeAllChildren()
        buildUI()
    }

    private func buildUI() {
        let cx = size.width / 2

        // Title
        let title = SKLabelNode(text: "MODESTO")
        title.fontName = "AvenirNext-Heavy"
        title.fontSize = min(72, size.width * 0.11)
        title.fontColor = SKColor(red: 0.91, green: 0.25, blue: 0.16, alpha: 1)
        title.position = CGPoint(x: cx, y: size.height * 0.70)
        title.horizontalAlignmentMode = .center
        addChild(title)

        let sub = SKLabelNode(text: "GRID PRIX")
        sub.fontName = "AvenirNext-Heavy"
        sub.fontSize = min(52, size.width * 0.08)
        sub.fontColor = .white
        sub.position = CGPoint(x: cx, y: size.height * 0.58)
        sub.horizontalAlignmentMode = .center
        addChild(sub)

        // Start button
        let button = SKShapeNode(rectOf: CGSize(width: 260, height: 68), cornerRadius: 14)
        button.name = startButtonName
        button.fillColor = SKColor(red: 0.91, green: 0.25, blue: 0.16, alpha: 1)
        button.strokeColor = .clear
        button.position = CGPoint(x: cx, y: size.height * 0.38)
        addChild(button)

        let label = SKLabelNode(text: "START RACE")
        label.name = startButtonName
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 28
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.position = button.position
        addChild(label)

        // Controls hint
        let hint = SKLabelNode(text: "Hold ▲ to accelerate  ·  ▼ to brake  ·  ◀ ▶ to steer")
        hint.fontName = "AvenirNext-Medium"
        hint.fontSize = min(18, size.width * 0.028)
        hint.fontColor = SKColor(white: 0.75, alpha: 1)
        hint.position = CGPoint(x: cx, y: size.height * 0.20)
        hint.horizontalAlignmentMode = .center
        addChild(hint)

        let laps = SKLabelNode(text: "\(GameConstants.defaultLaps) laps  Â·  \(GameConstants.defaultOpponents) opponents")
        laps.fontName = "AvenirNext-Medium"
        laps.fontSize = min(16, size.width * 0.025)
        laps.fontColor = SKColor(white: 0.55, alpha: 1)
        laps.position = CGPoint(x: cx, y: size.height * 0.13)
        laps.horizontalAlignmentMode = .center
        addChild(laps)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let hit = atPoint(t.location(in: self))
        if hit.name == startButtonName {
            startRace()
        }
    }

    private func startRace() {
        onStart?()
    }
}
