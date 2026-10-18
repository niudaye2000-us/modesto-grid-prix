// GameView.swift
// ModestoGridPrix
//
// Top-level SwiftUI navigation. The race is now full 3D (SceneKit), while the
// menu and results stay as lightweight SpriteKit screens. Because SceneKit and
// SpriteKit can't present into each other, navigation is driven here in SwiftUI
// state instead of SKScene-to-SKScene transitions.

import SwiftUI
import SpriteKit
import SceneKit

struct GameView: View {

    private enum Screen {
        case menu
        case race
        case results(order: [Car], playerId: Int)
    }

    @State private var screen: Screen = .menu

    var body: some View {
        GeometryReader { geo in
            let size = geo.size.width > 0 && geo.size.height > 0 ? geo.size : CGSize(width: 844, height: 390)
            Group {
                switch screen {
                case .menu:
                    SpriteView(scene: makeMenuScene(size: size))
                        .ignoresSafeArea()

                case .race:
                    Race3DView { order, playerId in
                        screen = .results(order: order, playerId: playerId)
                    }
                    .ignoresSafeArea()

                case let .results(order, playerId):
                    SpriteView(scene: makeResultsScene(size: size, order: order, playerId: playerId))
                        .ignoresSafeArea()
                }
            }
        }
    }

    private func makeMenuScene(size: CGSize) -> SKScene {
        let scene = MenuScene(size: size)
        scene.scaleMode = .resizeFill
        scene.onStart = { screen = .race }
        return scene
    }

    private func makeResultsScene(size: CGSize, order: [Car], playerId: Int) -> SKScene {
        let scene = ResultsScene(size: size, finishingOrder: order, playerId: playerId)
        scene.scaleMode = .resizeFill
        scene.onRaceAgain = { screen = .race }
        scene.onMenu = { screen = .menu }
        return scene
    }
}

#Preview {
    GameView()
}
