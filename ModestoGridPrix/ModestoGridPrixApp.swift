// ModestoGridPrixApp.swift
// ModestoGridPrix
//
// App entry point. Hosts the SpriteKit game inside a SwiftUI shell. The game is
// landscape; set the target's supported orientations to Landscape Left/Right.

import SwiftUI

@main
struct ModestoGridPrixApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
