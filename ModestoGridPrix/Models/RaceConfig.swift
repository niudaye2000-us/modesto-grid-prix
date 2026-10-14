// RaceConfig.swift
// ModestoGridPrix
//
// Configuration for a single race.

import Foundation

struct RaceConfig {
    var laps: Int = GameConstants.defaultLaps
    var opponents: Int = GameConstants.defaultOpponents

    static let `default` = RaceConfig()
}

/// Fictional teams/liveries (no real F1 trademarks). Used to color cars and
/// label results.
struct Livery {
    let name: String
    let colorHex: UInt32

    static let all: [Livery] = [
        Livery(name: "Modesto Red",   colorHex: 0xE8402A),
        Livery(name: "Delta Blue",    colorHex: 0x2A6CE8),
        Livery(name: "Valley Green",  colorHex: 0x27B36B),
        Livery(name: "Sierra Gold",   colorHex: 0xE8B52A),
        Livery(name: "Night Silver",  colorHex: 0xB9C0C8),
        Livery(name: "Orchard Orange", colorHex: 0xF07A1E),
    ]
}
