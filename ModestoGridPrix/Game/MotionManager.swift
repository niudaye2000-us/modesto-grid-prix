// MotionManager.swift
// ModestoGridPrix
//
// Reads device tilt via CoreMotion and converts it to a steering value in
// -1 (left) ... 1 (right). The game runs in landscape; the player tilts the
// phone like a steering wheel (roll).
//
// On a real device: start() begins updates; `steer` is read each frame. On the
// Simulator (no motion), steer stays 0 — the game still runs.

import CoreMotion
import CoreGraphics

final class MotionManager {
    private let motion = CMMotionManager()
    /// Calibrated "neutral" roll captured at race start so any hold angle = straight.
    private var neutralRoll: Double?

    /// Current steering, -1...1. Updated from the latest motion sample on read.
    var steer: CGFloat {
        guard let data = motion.deviceMotion else { return 0 }
        // In landscape, device roll maps to left/right lean. gravity.y works
        // well as a tilt proxy and is stable across landscape orientations.
        let raw = data.gravity.y
        let neutral = neutralRoll ?? 0
        var value = raw - neutral

        // Dead zone + scale to full lock.
        let dz = Double(GameConstants.tiltDeadZone)
        if abs(value) < dz { return 0 }
        value -= value > 0 ? dz : -dz
        let scaled = value / Double(GameConstants.tiltFullLock)
        return CGFloat(max(-1, min(1, scaled)))
    }

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates()
    }

    /// Capture the current hold angle as "straight" (call once racing begins).
    func calibrate() {
        if let data = motion.deviceMotion {
            neutralRoll = data.gravity.y
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}
