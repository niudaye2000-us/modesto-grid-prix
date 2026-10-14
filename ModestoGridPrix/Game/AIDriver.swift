// AIDriver.swift
// ModestoGridPrix
//
// Simple but effective opponent AI. Each frame it:
//   1. Finds a lookahead target point along the racing line (centerline),
//      a little ahead of the car so steering is smooth, not twitchy.
//   2. Steers toward that target (proportional to the angle error).
//   3. Picks throttle/brake from how sharp the upcoming corner is: full
//      throttle on straights, lift/brake when the track bends hard ahead.
//   4. Nudges back toward the centerline if it has drifted wide.
//
// Per-car `skill` (0..1) scales corner speed and reaction so opponents differ.

import CoreGraphics

enum AIDriver {

    /// Set car.throttle/brake/steer for this frame.
    static func drive(_ car: Car, on track: Track, skill: CGFloat) {
        let n = track.waypointCount
        guard n > 2 else { return }

        // Advance the car's target waypoint as it passes each one.
        let here = track.nearestIndex(to: car.position)
        // Keep nextWaypoint a few points ahead of where we actually are.
        let lookaheadPoints = 2 + Int(skill * 2)   // better AI looks slightly further
        var target = (here + lookaheadPoints) % n
        car.nextWaypoint = (here + 1) % n          // used by race ordering elsewhere
        let targetPoint = track.centerline[target]

        // --- Steering: proportional to heading error toward the target -----
        let toTarget = (targetPoint - car.position)
        let desiredHeading = toTarget.angle
        let err = angleDelta(car.heading, desiredHeading)   // -pi..pi
        // Scale: full lock by ~0.6 rad error.
        car.steer = max(-1, min(1, err / 0.6))

        // --- Throttle/brake from upcoming corner sharpness -----------------
        // Measure the heading change over the next stretch of track.
        let aheadA = track.heading(at: target)
        let aheadB = track.heading(at: (target + 2) % n)
        let cornerSharpness = abs(angleDelta(aheadA, aheadB))  // radians

        // Corner speed target: sharper corner => want to be slower.
        // skill raises the speed a car is willing to carry.
        let sharpnessLimit = 0.25 + skill * 0.15
        if cornerSharpness > sharpnessLimit {
            // Needs to slow: brake if going quick, otherwise just lift.
            let overspeed = car.speed > (GameConstants.maxSpeed * (0.45 + 0.2 * skill))
            car.throttle = overspeed ? 0 : 0.5
            car.brake = overspeed ? min(1, cornerSharpness) : 0
        } else {
            car.throttle = 1
            car.brake = 0
        }

        // If the steering error is big (badly misaligned), ease off the gas.
        if abs(err) > 0.9 {
            car.throttle = min(car.throttle, 0.4)
        }

        _ = target  // (kept for clarity)
    }

    /// Per-opponent skill spread so the field isn't identical. index 0 = fastest.
    static func skill(forOpponentIndex i: Int, of count: Int) -> CGFloat {
        guard count > 1 else { return 0.8 }
        // 0.85 down to ~0.6 across the field.
        let t = CGFloat(i) / CGFloat(count - 1)
        return 0.85 - t * 0.25
    }
}
