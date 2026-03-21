import SwiftUI
import ARKit
import SceneKit
import CoreLocation

/// Scan-Verfahren: Punktwolke (RGB aus Tiefe) oder Mesh (Oberflächen-Rekonstruktion).
enum ScanProcedure: String, CaseIterable {
    case pointCloud = "Punktwolke (RGB)"
    case mesh = "Mesh"
}

/// 3D-Scan per LiDAR: Punktwolke (ScanAce-ähnlich, RGB) oder Mesh. Speichert als .ply (Punktwolke) oder .scn (Mesh). GPS wird mitgespeichert.
struct ARMeshScanView: View {
    let scanId: UUID
    /// Callback: (Dateipfad, Latitude?, Longitude?, SceneOriginX?, Y?, Z?) – Origin = Kameraposition beim Speichern für Ausrichtung auf Luftbild.
    var onSave: (String, Double?, Double?, Double?, Double?, Double?) -> Void
    var onCancel: () -> Void

    @State private var scanProcedure: ScanProcedure = .mesh
    @State private var meshAnchorsCount = 0
    @State private var pointCloudCount = 0
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var supportsMesh = true
    @State private var requestExport = false
    @StateObject private var locationService = LocationService()
    @State private var trackingStateMessage: String = "normal"

    private let storage = StorageService()

    private var hasAnyData: Bool {
        switch scanProcedure {
        case .pointCloud: return pointCloudCount > 0
        case .mesh: return meshAnchorsCount > 0
        }
    }

