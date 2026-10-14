# Modesto Grid Prix

A top-down, F1-style arcade racing game for iOS, built with **SpriteKit** in pure
Swift. Steer by tilting the phone, race AI opponents around a circuit, and chase
your best lap.

> Original game — not affiliated with Formula 1® or any real team/driver. Cars,
> teams, and tracks are fictional.

## Status — v1 (code complete, pending first Xcode build)

The full game is written (16 Swift files). Not yet compiled in Xcode — create
the project and add the files per **Building** below, then build to a device.

### Features

- One closed-circuit track (tarmac, grass run-off, kerbs, start/finish line)
- Player car: tilt-to-steer + on-screen accelerate / brake
- Arcade physics: acceleration, grip, drifting feel, off-track slowdown
- 3 AI opponents that follow the racing line
- Laps, lap timer, best lap, live position among all cars
- Start countdown (3-2-1-GO), finish + results screen
- Main menu → race → results
- All graphics drawn programmatically (no external art assets)

Planned later: multiple tracks, difficulty levels, tyre/fuel/pit stops,
on-screen-button steering option, sound, Game Center leaderboards.

## Architecture

```
ModestoGridPrix/
  Models/   Track, Car (state + physics params), RaceConfig, GameConstants
  Game/     Physics, AI driver, race/lap logic, track geometry + rendering
  Scenes/   MenuScene, RaceScene (gameplay + HUD), ResultsScene
  ModestoGridPrixApp.swift  @main (SwiftUI host for the SpriteKit view)
  GameView.swift            SwiftUI SpriteView wrapper
```

Built with SpriteKit hosted in SwiftUI (`SpriteView`), so the app shell is SwiftUI
and the game runs in a SpriteKit scene.

## Controls

- **Steer:** tilt the device left/right (CoreMotion).
- **Accelerate / Brake:** on-screen buttons (bottom corners).

## Building (Xcode)

This repo contains the Swift source only. Create the Xcode project and add these
files:

1. Xcode → File → New → Project → iOS → **App** (SwiftUI; we host SpriteKit inside)
   - Product Name: `ModestoGridPrix`, Interface: **SwiftUI**, Language: **Swift**
   - Uncheck "Create Git repository" (this repo already has one)
2. Delete the template `ContentView.swift` and `ModestoGridPrixApp.swift`.
3. Drag the folders (`Models`, `Game`, `Scenes`) and the two root `.swift` files
   into the project ("Create groups", app target checked).
4. Add the motion usage string (see `Info-permissions.md`) — needed for tilt steering.
5. Build and run on a **real device** (tilt steering needs the gyroscope; the
   Simulator has no motion).

> SpriteKit and CoreMotion are part of iOS — no external packages.
