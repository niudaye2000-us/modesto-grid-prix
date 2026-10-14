// Track.swift
// ModestoGridPrix
//
// A closed circuit defined by a centerline of waypoints. The track is the band
// of tarmac within `trackHalfWidth` of the centerline. The start/finish line is
// at waypoint 0. The racing line (for AI and lap counting) is the centerline.

import CoreGraphics

struct Track {
    /// Ordered centerline points forming a closed loop (last connects to first).
    let centerline: [CGPoint]
    let halfWidth: CGFloat

    var waypointCount: Int { centerline.count }

    /// Heading (radians) of the track at waypoint i, toward the next waypoint.
    func heading(at i: Int) -> CGFloat {
        let a = centerline[i]
        let b = centerline[(i + 1) % waypointCount]
        return (b - a).angle
    }

    /// Start/finish is between waypoint 0 and waypoint 1.
    var startLineA: CGPoint { centerline[0] }
    var startLineHeading: CGFloat { heading(at: 0) }

    /// The nearest centerline index to a point (brute force; fine for v1 sizes).
    func nearestIndex(to p: CGPoint) -> Int {
        var best = 0
        var bestD = CGFloat.greatestFiniteMagnitude
        for (i, c) in centerline.enumerated() {
            let d = c.distance(to: p)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// True if a point is on the tarmac (within halfWidth of the nearest segment).
    func isOnTrack(_ p: CGPoint) -> Bool {
        distanceToCenterline(p) <= halfWidth
    }

    /// Perpendicular distance from a point to the centerline polyline.
    func distanceToCenterline(_ p: CGPoint) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for i in 0..<waypointCount {
            let a = centerline[i]
            let b = centerline[(i + 1) % waypointCount]
            best = min(best, Self.distance(from: p, toSegment: a, b: b))
        }
        return best
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, b: CGPoint) -> CGFloat {
        let ab = b - a
        let t = max(0, min(1, ((p - a).x * ab.x + (p - a).y * ab.y) / max(ab.x * ab.x + ab.y * ab.y, 0.0001)))
        let proj = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
        return p.distance(to: proj)
    }

    /// Overall bounds of the centerline (used to size/frame the world).
    var bounds: CGRect {
        guard let first = centerline.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in centerline {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let pad = halfWidth + 200
        return CGRect(x: minX - pad, y: minY - pad,
                      width: (maxX - minX) + 2 * pad, height: (maxY - minY) + 2 * pad)
    }
}
