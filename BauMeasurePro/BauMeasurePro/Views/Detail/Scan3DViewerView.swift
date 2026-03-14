import SwiftUI
import SceneKit

struct Scan3DViewerView: View {
    let scan: ThreeDScan

    var body: some View {
        VStack {
            SceneView(
                scene: loadScene(),
                pointOfView: nil,
                options: [.allowsCameraControl, .autoenablesDefaultLighting]
            )
            .ignoresSafeArea()
        }
        .navigationTitle(scan.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadScene() -> SCNScene {
        // Platzhalter: Solange noch keine echte 3D-Datei vorhanden ist, zeigen wir einen Würfel.
        let scene = SCNScene()
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(node)
        return scene
    }
}

