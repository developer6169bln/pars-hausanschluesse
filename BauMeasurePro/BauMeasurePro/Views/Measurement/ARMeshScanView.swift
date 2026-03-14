import SwiftUI
import ARKit
import SceneKit
import CoreLocation

/// 3D-Mesh-Scan per LiDAR. Erfasst die Umgebung als Mesh und speichert als .scn. Beim Speichern wird der aktuelle GPS-Standort mitgespeichert.
struct ARMeshScanView: View {
    let scanId: UUID
    /// Callback: (Dateipfad, Latitude?, Longitude?)
    var onSave: (String, Double?, Double?) -> Void
    var onCancel: () -> Void

    @State private var meshAnchorsCount = 0
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var supportsMesh = true
    @State private var requestExport = false
    @StateObject private var locationService = LocationService()

    private let storage = StorageService()

    var body: some View {
        ZStack {
            ARMeshScanSceneView(
                meshCount: $meshAnchorsCount,
                supportsMesh: $supportsMesh,
                requestExport: $requestExport,
                scanId: scanId,
                storage: storage,
                getLocation: {
                    guard let loc = locationService.location else { return nil }
                    return (loc.coordinate.latitude, loc.coordinate.longitude)
                },
                onExportDone: { path, lat, lon in
                    isSaving = false
                    requestExport = false
                    if let p = path {
                        onSave(p, lat, lon)
                    } else {
                        errorMessage = "Export fehlgeschlagen."
                        showError = true
                    }
                }
            )
            .ignoresSafeArea()

            VStack {
                if !supportsMesh {
                    Text("3D-Scan benötigt ein Gerät mit LiDAR (z. B. iPhone Pro).")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.black.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                } else {
                    Text("Bewege das Gerät langsam, um die Umgebung zu erfassen.")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 8)
                    Text("\(meshAnchorsCount) Mesh-Bereiche erfasst")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                HStack(spacing: 20) {
                    Button("Abbrechen") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button("Speichern") {
                        isSaving = true
                        requestExport = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!supportsMesh || meshAnchorsCount == 0 || isSaving)
                }
                .padding(.bottom, 40)
            }
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK", role: .cancel) { showError = false }
        } message: {
            Text(errorMessage ?? "Unbekannter Fehler")
        }
    }
}

// MARK: - UIViewRepresentable für AR-Mesh-Session

private struct ARMeshScanSceneView: UIViewRepresentable {
    @Binding var meshCount: Int
    @Binding var supportsMesh: Bool
    @Binding var requestExport: Bool
    var scanId: UUID
    var storage: StorageService
    var getLocation: () -> (Double, Double)?
    var onExportDone: (String?, Double?, Double?) -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.delegate = context.coordinator
        sceneView.session.delegate = context.coordinator
        sceneView.autoenablesDefaultLighting = true
        sceneView.antialiasingMode = .multisampling4X
        context.coordinator.sceneView = sceneView
        context.coordinator.meshCountBinding = $meshCount
        context.coordinator.supportsMeshBinding = $supportsMesh
        context.coordinator.requestExportBinding = $requestExport
        context.coordinator.storage = storage
        context.coordinator.scanId = scanId
        context.coordinator.getLocation = getLocation
        context.coordinator.onExportDone = onExportDone

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            sceneView.session.run(config)
        } else {
            DispatchQueue.main.async { supportsMesh = false }
            config.sceneReconstruction = []
            sceneView.session.run(config)
        }
        return sceneView
    }

    func updateUIView(_ sceneView: ARSCNView, context: Context) {
        if requestExport {
            context.coordinator.performExport()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        weak var sceneView: ARSCNView?
        var meshCountBinding: Binding<Int>?
        var supportsMeshBinding: Binding<Bool>?
        var requestExportBinding: Binding<Bool>?
        var knownMeshNodes: [UUID: SCNNode] = [:]
        var storage: StorageService?
        var scanId: UUID?
        var getLocation: (() -> (Double, Double)?)?
        var onExportDone: ((String?, Double?, Double?) -> Void)?

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let view = sceneView else { return }
            for anchor in anchors {
                guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
                let geo = SCNGeometry.fromAnchor(meshAnchor: meshAnchor)
                let node = SCNNode(geometry: geo)
                node.simdTransform = meshAnchor.transform
                node.name = anchor.identifier.uuidString
                knownMeshNodes[anchor.identifier] = node
                view.scene.rootNode.addChildNode(node)
            }
            updateMeshCount(session: session)
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            guard sceneView != nil else { return }
            for anchor in anchors {
                guard let meshAnchor = anchor as? ARMeshAnchor,
                      let node = knownMeshNodes[anchor.identifier] else { continue }
                node.geometry = SCNGeometry.fromAnchor(meshAnchor: meshAnchor)
                node.simdTransform = meshAnchor.transform
            }
            updateMeshCount(session: session)
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            for anchor in anchors {
                if let node = knownMeshNodes[anchor.identifier] {
                    node.removeFromParentNode()
                    knownMeshNodes.removeValue(forKey: anchor.identifier)
                }
            }
            updateMeshCount(session: session)
        }

        private func updateMeshCount(session: ARSession) {
            let count = session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor }.count ?? 0
            DispatchQueue.main.async {
                self.meshCountBinding?.wrappedValue = count
            }
        }

        func performExport() {
            requestExportBinding?.wrappedValue = false
            guard let session = sceneView?.session,
                  let storage = storage,
                  let scanId = scanId,
                  let done = onExportDone else {
                DispatchQueue.main.async { self.onExportDone?(nil, nil, nil) }
                return
            }
            guard let frame = session.currentFrame else {
                DispatchQueue.main.async { done(nil, nil, nil) }
                return
            }
            let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
            let scene = SCNScene()
            for meshAnchor in meshAnchors {
                guard let geo = SCNGeometry.copyFromAnchor(meshAnchor: meshAnchor) else { continue }
                let node = SCNNode(geometry: geo)
                node.simdTransform = meshAnchor.transform
                scene.rootNode.addChildNode(node)
            }
            let path = storage.save3DScene(scene, scanId: scanId)
            let loc = getLocation?()
            DispatchQueue.main.async {
                done(path, loc?.0, loc?.1)
            }
        }
    }
}
