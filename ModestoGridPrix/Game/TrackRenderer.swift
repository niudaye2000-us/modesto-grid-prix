// TrackRenderer.swift
// ModestoGridPrix
//
// Builds the SpriteKit nodes that draw the track: grass background, the tarmac
// ribbon (a thick stroked closed path), red/white kerb edges, the start/finish
// line, and a dashed racing-line hint. All drawn programmatically — no assets.

import SpriteKit

enum TrackRenderer {

    /// Returns a node containing the full static track art, positioned in world
    /// space. Add it to the world/camera-content node.
    static func buildNode(for track: Track) -> SKNode {
        let root = SKNode()
        root.zPosition = -100

        let path = closedPath(track.centerline)

        // 1. Grass background (big rectangle behind everything).
        let b = track.bounds
        let grass = SKShapeNode(rect: b)
        grass.fillColor = SKColor(red: 0.20, green: 0.45, blue: 0.22, alpha: 1)
        grass.strokeColor = .clear
        grass.zPosition = -100
        root.addChild(grass)

        // 2. Kerb underlay (slightly wider than tarmac, red/white striped look
        //    approximated with a light border band).
        let kerb = SKShapeNode(path: path)
        kerb.strokeColor = SKColor(white: 0.95, alpha: 1)
        kerb.lineWidth = (track.halfWidth + 10) * 2
        kerb.lineCap = .round
        kerb.lineJoin = .round
        kerb.fillColor = .clear
        kerb.zPosition = -90
        root.addChild(kerb)

        // 3. Tarmac ribbon.
        let tarmac = SKShapeNode(path: path)
        tarmac.strokeColor = SKColor(white: 0.26, alpha: 1)
        tarmac.lineWidth = track.halfWidth * 2
        tarmac.lineCap = .round
        tarmac.lineJoin = .round
        tarmac.fillColor = .clear
        tarmac.zPosition = -80
        root.addChild(tarmac)

        // 4. Center dashed racing-line hint.
        let center = SKShapeNode(path: path)
        center.strokeColor = SKColor(white: 1.0, alpha: 0.25)
        center.lineWidth = 4
        center.lineCap = .round
        if let dashed = path.copy(dashingWithPhase: 0, lengths: [26, 34]) as CGPath? {
            center.path = dashed
        }
        center.fillColor = .clear
        center.zPosition = -70
        root.addChild(center)

        // 5. Start / finish line (checkered band across the track at waypoint 0).
        root.addChild(startFinishLine(for: track))

        return root
    }

    private static func closedPath(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }

    private static func startFinishLine(for track: Track) -> SKNode {
        let node = SKNode()
        let center = track.startLineA
        let heading = track.startLineHeading
        // Perpendicular across the track.
        let perp = CGPoint(x: cos(heading + .pi / 2), y: sin(heading + .pi / 2))
        let along = CGPoint(x: cos(heading), y: sin(heading))

        let squares = 10
        let sq = (track.halfWidth * 2) / CGFloat(squares)
        let depth: CGFloat = sq
        for i in 0..<squares {
            for j in 0..<2 {
                let isWhite = (i + j) % 2 == 0
                let offsetAcross = (CGFloat(i) - CGFloat(squares) / 2 + 0.5) * sq
                let offsetAlong = (CGFloat(j) - 0.5) * depth
                let pos = center + perp * offsetAcross + along * offsetAlong
                let cell = SKShapeNode(rectOf: CGSize(width: sq, height: depth))
                cell.position = pos
                cell.zRotation = heading
                cell.fillColor = isWhite ? .white : SKColor(white: 0.1, alpha: 1)
                cell.strokeColor = .clear
                cell.zPosition = -60
                node.addChild(cell)
            }
        }
        return node
    }
}
