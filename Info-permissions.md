# Required permission & build settings

Add in Xcode (target → **Info** tab, or the generated `Info.plist`).

## Usage description key

Tilt steering uses CoreMotion. On modern iOS, device-motion (accelerometer/
gyroscope) generally does not require a usage-description prompt, but adding this
key is good practice and future-proofs the app:

| Key | Suggested value |
|-----|-----------------|
| `NSMotionUsageDescription` | Modesto Grid Prix uses device motion so you can steer your car by tilting the phone. |

## Frameworks (auto-linked by `import`)

`SpriteKit`, `SwiftUI`, `CoreMotion`. All part of iOS — nothing to install.

## Build / run notes

- Run on a **real device** — tilt steering needs the gyroscope; the Simulator
  has no motion data (the game still runs, but you can't steer by tilt there).
- Deployment target: iOS 16+ is fine (SpriteView + SpriteKit are long-standing).
- Orientation: the game is designed for **landscape**. Set the target's supported
  orientations to Landscape Left/Right for the best experience.