    var body: some View {
        ZStack {
            ARMeshScanSceneView(
                scanProcedure: scanProcedure,
                meshCount: $meshAnchorsCount,
                pointCloudCount: $pointCloudCount,
                supportsMesh: $supportsMesh,
                requestExport: $requestExport,
                trackingState: $trackingStateMessage,
                scanId: scanId,
                storage: storage,
                getLocation: {
                    guard let loc = locationService.location else { return nil }
                    return (loc.coordinate.latitude, loc.coordinate.longitude)
                },
                onExportDone: { path, lat, lon, ox, oy, oz in
                    isSaving = false
                    requestExport = false
                    if let p = path {
                        onSave(p, lat, lon, ox, oy, oz)
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
                    Text("Scan-Verfahren: Mesh (Standard)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(spacing: 6) {
                        Text("Bewege das Gerät langsam, um die Umgebung zu erfassen.")
                            .font(.caption)
                            .foregroundStyle(.white)
                        Text("Tipp für mehr Details: sehr langsam bewegen, gute Beleuchtung, jeden Bereich mehrfach von mehreren Seiten erfassen.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Vermessungs-Tipps:")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                            Text("• S-Pattern: Fläche in Zickzack abfahren (←←← / →→→ / ←←←) – LiDAR erhält mehr Winkel, bessere Genauigkeit.")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.9))
                                .multilineTextAlignment(.leading)
                            Text("• Baugrube: 3 Ebenen scannen – 1) Rand ablaufen, 2) halbe Höhe der Wände, 3) Boden – ergibt geschlossenes Mesh.")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.9))
                                .multilineTextAlignment(.leading)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(8)
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 8)
                    if scanProcedure == .mesh || meshAnchorsCount > 0 {
                        Text("\(meshAnchorsCount) Mesh-Bereiche erfasst")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    if trackingStateMessage == "limited" || trackingStateMessage == "notAvailable" {
                        Text(trackingStateMessage == "limited"
                             ? "Tracking eingeschränkt – langsam bewegen, mehr Struktur/Details erfassen"
                             : "Tracking verloren – Gerät bewegen bis AR wieder stabil ist")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.orange.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 6)
                    }
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
                    .disabled(!supportsMesh || !hasAnyData || isSaving)
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
    var scanProcedure: ScanProcedure
    @Binding var meshCount: Int
    @Binding var pointCloudCount: Int
    @Binding var supportsMesh: Bool
    @Binding var requestExport: Bool
    @Binding var trackingState: String
    var scanId: UUID
    var storage: StorageService
    var getLocation: () -> (Double, Double)?
    var onExportDone: (String?, Double?, Double?, Double?, Double?, Double?) -> Void

    private func makeConfig(usePointCloud: Bool) -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        } else {
            config.sceneReconstruction = []
        }
        if usePointCloud && ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth]) {
            config.frameSemantics.insert(.sceneDepth)
            if ARWorldTrackingConfiguration.supportsFrameSemantics([.smoothedSceneDepth]) {
                config.frameSemantics.insert(.smoothedSceneDepth)
            }
        }
        return config
    }

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.delegate = context.coordinator
        sceneView.session.delegate = context.coordinator
        sceneView.autoenablesDefaultLighting = true
        sceneView.antialiasingMode = .multisampling4X
        context.coordinator.sceneView = sceneView
        context.coordinator.meshCountBinding = $meshCount
        context.coordinator.pointCloudCountBinding = $pointCloudCount
        context.coordinator.supportsMeshBinding = $supportsMesh
        context.coordinator.requestExportBinding = $requestExport
        context.coordinator.trackingStateBinding = $trackingState
        context.coordinator.storage = storage
        context.coordinator.scanId = scanId
        context.coordinator.getLocation = getLocation
        context.coordinator.onExportDone = onExportDone
        context.coordinator.pointCloudService = PointCloudService()
        context.coordinator.scanProcedure = scanProcedure

        let pointCloudNode = SCNNode()
        pointCloudNode.name = "PointCloudNode"
        sceneView.scene.rootNode.addChildNode(pointCloudNode)
        context.coordinator.pointCloudNode = pointCloudNode

        if !ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) && !ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            DispatchQueue.main.async { supportsMesh = false }
        }
        let usePointCloud = (scanProcedure == .pointCloud)
        sceneView.session.run(makeConfig(usePointCloud: usePointCloud))
        context.coordinator.lastAppliedProcedure = scanProcedure
        return sceneView
    }

    func updateUIView(_ sceneView: ARSCNView, context: Context) {
        context.coordinator.scanProcedure = scanProcedure
        context.coordinator.trackingStateBinding = $trackingState
        if requestExport {
            context.coordinator.performExport()
        }
        let lastProcedure = context.coordinator.lastAppliedProcedure
        if lastProcedure != scanProcedure {
            context.coordinator.lastAppliedProcedure = scanProcedure
            let usePointCloud = (scanProcedure == .pointCloud)
            sceneView.session.run(makeConfig(usePointCloud: usePointCloud), options: [.resetSceneReconstruction])
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        weak var sceneView: ARSCNView?
        var meshCountBinding: Binding<Int>?
        var pointCloudCountBinding: Binding<Int>?
        var supportsMeshBinding: Binding<Bool>?
        var requestExportBinding: Binding<Bool>?
        var trackingStateBinding: Binding<String>?
        var knownMeshNodes: [UUID: SCNNode] = [:]
        var pointCloudNode: SCNNode?
        var pointCloudService: PointCloudService?
        var scanProcedure: ScanProcedure = .pointCloud
        var lastAppliedProcedure: ScanProcedure?
        private var frameCount = 0
        var storage: StorageService?
        var scanId: UUID?
        var getLocation: (() -> (Double, Double)?)?
        var onExportDone: ((String?, Double?, Double?, Double?, Double?, Double?) -> Void)?
        private var lastReportedTrackingState: String = ""

        private var lastGeometryUpdateTime: CFTimeInterval = 0

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Tracking-Qualitätsindikator: nur bei Änderung melden.
            let state = frame.camera.trackingState
            let stateStr: String
            switch state {
            case .normal: stateStr = "normal"
            case .limited: stateStr = "limited"
            case .notAvailable: stateStr = "notAvailable"
            @unknown default: stateStr = "unknown"
            }
            if stateStr != lastReportedTrackingState {
                lastReportedTrackingState = stateStr
                DispatchQueue.main.async { [weak self] in
                    self?.trackingStateBinding?.wrappedValue = stateStr
                }
            }

            // Punktwolke-Workflow unverändert
            guard scanProcedure == .pointCloud, let service = pointCloudService else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak service] in
                service?.addPoints(from: frame)
            }
            frameCount += 1
            let count = service.pointCount
            if frameCount % 5 == 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.pointCloudCountBinding?.wrappedValue = count
                }
            }
            let now = CACurrentMediaTime()
            guard count > 0, (now - lastGeometryUpdateTime) > 1.2 else { return }
            lastGeometryUpdateTime = now
            let node = pointCloudNode
            DispatchQueue.global(qos: .userInitiated).async { [weak service, weak node] in
                guard let service = service, let node = node, let geometry = service.makeSceneKitGeometry(maxPoints: 30_000) else { return }
                DispatchQueue.main.async {
                    node.geometry = geometry
                    node.position = SCNVector3(0, 0, 0)
                }
            }
        }

        private func refreshPointCloudUI() {
            // Nur Zähler aktualisieren; Geometrie wird in session(didUpdate:) asynchron erstellt
            guard let service = pointCloudService else { return }
            pointCloudCountBinding?.wrappedValue = service.pointCount
        }

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
            guard let view = sceneView else { return }
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
            guard let sceneView = sceneView,
                  let storage = storage,
                  let scanId = scanId,
                  let done = onExportDone else {
                DispatchQueue.main.async { self.onExportDone?(nil, nil, nil, nil, nil, nil) }
                return
            }
            let session = sceneView.session
            guard let frame = session.currentFrame else {
                DispatchQueue.main.async { done(nil, nil, nil, nil, nil, nil) }
                return
            }
            let cam = frame.camera.transform
            let originX = Double(cam.columns.3.x)
            let originY = Double(cam.columns.3.y)
            let originZ = Double(cam.columns.3.z)
            let loc = getLocation?()

            if scanProcedure == .pointCloud, let service = pointCloudService, service.pointCount > 0 {
                let scanIdCopy = scanId
                let storageCopy = storage
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let plyData = service.exportPLY() else {
                        DispatchQueue.main.async { done(nil, loc?.0, loc?.1, originX, originY, originZ) }
                        return
                    }
                    let path = storageCopy.savePointCloudPLY(plyData, scanId: scanIdCopy)
                    DispatchQueue.main.async {
                        done(path, loc?.0, loc?.1, originX, originY, originZ)
                    }
                }
                return
            }

            // Mesh-Export kann sehr teuer sein (viele Anchors) → in den Background verschieben,
            // damit die App nach dem Scan nicht durch Watchdog/Freeze abstürzt.
            let orientation = sceneView.window?.windowScene?.interfaceOrientation ?? .portrait
            let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
            let storageCopy = storage
            let scanIdCopy = scanId

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                autoreleasepool {
                    let scene = SCNScene()
                    var nodes: [SCNNode] = []
                    nodes.reserveCapacity(meshAnchors.count)

                    for meshAnchor in meshAnchors {
                        let geo: SCNGeometry? = SCNGeometry.fromAnchor(meshAnchor: meshAnchor, frame: frame, orientation: orientation)
                            ?? SCNGeometry.copyFromAnchor(meshAnchor: meshAnchor)
                        guard let geo = geo?.optimized(triangleEdgeLimitMeters: 0.02) else { continue } // 2 cm
                        for mat in geo.materials {
                            mat.transparency = 1.0
                            mat.transparencyMode = .default
                        }
                        let node = SCNNode(geometry: geo)
                        node.simdTransform = meshAnchor.transform
                        scene.rootNode.addChildNode(node)
                        nodes.append(node)
                    }

                    let path = storageCopy.save3DScene(scene, scanId: scanIdCopy)
                    DispatchQueue.main.async {
                        done(path, loc?.0, loc?.1, originX, originY, originZ)
                    }
                }
            }
        }
    }
}

