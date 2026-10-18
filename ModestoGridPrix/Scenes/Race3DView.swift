// Race3DView.swift
// ModestoGridPrix
//
// Full 3D driver's-view race, rendered with SceneKit. It reuses the existing
// headless simulation (RaceEngine / Track / CarPhysics / AIDriver) unchanged:
// each frame we call engine.update(...) and copy every car's 2D pose onto a 3D
// node. The camera sits low, just behind and above the player's car, looking
// down the road — the "sitting in the car" view.
//
// Coordinate mapping (2D sim -> 3D world):
//   sim (x, y) ground plane, heading 0 = +x, CCW positive
//   -> SceneKit (x, 0, -y) with +Y up; yaw about Y = -heading
// so forward (heading 0, +x) points along +X and visually matches the sim.
//
// Controls (accel/brake/left/right) are drawn as a SpriteKit overlay so the
// working two-thumb buttons carry over to the 3D view.

import SwiftUI
import SceneKit
import SpriteKit
import CoreGraphics

// MARK: - SwiftUI wrapper

/// Hosts the SceneKit race and reports back when the race finishes.
struct Race3DView: UIViewRepresentable {
    /// Called once when the race is over, with the final classification.
    var onFinish: ([Car], Int) -> Void

    func makeCoordinator() -> Race3DController {
        Race3DController(onFinish: onFinish)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.antialiasingMode = .multisampling2X
        view.isPlaying = true                 // keep the render loop running
        view.rendersContinuously = true
        view.backgroundColor = UIColor(red: 0.52, green: 0.74, blue: 0.98, alpha: 1) // sky
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - The controller: owns the engine, the SceneKit scene, and the loop

final class Race3DController: NSObject, SCNSceneRendererDelegate {

    private let engine = RaceEngine(track: TrackBuilder.defaultTrack(), config: .default)
    private let onFinish: ([Car], Int) -> Void

    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private var carNodes: [Int: SCNNode] = [:]
    private weak var playerCarNode: SCNNode?

    // Input state, driven by the SpriteKit overlay buttons.
    private let input = RaceInput()
    private var buttonSteer: CGFloat = 0

    // Synthesized engine note that revs with the car.
    private let engineSound = EngineSound()

    private var lastTime: TimeInterval = 0
    private var didFinish = false

    // Overlay (HUD + buttons)
    private var overlay: RaceOverlayScene?

    init(onFinish: @escaping ([Car], Int) -> Void) {
        self.onFinish = onFinish
        super.init()
    }

    func attach(to view: SCNView) {
        buildScene()
        view.scene = scene
        view.pointOfView = cameraNode
        view.delegate = self

        let overlay = RaceOverlayScene(size: view.bounds.size.isEmpty ? CGSize(width: 844, height: 390) : view.bounds.size)
        overlay.input = input
        overlay.scaleMode = .resizeFill
        view.overlaySKScene = overlay
        self.overlay = overlay

        engineSound.start()
    }

    // MARK: Scene construction

    private func buildScene() {
        // Gradient sky background so the horizon has depth (not a flat fill).
        scene.background.contents = skyGradient()
        // Distance fog so far scenery fades into the sky — reinforces depth.
        scene.fogStartDistance = 2200
        scene.fogEndDistance = 7000
        scene.fogColor = UIColor(red: 0.80, green: 0.89, blue: 0.98, alpha: 1)

        buildLights()
        buildGround()
        buildRoad()
        buildCars()
        buildCamera()
    }

    private func buildLights() {
        // Warm key "sun": casts soft shadows and gives everything a 3D, lit look.
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light!.type = .directional
        sun.light!.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        sun.light!.intensity = 1300
        sun.light!.castsShadow = true
        sun.light!.shadowMode = .deferred
        sun.light!.shadowSampleCount = 16
        sun.light!.shadowRadius = 6
        sun.light!.shadowColor = UIColor(white: 0, alpha: 0.35)
        sun.light!.maximumShadowDistance = 4000
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(sun)

        // Cool sky fill from the opposite side so shadows aren't pure black —
        // this directional contrast is what makes volumes read as 3D.
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .directional
        fill.light!.color = UIColor(red: 0.55, green: 0.65, blue: 0.85, alpha: 1)
        fill.light!.intensity = 450
        fill.eulerAngles = SCNVector3(-Float.pi / 5, -Float.pi * 0.7, 0)
        scene.rootNode.addChildNode(fill)

        // Image-based environment lighting: a sky gradient used for ambient +
        // subtle reflections so PBR materials pick up depth.
        scene.lightingEnvironment.contents = skyGradient()
        scene.lightingEnvironment.intensity = 1.2

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.color = UIColor(red: 0.42, green: 0.47, blue: 0.55, alpha: 1)
        ambient.light!.intensity = 300
        scene.rootNode.addChildNode(ambient)
    }

    /// Vertical sky gradient image used for the background + environment light.
    private func skyGradient() -> UIImage {
        let size = CGSize(width: 4, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(red: 0.33, green: 0.55, blue: 0.9, alpha: 1).cgColor,
                          UIColor(red: 0.68, green: 0.84, blue: 0.98, alpha: 1).cgColor,
                          UIColor(red: 0.85, green: 0.92, blue: 0.98, alpha: 1).cgColor]
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray, locations: [0, 0.6, 1])!
            ctx.cgContext.drawLinearGradient(grad, start: .zero,
                                             end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    private func buildGround() {
        // Big textured grass plane with PBR so it shades across the field and
        // doesn't look like flat paper.
        let ground = SCNFloor()
        ground.reflectivity = 0.02
        let g = SCNNode(geometry: ground)
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = grassTexture()
        mat.diffuse.wrapS = .repeat; mat.diffuse.wrapT = .repeat
        mat.diffuse.contentsTransform = SCNMatrix4MakeScale(220, 220, 0)
        mat.roughness.contents = 0.95
        ground.materials = [mat]
        scene.rootNode.addChildNode(g)

        buildDistantHills()
    }

    /// A mottled grass tile so the ground has texture/variation up close.
    private func grassTexture() -> UIImage {
        let s = 64
        let size = CGSize(width: s, height: s)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(red: 0.20, green: 0.45, blue: 0.22, alpha: 1).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            // Speckle a few lighter/darker blades for variation.
            for _ in 0..<140 {
                let x = CGFloat.random(in: 0..<CGFloat(s))
                let y = CGFloat.random(in: 0..<CGFloat(s))
                let g = CGFloat.random(in: 0.35...0.55)
                c.setFillColor(UIColor(red: 0.16, green: g, blue: 0.20, alpha: 1).cgColor)
                c.fill(CGRect(x: x, y: y, width: 1.5, height: 2.5))
            }
        }
    }

    /// Low rolling hills ringing the circuit so the horizon has depth.
    private func buildDistantHills() {
        let b = engine.track.bounds
        let cx = Float(b.midX), cz = -Float(b.midY)
        let ring = Float(max(b.width, b.height)) * 0.9 + 2500
        let count = 14
        for i in 0..<count {
            let a = Float(i) / Float(count) * 2 * .pi
            let hillR = CGFloat.random(in: 600...1100)
            let hill = SCNSphere(radius: hillR)
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            let g = CGFloat.random(in: 0.32...0.42)
            m.diffuse.contents = UIColor(red: 0.14, green: g, blue: 0.20, alpha: 1)
            m.roughness.contents = 1.0
            hill.materials = [m]
            let node = SCNNode(geometry: hill)
            // Sink the sphere so only a rounded hilltop shows above the ground.
            node.position = SCNVector3(cx + cosf(a) * ring,
                                       -Float(hillR) * 0.82,
                                       cz + sinf(a) * ring)
            scene.rootNode.addChildNode(node)
        }
    }

    /// Extrude a flat road ribbon along the track centerline.
    private func buildRoad() {
        let track = engine.track
        let center = track.centerline
        let n = center.count
        guard n > 2 else { return }
        let hw = Float(track.halfWidth)

        var verts: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [Int32] = []

        // For each centerline point, compute left/right edge using the segment normal.
        func worldLeftRight(_ i: Int) -> (SCNVector3, SCNVector3) {
            let p = center[i]
            let h = track.heading(at: i)                 // radians, 0 = +x
            // Left/right perpendicular in 2D (x,y): rotate heading by +/- 90.
            let nx = CGFloat(cos(h + .pi / 2))
            let ny = CGFloat(sin(h + .pi / 2))
            let left = CGPoint(x: p.x + nx * CGFloat(hw), y: p.y + ny * CGFloat(hw))
            let right = CGPoint(x: p.x - nx * CGFloat(hw), y: p.y - ny * CGFloat(hw))
            return (sim3(left, y: 0.05), sim3(right, y: 0.05))
        }

        var vIndex: Int32 = 0
        var arcLen: CGFloat = 0
        for i in 0..<n {
            let (l, r) = worldLeftRight(i)
            verts.append(l); verts.append(r)
            normals.append(SCNVector3(0, 1, 0)); normals.append(SCNVector3(0, 1, 0))
            // UV: v runs along the track (for a dashed centerline texture later), u across.
            let seg = i == 0 ? 0 : center[i].distance(to: center[i - 1])
            arcLen += seg
            let v = Float(arcLen / 120.0)
            uvs.append(CGPoint(x: 0, y: CGFloat(v)))
            uvs.append(CGPoint(x: 1, y: CGFloat(v)))

            let next = Int32((i + 1) % n) * 2
            let cur = vIndex
            // Two triangles for the quad [curL, curR, nextL, nextR].
            indices.append(cur);     indices.append(cur + 1); indices.append(next)
            indices.append(next);    indices.append(cur + 1); indices.append(next + 1)
            vIndex += 2
        }

        let vSource = SCNGeometrySource(vertices: verts)
        let nSource = SCNGeometrySource(normals: normals)
        let tSource = SCNGeometrySource(textureCoordinates: uvs)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geo = SCNGeometry(sources: [vSource, nSource, tSource], elements: [element])

        let road = SCNMaterial()
        road.lightingModel = .physicallyBased
        road.diffuse.contents = roadTexture()
        road.diffuse.wrapT = .repeat
        road.diffuse.wrapS = .clamp
        road.roughness.contents = 0.55          // slightly glossy tarmac catches the sun
        road.metalness.contents = 0.0
        road.isDoubleSided = true
        geo.materials = [road]

        let roadNode = SCNNode(geometry: geo)
        scene.rootNode.addChildNode(roadNode)

        buildStartLine(on: track)
        buildRoadsideMarkers(on: track)
    }

    /// A simple tarmac texture with a dashed centerline and white edges.
    private func roadTexture() -> UIImage {
        let w = 128, h = 256
        let size = CGSize(width: w, height: h)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0.25, alpha: 1).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            // White edge lines.
            c.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 8, height: h))
            c.fill(CGRect(x: w - 8, y: 0, width: 8, height: h))
            // Dashed yellow centerline.
            c.setFillColor(UIColor(red: 0.95, green: 0.85, blue: 0.2, alpha: 1).cgColor)
            let dashH = h / 2
            c.fill(CGRect(x: w / 2 - 4, y: 0, width: 8, height: dashH))
        }
    }

    private func buildStartLine(on track: Track) {
        // A checkered strip across the road at waypoint 0.
        let i = 0
        let h = track.heading(at: i)
        let p = track.centerline[i]
        let plane = SCNPlane(width: CGFloat(track.halfWidth) * 2, height: 60)
        let mat = SCNMaterial()
        mat.diffuse.contents = checkerTexture()
        mat.diffuse.wrapS = .repeat
        mat.diffuse.wrapT = .repeat
        mat.lightingModel = .constant
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        node.position = sim3(p, y: 0.08)
        // Plane default faces +Z; lay it flat and align across the road.
        node.eulerAngles = SCNVector3(-Float.pi / 2, -Float(h), 0)
        scene.rootNode.addChildNode(node)
    }

    private func checkerTexture() -> UIImage {
        let n = 8, cell = 16
        let size = CGSize(width: n * cell, height: 2 * cell)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let c = ctx.cgContext
            for col in 0..<n {
                for row in 0..<2 {
                    let black = (col + row) % 2 == 0
                    c.setFillColor((black ? UIColor.black : UIColor.white).cgColor)
                    c.fill(CGRect(x: col * cell, y: row * cell, width: cell, height: cell))
                }
            }
        }
    }

    /// Roadside 3D scenery: kerbs, tyre-barrier walls, trees and the odd
    /// grandstand — all with real height so the world reads as 3D, not flat.
    private func buildRoadsideMarkers(on track: Track) {
        let center = track.centerline
        let n = center.count

        func sidePoint(_ i: Int, offset: CGFloat, side: CGFloat) -> (CGPoint, CGFloat) {
            let h = track.heading(at: i)
            let nx = CGFloat(cos(h + .pi / 2)), ny = CGFloat(sin(h + .pi / 2))
            return (CGPoint(x: center[i].x + nx * offset * side,
                            y: center[i].y + ny * offset * side), h)
        }

        // 1) Red/white kerb blocks right at the track edge (low, flush).
        var i = 0
        while i < n {
            for side in [CGFloat(1), CGFloat(-1)] {
                let (p, h) = sidePoint(i, offset: CGFloat(track.halfWidth) + 6, side: side)
                let kerb = SCNBox(width: 30, height: 6, length: 40, chamferRadius: 1)
                let m = SCNMaterial()
                m.lightingModel = .physicallyBased
                m.diffuse.contents = (i / 2) % 2 == 0 ? UIColor.systemRed : UIColor.white
                kerb.materials = [m]
                let node = SCNNode(geometry: kerb)
                node.position = sim3(p, y: 3)
                node.eulerAngles = SCNVector3(0, Float(h) + .pi / 2, 0)
                scene.rootNode.addChildNode(node)
            }
            i += 4
        }

        // 2) Tyre-barrier walls set back from the kerb (stacked dark tyres with
        //    occasional colored ones). Real height = clear 3D depth at the edges.
        i = 0
        while i < n {
            for side in [CGFloat(1), CGFloat(-1)] {
                let (p, _) = sidePoint(i, offset: CGFloat(track.halfWidth) + 55, side: side)
                let tyre = SCNTorus(ringRadius: 14, pipeRadius: 7)
                let m = SCNMaterial()
                m.lightingModel = .physicallyBased
                m.diffuse.contents = (i % 10 == 0) ? UIColor.systemYellow : UIColor(white: 0.08, alpha: 1)
                m.roughness.contents = 0.9
                tyre.materials = [m]
                // Stack two tyres for a short wall.
                for lvl in 0..<2 {
                    let node = SCNNode(geometry: tyre)
                    node.position = sim3(p, y: 10 + Float(lvl) * 16)
                    node.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                    scene.rootNode.addChildNode(node)
                }
            }
            i += 5
        }

        // 3) Trees scattered further out — trunk + rounded foliage, varied size.
        i = 0
        while i < n {
            for side in [CGFloat(1), CGFloat(-1)] {
                // Skip some so they're not a solid wall of trees.
                if (i / 7 + (side > 0 ? 0 : 1)) % 2 != 0 { continue }
                let dist = CGFloat.random(in: 180...340)
                let (p, _) = sidePoint(i, offset: CGFloat(track.halfWidth) + dist, side: side)
                scene.rootNode.addChildNode(makeTree(at: p))
            }
            i += 7
        }

        // 4) A couple of grandstands near the start/finish for scale.
        for s in [CGFloat(1), CGFloat(-1)] {
            let (p, h) = sidePoint(2, offset: CGFloat(track.halfWidth) + 140, side: s)
            scene.rootNode.addChildNode(makeGrandstand(at: p, heading: h))
        }
    }

    /// Trunk + layered foliage sphere, with slight random scale/tint.
    private func makeTree(at p: CGPoint) -> SCNNode {
        let root = SCNNode()
        let scale = Float.random(in: 0.8...1.5)

        let trunk = SCNCylinder(radius: 7, height: 70)
        let tm = SCNMaterial()
        tm.lightingModel = .physicallyBased
        tm.diffuse.contents = UIColor(red: 0.33, green: 0.22, blue: 0.12, alpha: 1)
        tm.roughness.contents = 1.0
        trunk.materials = [tm]
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position = SCNVector3(0, 35, 0)
        root.addChildNode(trunkNode)

        let fm = SCNMaterial()
        fm.lightingModel = .physicallyBased
        let g = CGFloat.random(in: 0.45...0.62)
        fm.diffuse.contents = UIColor(red: 0.12, green: g, blue: 0.18, alpha: 1)
        fm.roughness.contents = 1.0
        // Two overlapping foliage blobs for a fuller canopy.
        for (dy, r) in [(Float(80), CGFloat(46)), (Float(110), CGFloat(34))] {
            let foliage = SCNSphere(radius: r)
            foliage.materials = [fm]
            let fnode = SCNNode(geometry: foliage)
            fnode.position = SCNVector3(0, dy, 0)
            root.addChildNode(fnode)
        }
        root.position = sim3(p, y: 0)
        root.scale = SCNVector3(scale, scale, scale)
        return root
    }

    /// A simple tiered grandstand (sloped seating block + roof).
    private func makeGrandstand(at p: CGPoint, heading: CGFloat) -> SCNNode {
        let root = SCNNode()

        let stand = SCNBox(width: 320, height: 90, length: 90, chamferRadius: 4)
        let sm = SCNMaterial()
        sm.lightingModel = .physicallyBased
        sm.diffuse.contents = UIColor(white: 0.72, alpha: 1)
        sm.roughness.contents = 0.8
        stand.materials = [sm]
        let standNode = SCNNode(geometry: stand)
        standNode.position = SCNVector3(0, 45, 0)
        root.addChildNode(standNode)

        // Colored "crowd" strip on the sloped face.
        let crowd = SCNBox(width: 316, height: 60, length: 10, chamferRadius: 2)
        let cm = SCNMaterial()
        cm.lightingModel = .physicallyBased
        cm.diffuse.contents = crowdTexture()
        crowd.materials = [cm]
        let crowdNode = SCNNode(geometry: crowd)
        crowdNode.position = SCNVector3(0, 55, 44)
        crowdNode.eulerAngles = SCNVector3(-0.5, 0, 0)
        root.addChildNode(crowdNode)

        // Roof slab.
        let roof = SCNBox(width: 330, height: 8, length: 120, chamferRadius: 2)
        let rm = SCNMaterial()
        rm.lightingModel = .physicallyBased
        rm.diffuse.contents = UIColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1)
        roof.materials = [rm]
        let roofNode = SCNNode(geometry: roof)
        roofNode.position = SCNVector3(0, 96, 10)
        root.addChildNode(roofNode)

        root.position = sim3(p, y: 0)
        root.eulerAngles = SCNVector3(0, Float(heading) + .pi / 2, 0)
        return root
    }

    /// Random multi-color speckle to suggest a crowd in the stands.
    private func crowdTexture() -> UIImage {
        let s = 128
        let size = CGSize(width: s, height: 32)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0.2, alpha: 1).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<400 {
                let x = CGFloat.random(in: 0..<CGFloat(s))
                let y = CGFloat.random(in: 0..<32)
                c.setFillColor(UIColor(hue: .random(in: 0...1), saturation: 0.6,
                                       brightness: 0.9, alpha: 1).cgColor)
                c.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
    }

    /// Soft dark radial blob (opaque center fading to clear) for a fake contact
    /// shadow under each car.
    private func contactShadowTexture() -> UIImage {
        let s = 128
        let size = CGSize(width: s, height: s)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let colors = [UIColor(white: 0, alpha: 0.55).cgColor,
                          UIColor(white: 0, alpha: 0.35).cgColor,
                          UIColor(white: 0, alpha: 0.0).cgColor]
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray, locations: [0, 0.55, 1])!
            let center = CGPoint(x: CGFloat(s) / 2, y: CGFloat(s) / 2)
            c.drawRadialGradient(grad, startCenter: center, startRadius: 0,
                                 endCenter: center, endRadius: CGFloat(s) / 2, options: [])
        }
    }

    private func buildCars() {
        for car in engine.cars {
            let node = makeCarNode(color: CarUIColor(car.livery.colorHex))
            node.position = sim3(car.position, y: 0)
            node.eulerAngles = SCNVector3(0, Float(car.heading) + Float.pi / 2, 0)
            // Player car stays visible. For a true driver's-eye view the camera
            // is parented INSIDE this car node at the cockpit (see buildCamera),
            // so the nose, wings and front wheels sit naturally in the driver's
            // field of view and track the car with zero drift.
            if car.isPlayer {
                playerCarNode = node
                // Hide the halo on our own car so it doesn't wrap the camera view.
                node.childNode(withName: "halo", recursively: true)?.isHidden = true
            }
            scene.rootNode.addChildNode(node)
            carNodes[car.id] = node
        }
    }

    /// An F1-style open-wheel single-seater, built from primitives. Local axes:
    /// +Z = forward (nose), X = left/right, Y = up. Long, low and narrow with a
    /// pointed nose, front/rear wings, side pods, airbox and exposed wheels.
    private func makeCarNode(color: UIColor) -> SCNNode {
        let root = SCNNode()

        // Soft contact-shadow blob flat on the road so the car reads as grounded
        // (not floating) even where dynamic shadows are hidden under the road.
        let shadow = SCNPlane(width: 150, height: 260)
        let shMat = SCNMaterial()
        shMat.diffuse.contents = contactShadowTexture()
        shMat.lightingModel = .constant
        shMat.isDoubleSided = true
        shMat.writesToDepthBuffer = false     // don't fight the road for depth
        shMat.blendMode = .alpha
        shadow.materials = [shMat]
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)  // lay flat
        shadowNode.position = SCNVector3(0, 1.2, -5)              // just above tarmac
        shadowNode.renderingOrder = -1
        root.addChildNode(shadowNode)

        // Glossy PBR paint so the car catches highlights and reads as 3D.
        let paint = SCNMaterial()
        paint.lightingModel = .physicallyBased
        paint.diffuse.contents = color
        paint.roughness.contents = 0.25
        paint.metalness.contents = 0.5
        paint.clearCoat.contents = 1.0
        paint.clearCoatRoughness.contents = 0.1

        let carbon = SCNMaterial()
        carbon.lightingModel = .physicallyBased
        carbon.diffuse.contents = UIColor(white: 0.08, alpha: 1)
        carbon.roughness.contents = 0.4
        carbon.metalness.contents = 0.3

        let dark = SCNMaterial()
        dark.lightingModel = .physicallyBased
        dark.diffuse.contents = UIColor(white: 0.03, alpha: 1)
        dark.roughness.contents = 0.5

        // --- Main survival cell / chassis: long, low, narrow -----------------
        let tub = SCNBox(width: 34, height: 18, length: 150, chamferRadius: 6)
        tub.materials = [paint]
        let tubNode = SCNNode(geometry: tub)
        tubNode.position = SCNVector3(0, 20, -5)
        root.addChildNode(tubNode)

        // Floor / plank slightly wider than the tub.
        let floor = SCNBox(width: 46, height: 5, length: 170, chamferRadius: 2)
        floor.materials = [carbon]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, 9, -5)
        root.addChildNode(floorNode)

        // --- Pointed nose cone reaching forward -----------------------------
        let nose = SCNCone(topRadius: 2, bottomRadius: 14, height: 70)
        nose.materials = [paint]
        let noseNode = SCNNode(geometry: nose)
        // Cone points +Y by default; rotate so the tip points forward (+Z).
        noseNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        noseNode.position = SCNVector3(0, 18, 95)
        root.addChildNode(noseNode)

        // --- Front wing (wide, low, at the very front) ----------------------
        let fWing = SCNBox(width: 118, height: 4, length: 26, chamferRadius: 1)
        fWing.materials = [carbon]
        let fWingNode = SCNNode(geometry: fWing)
        fWingNode.position = SCNVector3(0, 10, 120)
        root.addChildNode(fWingNode)
        // Front wing endplates.
        for sx in [Float(-59), Float(59)] {
            let ep = SCNBox(width: 4, height: 20, length: 26, chamferRadius: 1)
            ep.materials = [dark]
            let epNode = SCNNode(geometry: ep)
            epNode.position = SCNVector3(sx, 14, 120)
            root.addChildNode(epNode)
        }

        // --- Side pods (bulges either side of the cockpit) ------------------
        for sx in [Float(-30), Float(30)] {
            let pod = SCNBox(width: 24, height: 20, length: 70, chamferRadius: 6)
            pod.materials = [paint]
            let podNode = SCNNode(geometry: pod)
            podNode.position = SCNVector3(sx, 18, -20)
            root.addChildNode(podNode)
        }

        // --- Cockpit opening + headrest + halo ------------------------------
        let cockpit = SCNBox(width: 26, height: 14, length: 40, chamferRadius: 5)
        cockpit.materials = [dark]
        let cockpitNode = SCNNode(geometry: cockpit)
        cockpitNode.position = SCNVector3(0, 30, 10)
        root.addChildNode(cockpitNode)

        let headrest = SCNBox(width: 28, height: 20, length: 18, chamferRadius: 5)
        headrest.materials = [carbon]
        let headrestNode = SCNNode(geometry: headrest)
        headrestNode.position = SCNVector3(0, 36, -18)
        root.addChildNode(headrestNode)

        // Halo hoop (thin torus over the cockpit). Named so we can hide it on the
        // player's car (the camera sits right at it, so it would wrap the view).
        let halo = SCNTorus(ringRadius: 16, pipeRadius: 2.5)
        halo.materials = [dark]
        let haloNode = SCNNode(geometry: halo)
        haloNode.name = "halo"
        haloNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        haloNode.position = SCNVector3(0, 36, 14)
        root.addChildNode(haloNode)

        // --- Airbox + engine cover tapering to the back --------------------
        let airbox = SCNCone(topRadius: 6, bottomRadius: 12, height: 20)
        airbox.materials = [paint]
        let airboxNode = SCNNode(geometry: airbox)
        airboxNode.position = SCNVector3(0, 46, -22)
        root.addChildNode(airboxNode)

        let engineCover = SCNBox(width: 20, height: 24, length: 70, chamferRadius: 8)
        engineCover.materials = [paint]
        let coverNode = SCNNode(geometry: engineCover)
        coverNode.position = SCNVector3(0, 28, -45)
        root.addChildNode(coverNode)

        // --- Rear wing (tall, mounted at the back) --------------------------
        let rWing = SCNBox(width: 80, height: 5, length: 30, chamferRadius: 1)
        rWing.materials = [carbon]
        let rWingNode = SCNNode(geometry: rWing)
        rWingNode.position = SCNVector3(0, 52, -88)
        root.addChildNode(rWingNode)
        // Rear wing endplates.
        for sx in [Float(-40), Float(40)] {
            let ep = SCNBox(width: 4, height: 34, length: 30, chamferRadius: 1)
            ep.materials = [dark]
            let epNode = SCNNode(geometry: ep)
            epNode.position = SCNVector3(sx, 42, -88)
            root.addChildNode(epNode)
        }
        // Rear wing support pylon.
        let pylon = SCNBox(width: 6, height: 30, length: 10, chamferRadius: 1)
        pylon.materials = [carbon]
        let pylonNode = SCNNode(geometry: pylon)
        pylonNode.position = SCNVector3(0, 38, -84)
        root.addChildNode(pylonNode)

        // --- Exposed wheels: big, fat, standing proud of the body ----------
        // Front wheels narrower/forward, rears wider/back — like a real F1 car.
        let wheelSpecs: [(x: Float, z: Float, radius: CGFloat, width: CGFloat)] = [
            (-40, 92, 20, 20), (40, 92, 20, 20),      // front
            (-44, -70, 24, 28), (44, -70, 24, 28)     // rear (bigger)
        ]
        for s in wheelSpecs {
            let tyre = SCNCylinder(radius: s.radius, height: s.width)
            let tyreMat = SCNMaterial()
            tyreMat.diffuse.contents = UIColor(white: 0.06, alpha: 1)
            tyreMat.lightingModel = .lambert
            tyre.materials = [tyreMat]
            let wn = SCNNode(geometry: tyre)
            wn.eulerAngles = SCNVector3(0, 0, Float.pi / 2) // axle across X
            wn.position = SCNVector3(s.x, Float(s.radius), s.z)

            // Light rim disc so the wheels read as wheels.
            let rim = SCNCylinder(radius: s.radius * 0.5, height: s.width + 1)
            let rimMat = SCNMaterial(); rimMat.diffuse.contents = UIColor(white: 0.55, alpha: 1)
            rim.materials = [rimMat]
            let rimNode = SCNNode(geometry: rim)
            rimNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            rimNode.position = SCNVector3(s.x, Float(s.radius), s.z)
            root.addChildNode(rimNode)
            root.addChildNode(wn)
        }

        return root
    }

    private func buildCamera() {
        let cam = SCNCamera()
        cam.zNear = 1
        cam.zFar = 8000
        // Wider FOV = the immersive, slightly fish-eyed sense of speed you get
        // from an in-helmet view.
        cam.fieldOfView = 85
        cameraNode.camera = cam

        if let car = playerCarNode {
            // Parent the camera INSIDE the car at the driver's helmet. Local car
            // axes: +Z forward, X right, Y up. Driver sits in the cockpit, head
            // just behind the halo, eyes above the steering wheel.
            // Sit in the cockpit opening at helmet height, FORWARD of the airbox
            // and headrest so none of our own bodywork blocks the view. From here
            // we look out over the nose and front wheels down a clear racing lane.
            cameraNode.position = SCNVector3(0, 40, 14)
            // Orientation is set every frame in updateCamera() via a world-space
            // look(at:) toward the car's actual travel direction, which avoids
            // any ambiguity about which local axis is "forward."
            car.addChildNode(cameraNode)
        } else {
            scene.rootNode.addChildNode(cameraNode)
        }
    }

    // MARK: Per-frame loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 60.0 : min(1.0 / 20.0, time - lastTime)
        lastTime = time

        // Smooth button steering, same feel as the 2D version.
        let steerTarget: CGFloat = (input.left ? -1 : 0) + (input.right ? 1 : 0)
        let ease = min(1, 12 * CGFloat(dt))
        buttonSteer += (steerTarget - buttonSteer) * ease

        // From the in-car (driver's) viewpoint the world turns opposite to the
        // overhead sim convention, so flip the steer sign: ◀ turns left, ▶ right
        // as the driver sees it.
        engine.update(dt: dt,
                      playerThrottle: input.accel ? 1 : 0,
                      playerBrake: input.brake ? 1 : 0,
                      playerSteer: -buttonSteer)

        // Copy sim poses onto 3D nodes.
        for car in engine.cars {
            guard let node = carNodes[car.id] else { continue }
            node.position = sim3(car.position, y: 0)
            node.eulerAngles = SCNVector3(0, Float(car.heading) + Float.pi / 2, 0)
        }

        updateCamera()
        overlay?.update(engine: engine)

        // Drive the engine note from the player's speed + throttle.
        let speedFrac = Float(engine.player.speed / GameConstants.playerMaxSpeed)
        engineSound.update(speedFraction: speedFrac, throttle: input.accel ? 1 : 0)

        if case .finished = engine.phase, !didFinish {
            didFinish = true
            engineSound.stop()
            let order = engine.finishingOrder.isEmpty ? engine.cars : engine.finishingOrder
            let playerId = engine.player.id
            DispatchQueue.main.async { [weak self] in
                self?.onFinish(order, playerId)
            }
        }
    }

    /// The camera rides inside the player's car (child node), so its position
    /// tracks the car automatically. Each frame we aim it in WORLD space toward
    /// the direction the car is actually travelling — this sidesteps any
    /// ambiguity about which local axis is "forward" and guarantees we look down
    /// the road, not backward.
    private func updateCamera() {
        guard let car = playerCarNode else { return }

        // Use the CAR NODE's own forward direction (its local +Z, where the nose
        // is modelled) transformed into world space. This guarantees the camera
        // looks exactly the way the car's nose points — no reliance on a heading
        // sign convention that could flip the view.
        let t = car.worldTransform
        // Local +Z axis in world space = (m31, m32, m33) column of the transform.
        var fwd = SCNVector3(t.m31, t.m32, t.m33)
        let len = max(0.0001, sqrt(fwd.x * fwd.x + fwd.y * fwd.y + fwd.z * fwd.z))
        fwd = SCNVector3(fwd.x / len, fwd.y / len, fwd.z / len)

        // World position of the helmet (camera) right now.
        let eye = cameraNode.worldPosition

        // Aim down the road with a gentle downward tilt so the nose and front
        // wheels sit low in the frame and the racing lane fills the view ahead.
        let lookAt = SCNVector3(eye.x + fwd.x * 600,
                                eye.y - 35,
                                eye.z + fwd.z * 600)
        cameraNode.look(at: lookAt, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }

    // MARK: Coordinate mapping

    /// Map sim (x, y) ground point to SceneKit world (x, y_up, -y).
    private func sim3(_ p: CGPoint, y: Float) -> SCNVector3 {
        SCNVector3(Float(p.x), y, -Float(p.y))
    }
}

// MARK: - Shared input flags set by the overlay buttons

final class RaceInput {
    var accel = false
    var brake = false
    var left = false
    var right = false
}

// MARK: - Color helper (hex -> UIColor), matching CarNode.color

func CarUIColor(_ hex: UInt32) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

private extension CGSize {
    var isEmpty: Bool { width <= 0 || height <= 0 }
}
