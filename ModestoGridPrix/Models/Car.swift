// Car.swift
// ModestoGridPrix
//
// A car's physical state (position/heading/velocity) plus its race progress
// (lap, waypoint index, lap times). Pure data — physics stepping lives in
// Game/CarPhysics.swift, and the visual node is created in the scene.

import CoreGraphics
import Foundation

final class Car {
    let id: Int
    let livery: Livery
    let isPlayer: Bool

    // Physics state
    var position: CGPoint
    var heading: CGFloat        // radians; 0 = +x
    var velocity: CGPoint = .zero

    // Driver inputs for this frame (set by player controller or AI)
    var throttle: CGFloat = 0   // 0...1
    var brake: CGFloat = 0      // 0...1
    var steer: CGFloat = 0      // -1 (left) ... 1 (right)

    // Race progress
    var lap: Int = 0
    var nextWaypoint: Int = 0   // index into the track's racing line
    var finished = false
    var finishTime: TimeInterval = 0

    // Lap timing
    var currentLapStart: TimeInterval = 0
    var lastLapTime: TimeInterval = 0
    var bestLapTime: TimeInterval = .greatestFiniteMagnitude
    var lapTimes: [TimeInterval] = []

    /// Signed progress used only for live position ordering:
    /// lap * waypointCount + nextWaypoint, plus fractional distance.
    var progress: CGFloat = 0

    /// Live race position (1 = leading), updated each frame by the engine.
    var livePosition: Int = 1

    var speed: CGFloat { velocity.length }

    init(id: Int, livery: Livery, isPlayer: Bool, position: CGPoint, heading: CGFloat) {
        self.id = id
        self.livery = livery
        self.isPlayer = isPlayer
        self.position = position
        self.heading = heading
    }

    func resetInputs() {
        throttle = 0; brake = 0; steer = 0
    }
}
