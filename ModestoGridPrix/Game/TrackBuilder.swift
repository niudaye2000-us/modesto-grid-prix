// TrackBuilder.swift
// ModestoGridPrix
//
// Procedurally generates a closed circuit centerline, then resamples it at a
// fixed spacing so the waypoints are evenly distributed (good for AI + lap
// progress). The shape is a smooth, wavy loop — a stylized road course.

import CoreGraphics

enum TrackBuilder {

    /// Build the default v1 circuit.
    static func defaultTrack() -> Track {
        // A looping shape defined by radius modulation around a center.
        // Base ellipse + a few sine harmonics gives natural-looking corners.
        let cx: CGFloat = 0
        let cy: CGFloat = 0
        let baseR: CGFloat = 1400
        let aspect: CGFloat = 0.7   // squash vertically for a wider circuit

        var raw: [CGPoint] = []
        let samples = 240
        for i in 0..<samples {
            let t = CGFloat(i) / CGFloat(samples) * 2 * .pi
            // Radius wobble creates corners of varying tightness.
            let r = baseR
                + 320 * sin(2 * t)
                + 180 * sin(3 * t + 0.8)
                - 140 * sin(5 * t + 1.6)
            let x = cx + r * cos(t)
            let y = cy + r * aspect * sin(t)
            raw.append(CGPoint(x: x, y: y))
        }

        let centerline = resample(closedLoop: raw, spacing: GameConstants.waypointSpacing)
        return Track(centerline: centerline, halfWidth: GameConstants.trackHalfWidth)
    }

    /// Resample a closed polyline so points are ~`spacing` apart, preserving the
    /// loop. Produces evenly spaced waypoints regardless of the input density.
    static func resample(closedLoop pts: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard pts.count > 2, spacing > 0 else { return pts }
        // Total perimeter.
        var total: CGFloat = 0
        for i in 0..<pts.count {
            total += pts[i].distance(to: pts[(i + 1) % pts.count])
        }
        let count = max(8, Int((total / spacing).rounded()))
        let step = total / CGFloat(count)

        var result: [CGPoint] = []
        var segIndex = 0
        var segStart = pts[0]
        var segEnd = pts[1 % pts.count]
        var segLen = segStart.distance(to: segEnd)
        var distAlongSeg: CGFloat = 0

        for _ in 0..<count {
            // Advance to the segment containing the target distance.
            while distAlongSeg > segLen {
                distAlongSeg -= segLen
                segIndex += 1
                segStart = pts[segIndex % pts.count]
                segEnd = pts[(segIndex + 1) % pts.count]
                segLen = segStart.distance(to: segEnd)
                if segLen == 0 { segLen = 0.0001 }
            }
            let f = distAlongSeg / segLen
            result.append(CGPoint(x: segStart.x + (segEnd.x - segStart.x) * f,
                                  y: segStart.y + (segEnd.y - segStart.y) * f))
            distAlongSeg += step
        }
        return result
    }

    /// Starting grid positions: staggered behind the start line, two columns.
    static func gridPositions(on track: Track, count: Int) -> [(point: CGPoint, heading: CGFloat)] {
        let heading = track.startLineHeading
        let forward = CGPoint(x: cos(heading), y: sin(heading))
        let right = CGPoint(x: cos(heading - .pi / 2), y: sin(heading - .pi / 2))
        var out: [(CGPoint, CGFloat)] = []
        let rowGap: CGFloat = 110
        let colGap: CGFloat = 55
        for i in 0..<count {
            let row = i / 2
            let col = i % 2 == 0 ? -1 : 1
            // Place behind the start line (negative forward).
            let base = track.startLineA
                - forward * (CGFloat(row) * rowGap + 60)
                + right * (CGFloat(col) * colGap)
            out.append((base, heading))
        }
        return out
    }
}
