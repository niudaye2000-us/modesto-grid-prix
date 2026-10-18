// CarPhysics.swift
// ModestoGridPrix
//
// Arcade car physics. Each frame we take a car's throttle/brake/steer inputs and
// integrate position/heading/velocity. Model (top-down):
//   • Throttle adds forward force along the heading; brake decelerates.
//   • Steering rotates the heading, scaled by how fast we're going (you can't
//     turn a parked car; turn-in sharpens with speed up to a cap).
//   • "Grip" bleeds off the sideways component of velocity so the car tends to
//     go where it points (low grip => more drift).
//   • Off the tarmac: lower top speed + extra drag (penalty for cutting).
//
// Convention: heading 0 = +x. Units are scene points; dt in seconds.

import CoreGraphics

enum CarPhysics {

    static func step(_ car: Car, on track: Track, dt: CGFloat) {
        guard !car.finished else {
            // Coast to a stop after finishing.
            car.velocity = car.velocity * max(0, 1 - 2.0 * dt)
            car.position = car.position + car.velocity * dt
            return
        }

        let forward = CGPoint(x: cos(car.heading), y: sin(car.heading))

        // Current speed in the forward direction (can be negative if reversing).
        let fwdSpeed = car.velocity.x * forward.x + car.velocity.y * forward.y

        let onTrack = track.isOnTrack(car.position)
        // Player gets higher power + top speed so they can run down the AI field.
        let enginePower = car.isPlayer ? GameConstants.playerEnginePower : GameConstants.enginePower
        let carMaxSpeed = car.isPlayer ? GameConstants.playerMaxSpeed : GameConstants.maxSpeed
        let topSpeed = onTrack ? carMaxSpeed : GameConstants.offTrackMaxSpeed

        // --- Longitudinal: throttle / brake / drag -------------------------
        var newFwd = fwdSpeed
        if car.throttle > 0 {
            newFwd += enginePower * car.throttle * dt
        }
        if car.brake > 0 {
            // Brake reduces forward speed toward 0 (and a little reverse).
            newFwd -= GameConstants.brakePower * car.brake * dt
            if newFwd < -120 { newFwd = -120 }
        }
        // Passive + off-track drag when coasting.
        var drag = GameConstants.rollingDrag
        if !onTrack { drag += GameConstants.offTrackDrag }
        if car.throttle == 0 {
            newFwd -= newFwd * drag * dt
        }
        // Clamp to top speed.
        newFwd = max(-120, min(topSpeed, newFwd))

        // --- Steering: rotate heading, scaled by speed --------------------
        // Steering authority ramps up with speed then saturates.
        let speedFactor = min(1, abs(newFwd) / 150)
        let turn = car.steer * GameConstants.steerRate * speedFactor * dt
        // Reverse the turn direction when going backwards (feels natural).
        car.heading += (newFwd >= 0 ? turn : -turn)

        // --- Reassemble velocity with grip --------------------------------
        let newForward = CGPoint(x: cos(car.heading), y: sin(car.heading))
        // Desired velocity: purely along the new heading at newFwd.
        let desired = newForward * newFwd
        // Grip blends current velocity toward the desired (heading-aligned) one.
        let gripFactor = min(1, GameConstants.grip * dt)
        car.velocity = CGPoint(
            x: car.velocity.x + (desired.x - car.velocity.x) * gripFactor,
            y: car.velocity.y + (desired.y - car.velocity.y) * gripFactor
        )

        // --- Integrate position -------------------------------------------
        car.position = car.position + car.velocity * dt
    }
}
