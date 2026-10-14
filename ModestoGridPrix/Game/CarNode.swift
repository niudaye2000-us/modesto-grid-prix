// CarNode.swift
// ModestoGridPrix
//
// A programmatically drawn top-down open-wheel car (no art assets). The node's
// zRotation follows the car heading; +x is "forward" (nose points along +x at
// zRotation 0, matching the physics convention).

import SpriteKit

final class CarNode: SKNode {
    let carId: Int

    init(livery: Livery) {
        self.carId = -1
        super.init()
        build(color: Self.color(livery.colorHex))
    }

    init(carId: Int, livery: Livery) {
        self.carId = carId
        super.init()
        build(color: Self.color(livery.colorHex))
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build(color: SKColor) {
        // Dimensions (points). Car is longer than wide; nose toward +x.
        let length: CGFloat = 54
        let width: CGFloat = 24

        // Four tyres (dark rounded rects) at the corners.
        let tyreW: CGFloat = 14, tyreH: CGFloat = 8
        let tyreOffsetsX: [CGFloat] = [length * 0.3, -length * 0.3]
        let tyreOffsetsY: [CGFloat] = [width * 0.55, -width * 0.55]
        for ox in tyreOffsetsX {
            for oy in tyreOffsetsY {
                let tyre = SKShapeNode(rectOf: CGSize(width: tyreW, height: tyreH), cornerRadius: 3)
                tyre.fillColor = SKColor(white: 0.08, alpha: 1)
                tyre.strokeColor = .clear
                tyre.position = CGPoint(x: ox, y: oy)
                tyre.zPosition = 1
                addChild(tyre)
            }
        }

        // Body: a tapered shape (nose + cockpit + rear).
        let body = SKShapeNode(path: Self.bodyPath(length: length, width: width))
        body.fillColor = color
        body.strokeColor = SKColor(white: 0, alpha: 0.3)
        body.lineWidth = 1.5
        body.zPosition = 2
        addChild(body)

        // Front wing (thin bar near the nose).
        let wing = SKShapeNode(rectOf: CGSize(width: 5, height: width + 6), cornerRadius: 2)
        wing.fillColor = SKColor(white: 0.12, alpha: 1)
        wing.strokeColor = .clear
        wing.position = CGPoint(x: length * 0.5, y: 0)
        wing.zPosition = 2.5
        addChild(wing)

        // Cockpit (small dark oval).
        let cockpit = SKShapeNode(ellipseOf: CGSize(width: 16, height: 12))
        cockpit.fillColor = SKColor(white: 0.05, alpha: 1)
        cockpit.strokeColor = .clear
        cockpit.position = CGPoint(x: -2, y: 0)
        cockpit.zPosition = 3
        addChild(cockpit)
    }

    private static func bodyPath(length: CGFloat, width: CGFloat) -> CGPath {
        let hl = length / 2, hw = width / 2
        let p = CGMutablePath()
        p.move(to: CGPoint(x: hl, y: 0))                  // nose tip
        p.addLine(to: CGPoint(x: hl * 0.5, y: hw * 0.7))
        p.addLine(to: CGPoint(x: -hl * 0.6, y: hw))
        p.addLine(to: CGPoint(x: -hl, y: hw * 0.8))       // rear left
        p.addLine(to: CGPoint(x: -hl, y: -hw * 0.8))      // rear right
        p.addLine(to: CGPoint(x: -hl * 0.6, y: -hw))
        p.addLine(to: CGPoint(x: hl * 0.5, y: -hw * 0.7))
        p.closeSubpath()
        return p
    }

    static func color(_ hex: UInt32) -> SKColor {
        SKColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
