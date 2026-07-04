import AppKit
import SceneKit
import SwiftUI

/// A real 3D globe (SceneKit) that very slowly rotates and marks the station's
/// approximate broadcast location with a glowing pin. The pin is a child of the
/// globe so it turns with the Earth; the whole thing is a wireframe sphere over
/// a dark inner sphere for a clean "operator console" look. Updates live when
/// the station's coordinate changes.
struct RelayGlobe: NSViewRepresentable {
    var lat: Double?
    var lon: Double?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.isPlaying = true // keep the rotation action animating
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.updateMarker(lat: lat, lon: lon)
    }

    final class Coordinator {
        let scene = SCNScene()
        private let globeNode = SCNNode()
        private var markerNode: SCNNode?
        private var lastLat: Double?
        private var lastLon: Double?
        private static let R: CGFloat = 1.5

        init() {
            // Camera
            let camera = SCNCamera()
            camera.fieldOfView = 32
            let camNode = SCNNode()
            camNode.camera = camera
            camNode.position = SCNVector3(0, 0, 6)
            scene.rootNode.addChildNode(camNode)

            // Lights (soft, so the wireframe reads without harsh shading)
            let ambient = SCNLight(); ambient.type = .ambient; ambient.intensity = 500
            let ambientNode = SCNNode(); ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)

            // Wireframe sphere (the graticule/globe lines)
            let sphere = SCNSphere(radius: Self.R)
            sphere.segmentCount = 44
            let wire = SCNMaterial()
            wire.fillMode = .lines
            wire.diffuse.contents = NSColor(calibratedRed: 0.35, green: 0.85, blue: 1.0, alpha: 0.55)
            wire.emission.contents = NSColor(calibratedRed: 0.35, green: 0.85, blue: 1.0, alpha: 0.40)
            wire.lightingModel = .constant
            wire.isDoubleSided = true
            sphere.materials = [wire]
            globeNode.addChildNode(SCNNode(geometry: sphere))

            // Dark inner sphere so the far-side lines don't show through.
            let inner = SCNSphere(radius: Self.R - 0.02)
            let innerMat = SCNMaterial()
            innerMat.diffuse.contents = NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.10, alpha: 0.92)
            innerMat.lightingModel = .constant
            inner.materials = [innerMat]
            globeNode.addChildNode(SCNNode(geometry: inner))

            // Slight axial tilt for a more dimensional read.
            globeNode.eulerAngles = SCNVector3(CGFloat(18) * .pi / 180, 0, 0)
            scene.rootNode.addChildNode(globeNode)

            // VERY slow spin — one full turn every 90 seconds.
            globeNode.runAction(
                .repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 90))
            )
        }

        func updateMarker(lat: Double?, lon: Double?) {
            if lat == lastLat && lon == lastLon { return }
            lastLat = lat; lastLon = lon
            markerNode?.removeFromParentNode()
            markerNode = nil
            guard let lat, let lon else { return }

            let phi = CGFloat(lat) * .pi / 180
            let lam = CGFloat(lon) * .pi / 180
            let x = Self.R * cos(phi) * cos(lam)
            let z = Self.R * cos(phi) * sin(lam)
            let y = Self.R * sin(phi)

            let pin = SCNSphere(radius: 0.07)
            let mat = SCNMaterial()
            mat.diffuse.contents = NSColor(calibratedRed: 0.35, green: 0.95, blue: 0.65, alpha: 1)
            mat.emission.contents = NSColor(calibratedRed: 0.35, green: 0.95, blue: 0.65, alpha: 1)
            mat.lightingModel = .constant
            pin.materials = [mat]
            let node = SCNNode(geometry: pin)
            node.position = SCNVector3(x, y, z)

            // Soft glow halo around the pin.
            let halo = SCNSphere(radius: 0.14)
            let haloMat = SCNMaterial()
            haloMat.diffuse.contents = NSColor(calibratedRed: 0.35, green: 0.95, blue: 0.65, alpha: 0.18)
            haloMat.lightingModel = .constant
            haloMat.writesToDepthBuffer = false
            halo.materials = [haloMat]
            node.addChildNode(SCNNode(geometry: halo))

            globeNode.addChildNode(node) // child of the globe → turns with it
            markerNode = node
        }
    }
}
