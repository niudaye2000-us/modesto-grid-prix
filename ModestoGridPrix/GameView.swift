// GameView.swift
// ModestoGridPrix
//
// SwiftUI wrapper that hosts the SpriteKit game via SpriteView. It presents the
// MenuScene first; scenes transition among themselves (Menu → Race → Results)
// by calling scene.view?.presentScene(...).

import SwiftUI
import SpriteKit

struct GameView: View {
    var body: some View {
        GeometryReader { geo in
            SpriteView(scene: makeMenuScene(size: geo.size))
                .ignoresSafeArea()
        }
    }

    private func makeMenuScene(size: CGSize) -> SKScene {
        // Fall back to a sensible landscape size if geometry is zero at first.
        let s = size.width > 0 && size.height > 0 ? size : CGSize(width: 844, height: 390)
        let scene = MenuScene(size: s)
        scene.scaleMode = .resizeFill
        return scene
    }
}

#Preview {
    GameView()
}
