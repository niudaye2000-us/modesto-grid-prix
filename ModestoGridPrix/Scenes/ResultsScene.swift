// ResultsScene.swift
// ModestoGridPrix
//
// Shown after the race finishes: final classification (position, livery, best
// lap), the player's result highlighted, and buttons to race again or return to
// the menu.

import SpriteKit

final class ResultsScene: SKScene {

    private let order: [Car]
    private let playerId: Int
    private let againName = "again"
    private let menuName = "menu"

    init(size: CGSize, finishingOrder: [Car], playerId: Int) {
        self.order = finishingOrder
        self.playerId = playerId
        super.init(size: size)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)
        buildUI()
    }

    private func formatTime(_ t: TimeInterval) -> String {
        if t <= 0 || t == .greatestFiniteMagnitude { return "--:--" }
        let m = Int(t) / 60, s = Int(t) % 60, ms = Int((t - floor(t)) * 1000)
        return String(format: "%d:%02d.%03d", m, s, ms)
    }

    private func buildUI() {
        let cx = size.width / 2

        let header = SKLabelNode(text: "RESULTS")
        header.fontName = "AvenirNext-Heavy"
        header.fontSize = min(48, size.width * 0.07)
        header.fontColor = .white
        header.position = CGPoint(x: cx, y: size.height * 0.86)
        header.horizontalAlignmentMode = .center
        addChild(header)

        // Player's finishing place callout.
        if let playerPlace = order.firstIndex(where: { $0.id == playerId }) {
            let place = playerPlace + 1
            let suffix = ["st", "nd", "rd"][safe: place - 1] ?? "th"
            let msg = place == 1 ? "YOU WON! 🏆" : "You finished \(place)\(suffix)"
            let callout = SKLabelNode(text: msg)
            callout.fontName = "AvenirNext-Bold"
            callout.fontSize = min(30, size.width * 0.045)
            callout.fontColor = place == 1 ? SKColor(red: 1, green: 0.82, blue: 0.2, alpha: 1) : .white
            callout.position = CGPoint(x: cx, y: size.height * 0.76)
            callout.horizontalAlignmentMode = .center
            addChild(callout)
        }

        // Classification rows.
        let startY = size.height * 0.66
        let rowH: CGFloat = min(42, size.height * 0.085)
        for (i, car) in order.enumerated() {
            let y = startY - CGFloat(i) * rowH
            let isPlayer = car.id == playerId
            let row = SKNode()
            row.position = CGPoint(x: cx, y: y)
            addChild(row)

            let bg = SKShapeNode(rectOf: CGSize(width: min(560, size.width * 0.8), height: rowH - 6), cornerRadius: 8)
            bg.fillColor = isPlayer ? SKColor(white: 1, alpha: 0.14) : SKColor(white: 1, alpha: 0.05)
            bg.strokeColor = .clear
            row.addChild(bg)

            let halfW = min(560, size.width * 0.8) / 2 - 16

            let pos = SKLabelNode(text: "\(i + 1)")
            pos.fontName = "AvenirNext-Bold"; pos.fontSize = 20; pos.fontColor = .white
            pos.horizontalAlignmentMode = .left; pos.verticalAlignmentMode = .center
            pos.position = CGPoint(x: -halfW, y: 0)
            row.addChild(pos)

            let swatch = SKShapeNode(rectOf: CGSize(width: 18, height: 18), cornerRadius: 3)
            swatch.fillColor = CarNode.color(car.livery.colorHex)
            swatch.strokeColor = .clear
            swatch.position = CGPoint(x: -halfW + 36, y: 0)
            row.addChild(swatch)

            let name = SKLabelNode(text: car.livery.name + (isPlayer ? " (You)" : ""))
            name.fontName = "AvenirNext-Medium"; name.fontSize = 18; name.fontColor = .white
            name.horizontalAlignmentMode = .left; name.verticalAlignmentMode = .center
            name.position = CGPoint(x: -halfW + 56, y: 0)
            row.addChild(name)

            let best = SKLabelNode(text: "Best " + formatTime(car.bestLapTime))
            best.fontName = "AvenirNext-Medium"; best.fontSize = 16
            best.fontColor = SKColor(white: 0.8, alpha: 1)
            best.horizontalAlignmentMode = .right; best.verticalAlignmentMode = .center
            best.position = CGPoint(x: halfW, y: 0)
            row.addChild(best)
        }

        // Buttons
        addButton(name: againName, text: "RACE AGAIN",
                  position: CGPoint(x: cx - 130, y: size.height * 0.12),
                  color: SKColor(red: 0.91, green: 0.25, blue: 0.16, alpha: 1))
        addButton(name: menuName, text: "MENU",
                  position: CGPoint(x: cx + 130, y: size.height * 0.12),
                  color: SKColor(white: 0.3, alpha: 1))
    }

    private func addButton(name: String, text: String, position: CGPoint, color: SKColor) {
        let b = SKShapeNode(rectOf: CGSize(width: 220, height: 60), cornerRadius: 12)
        b.name = name; b.fillColor = color; b.strokeColor = .clear; b.position = position
        addChild(b)
        let l = SKLabelNode(text: text)
        l.name = name; l.fontName = "AvenirNext-Bold"; l.fontSize = 24; l.fontColor = .white
        l.verticalAlignmentMode = .center; l.position = position
        addChild(l)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let name = atPoint(t.location(in: self)).name
        if name == againName {
            let race = RaceScene(size: size); race.scaleMode = .resizeFill
            view?.presentScene(race, transition: .fade(withDuration: 0.4))
        } else if name == menuName {
            let menu = MenuScene(size: size); menu.scaleMode = .resizeFill
            view?.presentScene(menu, transition: .fade(withDuration: 0.4))
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
