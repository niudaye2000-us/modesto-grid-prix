// GameConstants.swift
// ModestoGridPrix
//
// Central tuning values for the arcade physics and gameplay. Kept in one place
// so the car "feel" is easy to adjust.

import CoreGraphics

enum GameConstants {

    // MARK: Car physics (arcade, points-per-second in scene units)

    /// Forward acceleration while the throttle is held (units/s^2). Shared baseline (AI).
    static let enginePower: CGFloat = 2500
    /// Player gets a stronger launch so they can keep up with / pass the field.
    static let playerEnginePower: CGFloat = 4200
    /// Player top speed (higher than AI top speed so the player can run them down).
    static let playerMaxSpeed: CGFloat = 1150
    /// Deceleration while braking (units/s^2).
    static let brakePower: CGFloat = 900
    /// Passive drag when neither accelerating nor braking (fraction/sec).
    static let rollingDrag: CGFloat = 0.6
    /// Top speed on tarmac (units/s).
    static let maxSpeed: CGFloat = 1000
    /// How quickly the car can rotate (radians/sec) at speed.
    static let steerRate: CGFloat = 0.5
    /// Grip: how fast sideways velocity is bled off (higher = less drift).
    static let grip: CGFloat = 6.0

    // MARK: Off-track penalty

    /// Speed multiplier cap when off the tarmac (on grass).
    static let offTrackMaxSpeed: CGFloat = 300
    /// Extra drag applied when off track (fraction/sec).
    static let offTrackDrag: CGFloat = 2.2

    // MARK: Steering input

    /// Tilt angle (radians) that maps to full steering lock.
    static let tiltFullLock: CGFloat = 0.5
    /// Dead zone for tilt so a level-ish phone drives straight.
    static let tiltDeadZone: CGFloat = 0.04

    // MARK: Track geometry

    /// Half-width of the drivable tarmac (track is 2× this wide).
    static let trackHalfWidth: CGFloat = 120
    /// Spacing between generated racing-line waypoints along the centerline.
    static let waypointSpacing: CGFloat = 90

    // MARK: Camera

    /// How tightly the camera follows the player (0–1 per frame lerp).
    static let cameraLerp: CGFloat = 0.12
    /// Camera zoom (scene scale). >1 zooms out to show more track.
    static let cameraZoom: CGFloat = 1.6

    // MARK: Race

    static let defaultLaps = 3
    static let defaultOpponents = 3
    static let countdownSeconds = 3
}

// MARK: - Small CG helpers used across the game

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }

    var length: CGFloat { (x * x + y * y).squareRoot() }
    func distance(to p: CGPoint) -> CGFloat { (self - p).length }
    var angle: CGFloat { atan2(y, x) }
    func normalized() -> CGPoint {
        let l = length
        return l > 0 ? CGPoint(x: x / l, y: y / l) : .zero
    }
}

/// Shortest signed difference between two angles, in (-π, π].
func angleDelta(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
    var d = to - from
    while d > .pi { d -= 2 * .pi }
    while d < -.pi { d += 2 * .pi }
    return d
}
