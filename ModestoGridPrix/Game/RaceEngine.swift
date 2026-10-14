// RaceEngine.swift
// ModestoGridPrix
//
// The headless race simulation: owns the cars + track, steps physics for every
// car each frame, counts laps, times laps, orders live positions, and detects
// the finish. The SpriteKit scene drives it (feeds player input, reads state to
// move the visual nodes) but all rules live here.
//
// Lap counting: each car tracks its nextWaypoint around the centerline. When it
// advances through waypoint 0 (crosses the start/finish line going forward) a
// lap is completed.

import CoreGraphics
import Foundation

final class RaceEngine {

    enum Phase: Equatable {
        case countdown(remaining: Int)   // 3,2,1
        case racing
        case finished
    }

    let track: Track
    let config: RaceConfig
    private(set) var cars: [Car] = []
    private(set) var phase: Phase = .countdown(remaining: GameConstants.countdownSeconds)

    /// Live finishing order once the race ends (best first).
    private(set) var finishingOrder: [Car] = []

    private var elapsed: TimeInterval = 0
    private var countdownClock: TimeInterval = 0

    var player: Car { cars.first(where: { $0.isPlayer })! }

    init(track: Track, config: RaceConfig) {
        self.track = track
        self.config = config
        buildGrid()
    }

    private func buildGrid() {
        let total = config.opponents + 1
        let grid = TrackBuilder.gridPositions(on: track, count: total)
        var liveries = Livery.all
        // Player gets the first livery (Modesto Red); shuffle the rest a bit.
        for i in 0..<total {
            let pos = grid[i]
            let isPlayer = (i == 0)
            let livery = liveries[i % liveries.count]
            let car = Car(id: i, livery: livery, isPlayer: isPlayer,
                          position: pos.point, heading: pos.heading)
            // Start just before the line so the first crossing counts lap 1.
            car.nextWaypoint = 0
            car.lap = 0
            cars.append(car)
        }
        _ = liveries
    }

    // MARK: Per-frame update

    /// Advance the whole race by dt seconds. `playerThrottle/Brake/Steer` are the
    /// current player inputs (from buttons + tilt).
    func update(dt: TimeInterval, playerThrottle: CGFloat, playerBrake: CGFloat, playerSteer: CGFloat) {
        switch phase {
        case .countdown(let remaining):
            countdownClock += dt
            if countdownClock >= 1 {
                countdownClock -= 1
                let next = remaining - 1
                phase = next <= 0 ? .racing : .countdown(remaining: next)
                if case .racing = phase {
                    // Start the clock + each car's first lap timer.
                    elapsed = 0
                    for c in cars { c.currentLapStart = 0 }
                }
            }
            return

        case .finished:
            // Let cars coast; still integrate so they visibly roll to a stop.
            for c in cars { CarPhysics.step(c, on: track, dt: CGFloat(dt)) }
            return

        case .racing:
            break
        }

        elapsed += dt

        // Player inputs.
        let p = player
        if !p.finished {
            p.throttle = max(0, min(1, playerThrottle))
            p.brake = max(0, min(1, playerBrake))
            p.steer = max(-1, min(1, playerSteer))
        } else {
            p.resetInputs()
        }

        // AI inputs.
        var opp = 0
        for c in cars where !c.isPlayer {
            if c.finished { c.resetInputs() }
            else { AIDriver.drive(c, on: track, skill: AIDriver.skill(forOpponentIndex: opp, of: config.opponents)) }
            opp += 1
        }

        // Step physics + lap logic for every car.
        for c in cars {
            CarPhysics.step(c, on: track, dt: CGFloat(dt))
            updateLapProgress(c)
        }

        updatePositions()

        if cars.allSatisfy({ $0.finished }) {
            phase = .finished
            finishingOrder = cars.sorted { $0.finishTime < $1.finishTime }
        }
    }

    // MARK: Lap counting + timing

    // Per-car progress tracking for robust lap counting.
    private var lastIndex: [Int: Int] = [:]   // last nearest waypoint index seen
    private var reachedHalf: [Int: Bool] = [:] // has car reached the far half this lap

    private func updateLapProgress(_ car: Car) {
        guard !car.finished else { return }
        let n = track.waypointCount
        let here = track.nearestIndex(to: car.position)
        let half = n / 2

        // Live fractional progress for ordering: laps*n + current index.
        car.progress = CGFloat(car.lap) * CGFloat(n) + CGFloat(here)
        car.nextWaypoint = (here + 1) % n

        // Mark when the car has gone past the halfway point of the loop; a lap is
        // only valid once it has, which prevents counting laps by wiggling back
        // and forth across the start line.
        if here >= half && here < n - 2 {
            reachedHalf[car.id] = true
        }

        let prev = lastIndex[car.id] ?? here
        lastIndex[car.id] = here

        // Detect a forward crossing of the start/finish line: index wraps from
        // the high end (near n-1) back down to the low end (near 0).
        let wrappedForward = prev >= n - 3 && here <= 2
        if wrappedForward {
            if car.lap == 0 {
                // Leaving the grid onto lap 1 — start the timer, no lap counted.
                car.lap = 1
                car.currentLapStart = elapsed
                reachedHalf[car.id] = false
            } else if reachedHalf[car.id] == true {
                completeLap(car)
                reachedHalf[car.id] = false
            }
        }
    }

    private func completeLap(_ car: Car) {
        let lapTime = elapsed - car.currentLapStart
        car.lastLapTime = lapTime
        car.lapTimes.append(lapTime)
        car.bestLapTime = min(car.bestLapTime, lapTime)
        car.currentLapStart = elapsed
        car.lap += 1

        if car.lap > config.laps {
            car.finished = true
            car.finishTime = elapsed
        }
    }

    // MARK: Positions

    private func updatePositions() {
        // Sort by progress (desc); finished cars rank by finishTime.
        let order = cars.sorted { a, b in
            if a.finished && b.finished { return a.finishTime < b.finishTime }
            if a.finished != b.finished { return a.finished }
            return a.progress > b.progress
        }
        for (i, c) in order.enumerated() { c.livePosition = i + 1 }
    }

    var totalCars: Int { cars.count }
    var raceElapsed: TimeInterval { elapsed }
}
