import SwiftUI
import ARKit
import SceneKit
import CoreLocation
import UIKit
import ImageIO

/// Scan-Verfahren: Punktwolke (RGB aus Tiefe) oder Mesh (Oberflächen-Rekonstruktion).
enum ScanProcedure: String, CaseIterable {
    case pointCloud = "Punktwolke (RGB)"
    case mesh = "Mesh"
}

enum MeshProcessingPreset: String, CaseIterable {
    case standard = "Standard"
    case dense = "Dicht"
    case custom = "Benutzerdefiniert"
    case cloud = "Cloud"
}

enum ScanCaptureProfile: String, CaseIterable {
    case pitDetail = "Baugrube Detail"
    case pipelineLongRange = "Leitung Langstrecke"
}

struct MeshProcessingOptions {
    var preset: MeshProcessingPreset = .standard
    var captureProfile: ScanCaptureProfile = .pitDetail
    var lightweightLivePreview: Bool = false
    var autoPreviewThrottling: Bool = true
    var depthRangeMeters: Double = 5.0
    var voxelSizeMillimeters: Double = 4.0
    var simplificationPercent: Double = 45.0
    var autoCrop: Bool = true
    var loopClosure: Bool = true
    var fillHoles: Bool = true
}

/// 3D-Scan per LiDAR: Punktwolke (ScanAce-ähnlich, RGB) oder Mesh. Speichert als .ply (Punktwolke) oder .scn (Mesh). GPS wird mitgespeichert.
struct ARMeshScanView: View {
    let scanId: UUID
    /// Callback: (Dateipfad, Latitude?, Longitude?, SceneOriginX?, Y?, Z?) – Origin = Kameraposition beim Speichern für Ausrichtung auf Luftbild.
    var onSave: (String, Double?, Double?, Double?, Double?, Double?, [ScanKeyframe]) -> Void
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
    @State private var meshPreviewPaused = false
    @State private var meshSegmentationActive = false
    @State private var savedSegmentCount = 0
    @State private var processingOptions = MeshProcessingOptions()
    @State private var detailLevel: Double = 0.75
    @State private var liveQualityScore: Int = 0
    @State private var liveQualityHint: String = "Initialisiere Scan..."
    @AppStorage("pointCloudPointSize") private var pointCloudPointSize: Double = 1.0
    @AppStorage("pointCloudDensity") private var pointCloudDensity: Double = 0.85
    @AppStorage("pointCloudCableHighlightEnabled") private var cableHighlightEnabled: Bool = true
    @AppStorage("pointCloudCableHighlightStrength") private var cableHighlightStrength: Double = 0.75
    @AppStorage("pointCloudCableDetectOrange") private var cableDetectOrange: Bool = false
    @AppStorage("pointCloudCableAutoTracePipe") private var cableAutoTracePipe: Bool = true
    @AppStorage("pointCloudCableAutoPipeRadiusMeters") private var cableAutoPipeRadiusMeters: Double = 0.028
    @AppStorage("pointCloudCablePathEnabled") private var cablePathEnabled: Bool = false
    @State private var requestCablePathUndo: Bool = false
    @State private var requestCablePathClear: Bool = false

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
                meshPreviewPaused: $meshPreviewPaused,
                meshSegmentationActive: $meshSegmentationActive,
                savedSegmentCount: $savedSegmentCount,
                processingOptions: processingOptions,
                requestExport: $requestExport,
                trackingState: $trackingStateMessage,
                qualityScore: $liveQualityScore,
                qualityHint: $liveQualityHint,
                pointCloudPointSize: pointCloudPointSize,
                pointCloudDensity: pointCloudDensity,
                cableHighlightEnabled: cableHighlightEnabled,
                cableHighlightStrength: cableHighlightStrength,
                cableDetectOrange: cableDetectOrange,
                cableAutoTracePipe: cableAutoTracePipe,
                cableAutoPipeRadiusMeters: cableAutoPipeRadiusMeters,
                cablePathEnabled: cablePathEnabled,
                requestCablePathUndo: $requestCablePathUndo,
                requestCablePathClear: $requestCablePathClear,
                scanId: scanId,
                storage: storage,
                getLocation: {
                    guard let loc = locationService.location else { return nil }
                    return (loc.coordinate.latitude, loc.coordinate.longitude)
                },
                onExportDone: { path, lat, lon, ox, oy, oz, keyframes in
                    isSaving = false
                    requestExport = false
                    if let p = path {
                        onSave(p, lat, lon, ox, oy, oz, keyframes)
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
                    if scanProcedure == .mesh || meshAnchorsCount > 0 {
                        Text("\(meshAnchorsCount) Mesh-Bereiche erfasst")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    qualityOverlay
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
                detailControlPanel
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            applyDetailLevel(detailLevel)
        }
        .onChange(of: detailLevel) { _, newValue in
            applyDetailLevel(newValue)
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK", role: .cancel) { showError = false }
        } message: {
            Text(errorMessage ?? "Unbekannter Fehler")
        }
    }

    private var qualityOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Scan-Qualität")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                Text("\(liveQualityScore)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule()
                        .fill(liveQualityScore >= 70 ? .green : (liveQualityScore >= 45 ? .orange : .red))
                        .frame(width: proxy.size.width * CGFloat(max(0, min(100, liveQualityScore))) / 100.0)
                }
            }
            .frame(height: 8)
            Text(liveQualityHint)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.95))
        }
        .padding(8)
        .background(.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.top, 6)
        .padding(.horizontal, 6)
    }

    private var detailControlPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detailgrad")
                .font(.caption.bold())
                .foregroundStyle(.white)
            HStack {
                Text("Grob")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                Slider(value: $detailLevel, in: 0...1, step: 0.01)
                Text("Fein")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .font(.caption2)
            .foregroundStyle(.white)
            HStack {
                Text("Punktgröße")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                Slider(value: $pointCloudPointSize, in: 0.5...4.0, step: 0.1)
                Text(String(format: "%.1f", pointCloudPointSize))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            }
            if scanProcedure == .pointCloud {
                HStack {
                    Text("Punktdichte")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                    Slider(value: $pointCloudDensity, in: 0.2...1.0, step: 0.05)
                    Text("\(Int(pointCloudDensity * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }
                Toggle("Leitungen hervorheben", isOn: $cableHighlightEnabled)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                    .tint(.cyan)
                if cableHighlightEnabled {
                    HStack {
                        Text("Leitungs-Fokus")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                        Slider(value: $cableHighlightStrength, in: 0.2...1.0, step: 0.05)
                        Text("\(Int(cableHighlightStrength * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Toggle("Orange mit erkennen", isOn: $cableDetectOrange)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))
                        .tint(.orange)
                    Toggle("Auto-Rohr (Magenta)", isOn: $cableAutoTracePipe)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))
                        .tint(.pink)
                    if cableAutoTracePipe {
                        HStack {
                            Text("Rohr-Ø")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.8))
                            Slider(value: $cableAutoPipeRadiusMeters, in: 0.010...0.060, step: 0.002)
                            Text(String(format: "%.0f mm", cableAutoPipeRadiusMeters * 2 * 1000))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
                Toggle("Leitungsweg zeichnen", isOn: $cablePathEnabled)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                    .tint(.pink)
                if cablePathEnabled {
                    HStack(spacing: 10) {
                        Button("Undo") { requestCablePathUndo = true }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        Button("Löschen") { requestCablePathClear = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                    .font(.caption2)
                }
            }
            Text(detailModeDescription)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.95))
        }
        .font(.caption2)
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 10)
    }

    private var detailModeDescription: String {
        if detailLevel >= 0.90 {
            return "Superfein: Punktwolke Max-Detail für kritische Bereiche (langsam scannen)."
        } else if detailLevel >= 0.72 {
            return "Fein: Punktwolke aktiv (maximale Details, höherer Speicherbedarf)."
        } else if detailLevel >= 0.38 {
            return "Mittel: Mesh mit hoher Detailtreue für Baugruben."
        } else {
            return "Grob: Mesh optimiert für lange Leitungsstrecken (stabil und leicht)."
        }
    }

    private func applyDetailLevel(_ value: Double) {
        if value >= 0.90 {
            // Superfein => Punktwolke maximal
            scanProcedure = .pointCloud
            processingOptions.captureProfile = .pitDetail
            processingOptions.preset = .dense
            processingOptions.depthRangeMeters = 4.5
            processingOptions.voxelSizeMillimeters = 2
            processingOptions.simplificationPercent = 0
            processingOptions.autoCrop = false
            processingOptions.loopClosure = true
            processingOptions.fillHoles = true
            processingOptions.lightweightLivePreview = false
            processingOptions.autoPreviewThrottling = true
        } else if value >= 0.72 {
            // Fein => Wolke
            scanProcedure = .pointCloud
            processingOptions.captureProfile = .pitDetail
            processingOptions.preset = .dense
            processingOptions.depthRangeMeters = 6
            processingOptions.voxelSizeMillimeters = 2
            processingOptions.simplificationPercent = 10
            processingOptions.autoCrop = false
            processingOptions.loopClosure = true
            processingOptions.fillHoles = true
            processingOptions.lightweightLivePreview = false
            processingOptions.autoPreviewThrottling = true
        } else if value >= 0.38 {
            // Mittel => Mesh detailreich
            scanProcedure = .mesh
            processingOptions.captureProfile = .pitDetail
            processingOptions.preset = .dense
            processingOptions.depthRangeMeters = 6
            processingOptions.voxelSizeMillimeters = 3
            processingOptions.simplificationPercent = 25
            processingOptions.autoCrop = true
            processingOptions.loopClosure = true
            processingOptions.fillHoles = true
            processingOptions.lightweightLivePreview = true
            processingOptions.autoPreviewThrottling = true
        } else {
            // Grob => Mesh langstrecke
            scanProcedure = .mesh
            processingOptions.captureProfile = .pipelineLongRange
            processingOptions.preset = .cloud
            processingOptions.depthRangeMeters = 10
            processingOptions.voxelSizeMillimeters = 7
            processingOptions.simplificationPercent = 60
            processingOptions.autoCrop = true
            processingOptions.loopClosure = true
            processingOptions.fillHoles = false
            processingOptions.lightweightLivePreview = true
            processingOptions.autoPreviewThrottling = true
        }
    }
}

// MARK: - UIViewRepresentable für AR-Mesh-Session

private struct ARMeshScanSceneView: UIViewRepresentable {
    var scanProcedure: ScanProcedure
    @Binding var meshCount: Int
    @Binding var pointCloudCount: Int
    @Binding var supportsMesh: Bool
    @Binding var meshPreviewPaused: Bool
    @Binding var meshSegmentationActive: Bool
    @Binding var savedSegmentCount: Int
    var processingOptions: MeshProcessingOptions
    @Binding var requestExport: Bool
    @Binding var trackingState: String
    @Binding var qualityScore: Int
    @Binding var qualityHint: String
    var pointCloudPointSize: Double
    var pointCloudDensity: Double
    var cableHighlightEnabled: Bool
    var cableHighlightStrength: Double
    var cableDetectOrange: Bool
    var cableAutoTracePipe: Bool
    var cableAutoPipeRadiusMeters: Double
    var cablePathEnabled: Bool
    @Binding var requestCablePathUndo: Bool
    @Binding var requestCablePathClear: Bool
    var scanId: UUID
    var storage: StorageService
    var getLocation: () -> (Double, Double)?
    var onExportDone: (String?, Double?, Double?, Double?, Double?, Double?, [ScanKeyframe]) -> Void

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
        context.coordinator.meshPreviewPausedBinding = $meshPreviewPaused
        context.coordinator.meshSegmentationActiveBinding = $meshSegmentationActive
        context.coordinator.savedSegmentCountBinding = $savedSegmentCount
        context.coordinator.requestExportBinding = $requestExport
        context.coordinator.trackingStateBinding = $trackingState
        context.coordinator.savedSegmentCountBinding = $savedSegmentCount
        context.coordinator.qualityScoreBinding = $qualityScore
        context.coordinator.qualityHintBinding = $qualityHint
        context.coordinator.storage = storage
        context.coordinator.scanId = scanId
        context.coordinator.getLocation = getLocation
        context.coordinator.onExportDone = onExportDone
        context.coordinator.pointCloudService = PointCloudService()
        context.coordinator.scanProcedure = scanProcedure
        context.coordinator.processingOptions = processingOptions
        context.coordinator.pointCloudPointSize = pointCloudPointSize
        context.coordinator.pointCloudDensity = pointCloudDensity
        context.coordinator.cableHighlightEnabled = cableHighlightEnabled
        context.coordinator.cableHighlightStrength = cableHighlightStrength
        context.coordinator.cableDetectOrange = cableDetectOrange
        context.coordinator.cableAutoTracePipe = cableAutoTracePipe
        context.coordinator.cableAutoPipeRadiusMeters = cableAutoPipeRadiusMeters
        context.coordinator.cablePathEnabled = cablePathEnabled
        context.coordinator.requestCablePathUndoBinding = $requestCablePathUndo
        context.coordinator.requestCablePathClearBinding = $requestCablePathClear
        context.coordinator.resetCaptureState()

        let pointCloudNode = SCNNode()
        pointCloudNode.name = "PointCloudNode"
        sceneView.scene.rootNode.addChildNode(pointCloudNode)
        context.coordinator.pointCloudNode = pointCloudNode
        let cableNode = SCNNode()
        cableNode.name = "CableHighlightNode"
        sceneView.scene.rootNode.addChildNode(cableNode)
        context.coordinator.cableHighlightNode = cableNode
        let cablePathNode = SCNNode()
        cablePathNode.name = "CablePathNode"
        sceneView.scene.rootNode.addChildNode(cablePathNode)
        context.coordinator.cablePathRootNode = cablePathNode
        let autoPipeNode = SCNNode()
        autoPipeNode.name = "AutoCablePipeNode"
        sceneView.scene.rootNode.addChildNode(autoPipeNode)
        context.coordinator.autoTracePipeRootNode = autoPipeNode
        let scanPathNode = SCNNode()
        scanPathNode.name = "ScanPathNode"
        sceneView.scene.rootNode.addChildNode(scanPathNode)
        context.coordinator.scanPathRootNode = scanPathNode

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        sceneView.addGestureRecognizer(tap)

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
        context.coordinator.qualityScoreBinding = $qualityScore
        context.coordinator.qualityHintBinding = $qualityHint
        context.coordinator.processingOptions = processingOptions
        context.coordinator.pointCloudPointSize = pointCloudPointSize
        context.coordinator.pointCloudDensity = pointCloudDensity
        context.coordinator.cableHighlightEnabled = cableHighlightEnabled
        context.coordinator.cableHighlightStrength = cableHighlightStrength
        context.coordinator.cableDetectOrange = cableDetectOrange
        context.coordinator.cableAutoTracePipe = cableAutoTracePipe
        context.coordinator.cableAutoPipeRadiusMeters = cableAutoPipeRadiusMeters
        context.coordinator.cablePathEnabled = cablePathEnabled
        if requestCablePathUndo {
            context.coordinator.undoCablePathPoint()
            DispatchQueue.main.async { requestCablePathUndo = false }
        }
        if requestCablePathClear {
            context.coordinator.clearCablePath()
            DispatchQueue.main.async { requestCablePathClear = false }
        }
        context.coordinator.updatePointCloudSamplingConfiguration()
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
        var meshPreviewPausedBinding: Binding<Bool>?
        var meshSegmentationActiveBinding: Binding<Bool>?
        var savedSegmentCountBinding: Binding<Int>?
        var requestExportBinding: Binding<Bool>?
        var trackingStateBinding: Binding<String>?
        var qualityScoreBinding: Binding<Int>?
        var qualityHintBinding: Binding<String>?
        var requestCablePathUndoBinding: Binding<Bool>?
        var requestCablePathClearBinding: Binding<Bool>?
        var knownMeshNodes: [UUID: SCNNode] = [:]
        var pointCloudNode: SCNNode?
        var cableHighlightNode: SCNNode?
        var cablePathRootNode: SCNNode?
        var autoTracePipeRootNode: SCNNode?
        var scanPathRootNode: SCNNode?
        var pointCloudService: PointCloudService?
        var scanProcedure: ScanProcedure = .pointCloud
        var lastAppliedProcedure: ScanProcedure?
        private var frameCount = 0
        var storage: StorageService?
        var scanId: UUID?
        var getLocation: (() -> (Double, Double)?)?
        var onExportDone: ((String?, Double?, Double?, Double?, Double?, Double?, [ScanKeyframe]) -> Void)?
        var processingOptions = MeshProcessingOptions()
        private var capturedKeyframes: [ScanKeyframe] = []
        private var lastKeyframeCaptureTime: CFTimeInterval = 0
        private let keyframeIntervalSeconds: CFTimeInterval = 0.8
        private let maxKeyframes = 120
        private var lastReportedTrackingState: String = ""
        /// In "Live-Vorschau (leicht)" nur wenige Anker visualisieren.
        private let maxLiveMeshAnchors = 8
        private var isMeshPreviewPaused = true
        /// Ab dieser Ankerzahl: Segmentieren + Rekonstruktion zurücksetzen.
        private let segmentationThresholdAnchors = 18
        private var cachedSegmentPaths: [String] = []
        private var nextSegmentIndex: Int = 0
        private var isFlushingMeshSegment = false
        private var isExportInProgress = false
        private var lastFrameTimestamp: TimeInterval?
        private var lastFramePosition: simd_float3?
        private var lastKeyframePosition: simd_float3?
        private var lastKeyframeForward: simd_float3?
        private var lastObservedSpeedMps: Float = 0
        private var autoPausedUntil: CFTimeInterval = 0
        private var lastPathPoint: simd_float3?
        private var pathSegmentNodes: [SCNNode] = []
        private let maxPathSegments = 1200
        private var currentQualityScore: Int = 0
        var pointCloudPointSize: Double = 1.0
        var pointCloudDensity: Double = 0.85
        private var pointCloudPreviewMaxPoints: Int = 8_000
        private var isPointCloudFrameProcessing = false
        var cableHighlightEnabled: Bool = true
        var cableHighlightStrength: Double = 0.75
        private var cablePreviewMaxPoints: Int = 6_000
        var cableDetectOrange: Bool = false
        var cableAutoTracePipe: Bool = true
        var cableAutoPipeRadiusMeters: Double = 0.028
        var cablePathEnabled: Bool = false
        /// Gespeicherte automatische Mittellinie (für Export + Live-Rohr).
        var autoTracedCenterline: [simd_float3] = []
        private var cablePathPoints: [simd_float3] = []
        private var cablePathSegmentNodes: [SCNNode] = []
        private var cablePathMarkerNodes: [SCNNode] = []

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
            updateLiveQuality(frame: frame, trackingState: stateStr)
            updateScanPath(with: frame)

            captureKeyframeIfNeeded(from: frame)

            // Punktwolke-Workflow unverändert
            guard scanProcedure == .pointCloud, let service = pointCloudService else { return }
            guard !isPointCloudFrameProcessing else { return }
            isPointCloudFrameProcessing = true
            DispatchQueue.global(qos: .userInitiated).async { [weak service] in
                service?.addPoints(from: frame)
                DispatchQueue.main.async { [weak self] in
                    self?.isPointCloudFrameProcessing = false
                }
            }
            frameCount += 1
            let count = service.pointCount
            if frameCount % 5 == 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.pointCloudCountBinding?.wrappedValue = count
                }
            }
            let now = CACurrentMediaTime()
            let minUpdateInterval: CFTimeInterval = cableHighlightEnabled ? 0.85 : 1.2
            guard count > 0, (now - lastGeometryUpdateTime) > minUpdateInterval else { return }
            lastGeometryUpdateTime = now
            let node = pointCloudNode
            let cableNode = cableHighlightNode
            let highlightOn = cableHighlightEnabled
            let tracePipeOn = cableAutoTracePipe
            DispatchQueue.global(qos: .userInitiated).async { [weak service, weak node, weak cableNode, weak self] in
                // Live-Punktwolke dynamisch je nach Dichteprofil begrenzen.
                guard let service = service, let node = node,
                      let geometry = service.makeSceneKitGeometry(
                        maxPoints: self?.pointCloudPreviewMaxPoints ?? 8_000,
                        pointSize: CGFloat(self?.pointCloudPointSize ?? 1.0)
                      ) else { return }
                let cableGeometry: SCNGeometry? = {
                    guard highlightOn else { return nil }
                    let maxPts = self?.cablePreviewMaxPoints ?? 6_000
                    // Kabel deutlich größer darstellen als Umgebungspunkte.
                    let size = CGFloat((self?.pointCloudPointSize ?? 1.0) * 3.2 + 1.2)
                    return service.makeCableHighlightGeometry(
                        maxPoints: maxPts,
                        pointSize: size,
                        highlightColor: (255, 0, 255)
                    )
                }()

                var newAutoLine: [simd_float3] = []
                if highlightOn, tracePipeOn {
                    let cableAll = service.copyCableCandidatePoints()
                    if cableAll.count >= 40 {
                        let vecs = cableAll.map { SIMD3<Float>($0.x, $0.y, $0.z) }
                        newAutoLine = MagentaCableAutoTrace.computeCenterline(fromCablePoints: vecs)
                    }
                }

                DispatchQueue.main.async {
                    node.geometry = geometry
                    node.position = SCNVector3(0, 0, 0)
                    // Wenn Kabelpunkte vorhanden sind, Umgebung abdunkeln, damit Magenta „knallt“.
                    node.opacity = (cableGeometry != nil) ? 0.28 : 1.0
                    if let cableNode = cableNode {
                        cableNode.geometry = cableGeometry
                        cableNode.position = SCNVector3(0, 0, 0)
                        cableNode.opacity = 1.0
                    }
                    guard let self = self else { return }
                    if !highlightOn || !tracePipeOn {
                        self.autoTracedCenterline = []
                        self.rebuildAutoTracePipe(line: [])
                    } else if newAutoLine.count >= 2 {
                        self.autoTracedCenterline = newAutoLine
                        self.rebuildAutoTracePipe(line: newAutoLine)
                    }
                }
            }
        }

        private func refreshPointCloudUI() {
            // Nur Zähler aktualisieren; Geometrie wird in session(didUpdate:) asynchron erstellt
            guard let service = pointCloudService else { return }
            pointCloudCountBinding?.wrappedValue = service.pointCount
        }

        func updatePointCloudSamplingConfiguration() {
            guard let service = pointCloudService else { return }
            let d = max(0.2, min(1.0, pointCloudDensity))
            // Dicht = kleines Voxel + weniger Pixel-Skipping.
            service.voxelSize = Float(0.002 + (1.0 - d) * 0.010) // 2 mm ... 12 mm
            if d >= 0.90 {
                service.depthStep = 1
            } else if d >= 0.70 {
                service.depthStep = 2
            } else if d >= 0.45 {
                service.depthStep = 3
            } else {
                service.depthStep = 4
            }
            // Lange Strecken: RAM stabil halten, aber bei hoher Dichte mehr Punkte erlauben.
            service.maxStoredPoints = Int(160_000 + (d * 240_000)) // 208k ... 400k
            pointCloudPreviewMaxPoints = Int(4_000 + (d * 20_000))
            let focus = max(0.2, min(1.0, cableHighlightStrength))
            cablePreviewMaxPoints = Int(2_000 + (focus * 14_000))
            service.detectOrangeCables = cableDetectOrange
        }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard cablePathEnabled else { return }
            guard let view = sceneView else { return }
            let p = gr.location(in: view)

            // 1) Versuche auf Mesh/Plane zu treffen, sonst 2) FeaturePoint.
            let results = view.hitTest(p, types: [.existingPlaneUsingExtent, .existingPlane, .featurePoint])
            guard let hit = results.first else { return }
            let t = hit.worldTransform.columns.3
            let world = simd_float3(t.x, t.y, t.z)
            appendCablePathPoint(world)
        }

        private func appendCablePathPoint(_ p: simd_float3) {
            cablePathPoints.append(p)
            addCablePathMarker(at: p)
            if cablePathPoints.count >= 2 {
                let a = cablePathPoints[cablePathPoints.count - 2]
                let b = cablePathPoints[cablePathPoints.count - 1]
                addCablePathSegment(from: a, to: b)
            }
        }

        private func addCablePathMarker(at p: simd_float3) {
            guard let root = cablePathRootNode else { return }
            let sphere = SCNSphere(radius: 0.015)
            let mat = sphere.firstMaterial ?? SCNMaterial()
            let cableColor = UIColor.magenta
            mat.diffuse.contents = cableColor
            mat.emission.contents = cableColor.withAlphaComponent(0.75)
            mat.lightingModel = .constant
            sphere.materials = [mat]
            let node = SCNNode(geometry: sphere)
            node.simdPosition = p
            root.addChildNode(node)
            cablePathMarkerNodes.append(node)
        }

        private func addCablePathSegment(from a: simd_float3, to b: simd_float3) {
            guard let root = cablePathRootNode else { return }
            let dir = b - a
            let length = simd_length(dir)
            guard length.isFinite, length > 0.001 else { return }
            let cylinder = SCNCylinder(radius: 0.012, height: CGFloat(length))
            cylinder.radialSegmentCount = 10
            let mat = cylinder.firstMaterial ?? SCNMaterial()
            let cableColor = UIColor.magenta
            mat.diffuse.contents = cableColor
            mat.emission.contents = cableColor.withAlphaComponent(0.75)
            mat.lightingModel = .constant
            cylinder.materials = [mat]
            let node = SCNNode(geometry: cylinder)
            node.simdPosition = (a + b) * 0.5
            // Zylinder ist entlang Y -> auf Segmentrichtung ausrichten.
            let up = simd_float3(0, 1, 0)
            let nDir = simd_normalize(dir)
            let axis = simd_cross(up, nDir)
            let dot = max(-1.0, min(1.0, simd_dot(up, nDir)))
            let angle = acos(dot)
            if simd_length(axis) > 0.0001, angle.isFinite {
                node.simdOrientation = simd_quatf(angle: angle, axis: simd_normalize(axis))
            }
            root.addChildNode(node)
            cablePathSegmentNodes.append(node)
        }

        func undoCablePathPoint() {
            guard !cablePathPoints.isEmpty else { return }
            cablePathPoints.removeLast()
            if let lastMarker = cablePathMarkerNodes.popLast() {
                lastMarker.removeFromParentNode()
            }
            if let lastSeg = cablePathSegmentNodes.popLast() {
                lastSeg.removeFromParentNode()
            }
        }

        func clearCablePath() {
            cablePathPoints.removeAll()
            for n in cablePathSegmentNodes { n.removeFromParentNode() }
            for n in cablePathMarkerNodes { n.removeFromParentNode() }
            cablePathSegmentNodes.removeAll()
            cablePathMarkerNodes.removeAll()
        }

        /// Magenta „Rohr“ aus automatisch erkanntem Kabelverlauf (Zylinderkette).
        private func rebuildAutoTracePipe(line: [simd_float3]) {
            guard let root = autoTracePipeRootNode else { return }
            root.childNodes.forEach { $0.removeFromParentNode() }
            guard line.count >= 2 else { return }
            let color = UIColor.magenta
            let radius: CGFloat = CGFloat(max(0.008, min(0.06, cableAutoPipeRadiusMeters)))
            for i in 1..<line.count {
                let a = line[i - 1]
                let b = line[i]
                let dir = b - a
                let length = simd_length(dir)
                guard length.isFinite, length > 0.001 else { continue }
                let cylinder = SCNCylinder(radius: radius, height: CGFloat(length))
                cylinder.radialSegmentCount = 12
                let mat = cylinder.firstMaterial ?? SCNMaterial()
                mat.diffuse.contents = color
                mat.emission.contents = color.withAlphaComponent(0.85)
                mat.lightingModel = .constant
                cylinder.materials = [mat]
                let node = SCNNode(geometry: cylinder)
                node.simdPosition = (a + b) * 0.5
                let up = simd_float3(0, 1, 0)
                let nDir = simd_normalize(dir)
                let axis = simd_cross(up, nDir)
                let dot = max(-1.0, min(1.0, simd_dot(up, nDir)))
                let angle = acos(dot)
                if simd_length(axis) > 0.0001, angle.isFinite {
                    node.simdOrientation = simd_quatf(angle: angle, axis: simd_normalize(axis))
                }
                root.addChildNode(node)
            }
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let view = sceneView else { return }
            updatePreviewMode(session: session)
            maybeFlushMeshSegment(session: session)
            if isMeshPreviewPaused {
                updateMeshCount(session: session)
                return
            }
            for anchor in anchors {
                guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
                let geo = SCNGeometry.fromAnchor(meshAnchor: meshAnchor)
                    .optimized(triangleEdgeLimitMeters: currentEdgeLimitMeters(multiplier: 2.4))
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
            updatePreviewMode(session: session)
            maybeFlushMeshSegment(session: session)
            if isMeshPreviewPaused {
                updateMeshCount(session: session)
                return
            }
            for anchor in anchors {
                guard let meshAnchor = anchor as? ARMeshAnchor,
                      let node = knownMeshNodes[anchor.identifier] else { continue }
                node.geometry = SCNGeometry.fromAnchor(meshAnchor: meshAnchor)
                    .optimized(triangleEdgeLimitMeters: currentEdgeLimitMeters(multiplier: 2.4))
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

        private func updatePreviewMode(session: ARSession) {
            if !processingOptions.lightweightLivePreview {
                if !isMeshPreviewPaused {
                    isMeshPreviewPaused = true
                }
                DispatchQueue.main.async { [weak self] in
                    self?.meshPreviewPausedBinding?.wrappedValue = true
                }
                if !knownMeshNodes.isEmpty {
                    // Speicher freigeben: niemals Live-Geometrie halten.
                    for (_, node) in knownMeshNodes {
                        node.removeFromParentNode()
                    }
                    knownMeshNodes.removeAll()
                }
                return
            }

            let count = session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor }.count ?? 0
            let now = CACurrentMediaTime()
            if processingOptions.autoPreviewThrottling {
                if count > maxLiveMeshAnchors + 4 {
                    autoPausedUntil = now + 1.6
                } else if lastReportedTrackingState == "limited" || lastReportedTrackingState == "notAvailable" {
                    autoPausedUntil = now + 1.2
                }
            }
            let forcePause = processingOptions.autoPreviewThrottling && now < autoPausedUntil
            let shouldPause = count > maxLiveMeshAnchors
            let nextPauseState = shouldPause || forcePause
            guard nextPauseState != isMeshPreviewPaused else { return }
            isMeshPreviewPaused = nextPauseState
            DispatchQueue.main.async { [weak self] in
                self?.meshPreviewPausedBinding?.wrappedValue = nextPauseState
            }
            if nextPauseState {
                // Speicher freigeben: vorhandene Live-Mesh-Knoten entfernen.
                for (_, node) in knownMeshNodes {
                    node.removeFromParentNode()
                }
                knownMeshNodes.removeAll()
            }
        }

        private func maybeFlushMeshSegment(session: ARSession) {
            guard scanProcedure == .mesh else { return }
            guard !isFlushingMeshSegment else { return }
            guard let frame = session.currentFrame else { return }
            let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
            guard meshAnchors.count >= segmentationThresholdAnchors else { return }
            isFlushingMeshSegment = true
            DispatchQueue.main.async { [weak self] in
                self?.meshSegmentationActiveBinding?.wrappedValue = true
            }

            // Aktuelle Anker in leichtes Zwischenmodell übernehmen.
            var segmentNodes: [SCNNode] = []
            segmentNodes.reserveCapacity(meshAnchors.count)
            for meshAnchor in meshAnchors {
                if processingOptions.autoCrop {
                    let cam = frame.camera.transform.columns.3
                    let meshPos = meshAnchor.transform.columns.3
                    let d = simd_distance(simd_float3(cam.x, cam.y, cam.z), simd_float3(meshPos.x, meshPos.y, meshPos.z))
                    if d > Float(processingOptions.depthRangeMeters) { continue }
                }
                guard let geo = SCNGeometry.copyFromAnchor(meshAnchor: meshAnchor)?
                    .optimized(triangleEdgeLimitMeters: currentEdgeLimitMeters(multiplier: 1.5)) else { continue }
                let node = SCNNode(geometry: geo)
                node.simdTransform = meshAnchor.transform
                segmentNodes.append(node)
            }

            if !segmentNodes.isEmpty, let storage, let scanId {
                let segmentScene = SCNScene()
                for node in segmentNodes {
                    segmentScene.rootNode.addChildNode(node)
                }
                if let relativePath = storage.saveMeshSegmentScene(segmentScene, scanId: scanId, segmentIndex: nextSegmentIndex) {
                    cachedSegmentPaths.append(relativePath)
                    nextSegmentIndex += 1
                    DispatchQueue.main.async { [weak self] in
                        self?.savedSegmentCountBinding?.wrappedValue = self?.cachedSegmentPaths.count ?? 0
                    }
                }
            }

            // Live-Nodes entfernen und Rekonstruktion zurücksetzen (ohne Tracking-Reset).
            for (_, node) in knownMeshNodes {
                node.removeFromParentNode()
            }
            knownMeshNodes.removeAll()

            let cfg = ARWorldTrackingConfiguration()
            cfg.worldAlignment = .gravity
            cfg.planeDetection = [.horizontal, .vertical]
            cfg.environmentTexturing = .automatic
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                cfg.sceneReconstruction = .meshWithClassification
            } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                cfg.sceneReconstruction = .mesh
            } else {
                cfg.sceneReconstruction = []
            }
            session.run(cfg, options: [.resetSceneReconstruction])
            isFlushingMeshSegment = false
        }

        func performExport() {
            guard !isExportInProgress else { return }
            isExportInProgress = true
            requestExportBinding?.wrappedValue = false
            guard let sceneView = sceneView,
                  let storage = storage,
                  let scanId = scanId,
                  let done = onExportDone else {
                isExportInProgress = false
                DispatchQueue.main.async { self.onExportDone?(nil, nil, nil, nil, nil, nil, []) }
                return
            }
            let session = sceneView.session
            guard let frame = session.currentFrame else {
                isExportInProgress = false
                DispatchQueue.main.async { done(nil, nil, nil, nil, nil, nil, []) }
                return
            }
            let cam = frame.camera.transform
            let originX = Double(cam.columns.3.x)
            let originY = Double(cam.columns.3.y)
            let originZ = Double(cam.columns.3.z)
            let loc = getLocation?()
            if capturedKeyframes.isEmpty, let fallback = makeKeyframe(from: frame, storage: storage) {
                capturedKeyframes.append(fallback)
            }
            DispatchQueue.main.async { [weak self] in
                self?.savedSegmentCountBinding?.wrappedValue = self?.cachedSegmentPaths.count ?? 0
            }

            if scanProcedure == .pointCloud, let service = pointCloudService, service.pointCount > 0 {
                let scanIdCopy = scanId
                let storageCopy = storage
                let cablePointsCopy = self.cablePathPoints
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let plyData = service.exportPLY() else {
                        DispatchQueue.main.async {
                            self?.isExportInProgress = false
                            done(nil, loc?.0, loc?.1, originX, originY, originZ, self?.capturedKeyframes ?? [])
                        }
                        return
                    }
                    let path = storageCopy.savePointCloudPLY(plyData, scanId: scanIdCopy)
                    let cableVecs = service.copyCableCandidatePoints().map { SIMD3<Float>($0.x, $0.y, $0.z) }
                    let finalAuto = MagentaCableAutoTrace.computeCenterline(fromCablePoints: cableVecs)
                    _ = storageCopy.saveCablePath(manualPoints: cablePointsCopy, autoTracePoints: finalAuto, autoTraceRadiusMeters: self?.cableAutoPipeRadiusMeters, scanId: scanIdCopy)
                    DispatchQueue.main.async {
                        self?.isExportInProgress = false
                        done(path, loc?.0, loc?.1, originX, originY, originZ, self?.capturedKeyframes ?? [])
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
            let segmentPaths = cachedSegmentPaths
            let cablePointsCopy = self.cablePathPoints
            let autoMeshSnapshot = self.autoTracedCenterline

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                autoreleasepool {
                    let scene = SCNScene()
                    var nodes: [SCNNode] = []
                    nodes.reserveCapacity(meshAnchors.count)

                    for relative in segmentPaths {
                        let full = storageCopy.fullPath(forStoredPath: relative)
                        let url = URL(fileURLWithPath: full)
                        if let loaded = try? SCNScene(url: url) {
                            for child in loaded.rootNode.childNodes {
                                scene.rootNode.addChildNode(child.clone())
                            }
                        }
                    }
                    for meshAnchor in meshAnchors {
                        if self?.processingOptions.autoCrop == true {
                            let camPos = frame.camera.transform.columns.3
                            let meshPos = meshAnchor.transform.columns.3
                            let d = simd_distance(simd_float3(camPos.x, camPos.y, camPos.z), simd_float3(meshPos.x, meshPos.y, meshPos.z))
                            if d > Float(self?.processingOptions.depthRangeMeters ?? 5) { continue }
                        }
                        let geo: SCNGeometry? = SCNGeometry.fromAnchor(meshAnchor: meshAnchor, frame: frame, orientation: orientation)
                            ?? SCNGeometry.copyFromAnchor(meshAnchor: meshAnchor)
                        guard let geo = geo?.optimized(triangleEdgeLimitMeters: self?.currentEdgeLimitMeters(multiplier: 1.0) ?? 0.02) else { continue }
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
                    _ = storageCopy.saveCablePath(manualPoints: cablePointsCopy, autoTracePoints: autoMeshSnapshot, autoTraceRadiusMeters: self?.cableAutoPipeRadiusMeters, scanId: scanIdCopy)
                    DispatchQueue.main.async {
                        self?.isExportInProgress = false
                        storageCopy.clearMeshSegments(scanId: scanIdCopy)
                        done(path, loc?.0, loc?.1, originX, originY, originZ, self?.capturedKeyframes ?? [])
                    }
                }
            }
        }

        func resetCaptureState() {
            updatePointCloudSamplingConfiguration()
            clearCablePath()
            autoTracedCenterline = []
            rebuildAutoTracePipe(line: [])
            capturedKeyframes.removeAll()
            lastKeyframeCaptureTime = 0
            isExportInProgress = false
            cachedSegmentPaths.removeAll()
            nextSegmentIndex = 0
            savedSegmentCountBinding?.wrappedValue = 0
            if let storage, let scanId {
                storage.clearMeshSegments(scanId: scanId)
            }
            lastFrameTimestamp = nil
            lastFramePosition = nil
            lastKeyframePosition = nil
            lastKeyframeForward = nil
            lastObservedSpeedMps = 0
            lastPathPoint = nil
            for node in pathSegmentNodes {
                node.removeFromParentNode()
            }
            pathSegmentNodes.removeAll()
        }

        private func updateScanPath(with frame: ARFrame) {
            guard let root = scanPathRootNode else { return }
            let t = frame.camera.transform.columns.3
            let current = simd_float3(t.x, t.y, t.z)
            guard let previous = lastPathPoint else {
                lastPathPoint = current
                return
            }
            let distance = simd_distance(current, previous)
            // Kleine Bewegungen ignorieren, damit die Linie sauber und performant bleibt.
            guard distance >= 0.08 else { return }
            lastPathPoint = current

            let color: UIColor
            if currentQualityScore >= 70 {
                color = UIColor.systemGreen.withAlphaComponent(0.9)
            } else if currentQualityScore >= 45 {
                color = UIColor.systemOrange.withAlphaComponent(0.9)
            } else {
                color = UIColor.systemRed.withAlphaComponent(0.9)
            }
            let segment = makeLineSegmentNode(from: previous, to: current, color: color)
            root.addChildNode(segment)
            pathSegmentNodes.append(segment)
            if pathSegmentNodes.count > maxPathSegments, let old = pathSegmentNodes.first {
                old.removeFromParentNode()
                pathSegmentNodes.removeFirst()
            }
        }

        private func makeLineSegmentNode(from a: simd_float3, to b: simd_float3, color: UIColor) -> SCNNode {
            let dir = b - a
            let length = simd_length(dir)
            let cylinder = SCNCylinder(radius: 0.01, height: CGFloat(max(0.001, length)))
            cylinder.radialSegmentCount = 6
            cylinder.firstMaterial?.diffuse.contents = color
            cylinder.firstMaterial?.emission.contents = color
            let node = SCNNode(geometry: cylinder)
            node.simdPosition = (a + b) * 0.5

            // Standardzylinder zeigt entlang Y-Achse -> auf Segmentrichtung ausrichten.
            let up = simd_float3(0, 1, 0)
            let nDir = simd_normalize(dir)
            let axis = simd_cross(up, nDir)
            let dot = max(-1.0, min(1.0, simd_dot(up, nDir)))
            let angle = acos(dot)
            if simd_length(axis) > 0.0001, angle.isFinite {
                node.simdOrientation = simd_quatf(angle: angle, axis: simd_normalize(axis))
            }
            return node
        }

        private func captureKeyframeIfNeeded(from frame: ARFrame) {
            guard let storage else { return }
            let now = CACurrentMediaTime()
            let dynamicInterval = adaptiveKeyframeInterval(for: lastObservedSpeedMps)
            guard now - lastKeyframeCaptureTime >= dynamicInterval else { return }
            guard capturedKeyframes.count < maxKeyframes else { return }
            guard isFrameEligibleForKeyframe(frame: frame) else { return }
            lastKeyframeCaptureTime = now

            guard let keyframe = makeKeyframe(from: frame, storage: storage) else { return }
            capturedKeyframes.append(keyframe)
            let t = frame.camera.transform.columns.3
            lastKeyframePosition = simd_float3(t.x, t.y, t.z)
            let f = frame.camera.transform.columns.2
            lastKeyframeForward = simd_normalize(simd_float3(-f.x, -f.y, -f.z))
        }

        private func adaptiveKeyframeInterval(for speed: Float) -> CFTimeInterval {
            switch processingOptions.captureProfile {
            case .pitDetail:
                if speed < 0.15 { return 0.55 }
                if speed < 0.45 { return 0.45 }
                if speed < 0.9 { return 0.65 }
                return 0.85
            case .pipelineLongRange:
                if speed < 0.15 { return 0.9 }
                if speed < 0.45 { return 0.75 }
                if speed < 0.9 { return 0.65 }
                return 0.8
            }
        }

        private func isFrameEligibleForKeyframe(frame: ARFrame) -> Bool {
            let t = frame.camera.transform.columns.3
            let currentPos = simd_float3(t.x, t.y, t.z)
            let f = frame.camera.transform.columns.2
            let currentForward = simd_normalize(simd_float3(-f.x, -f.y, -f.z))

            guard let lastPos = lastKeyframePosition, let lastForward = lastKeyframeForward else {
                return true
            }
            let moved = simd_distance(currentPos, lastPos)
            let angle = acos(max(-1, min(1, simd_dot(currentForward, lastForward))))
            let minMove: Float = (processingOptions.captureProfile == .pitDetail) ? 0.08 : 0.18
            let minTurn: Float = (processingOptions.captureProfile == .pitDetail) ? 0.12 : 0.16
            return moved >= minMove || angle >= minTurn
        }

        private func updateLiveQuality(frame: ARFrame, trackingState: String) {
            let nowT = frame.timestamp
            let cam = frame.camera.transform.columns.3
            let currentPos = simd_float3(cam.x, cam.y, cam.z)
            var speed: Float = lastObservedSpeedMps
            if let prevPos = lastFramePosition, let prevT = lastFrameTimestamp {
                let dt = max(0.001, nowT - prevT)
                speed = simd_distance(currentPos, prevPos) / Float(dt)
            }
            lastFramePosition = currentPos
            lastFrameTimestamp = nowT
            lastObservedSpeedMps = speed

            let meshCount = frame.anchors.compactMap { $0 as? ARMeshAnchor }.count
            var score = 0
            switch trackingState {
            case "normal": score += 60
            case "limited": score += 35
            default: score += 10
            }
            if speed >= 0.08 && speed <= 0.55 {
                score += 25
            } else if speed > 0.55 && speed <= 1.0 {
                score += 12
            } else if speed > 1.0 {
                score -= 10
            } else {
                score += 5
            }
            score += min(15, meshCount / 3)
            if isMeshPreviewPaused { score -= 6 }
            score = max(0, min(100, score))

            let hint: String
            if trackingState == "notAvailable" {
                hint = "Tracking verloren: Gerät langsam schwenken bis AR stabil ist."
            } else if trackingState == "limited" {
                hint = "Tracking eingeschränkt: mehr Struktur im Bild erfassen."
            } else if speed > 1.0 {
                hint = "Zu schnell: für mehr Details langsamer bewegen."
            } else if speed < 0.05 {
                hint = "Etwas weiterbewegen, damit neue Bereiche erfasst werden."
            } else if meshCount < 8 {
                hint = "Mehr Flächen aus mehreren Winkeln scannen."
            } else {
                hint = "Gute Scan-Qualität."
            }

            DispatchQueue.main.async { [weak self] in
                self?.qualityScoreBinding?.wrappedValue = score
                self?.qualityHintBinding?.wrappedValue = hint
            }
            currentQualityScore = score
        }

        private func makeKeyframe(from frame: ARFrame, storage: StorageService) -> ScanKeyframe? {
            let imageBuffer = frame.capturedImage
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            // Dynamische Ausrichtung: funktioniert für Hoch- und Querformat.
            let orientedCIImage = ciImage.oriented(currentImageOrientation())
            let ciContext = CIContext()
            guard let cgImage = ciContext.createCGImage(orientedCIImage, from: orientedCIImage.extent) else { return nil }
            let image = UIImage(cgImage: cgImage)
            guard let path = storage.saveImage(image, projectName: nil, overlay: nil, exportToAlbum: false) else { return nil }
            let t = frame.camera.transform.columns.3
            return ScanKeyframe(
                imagePath: path,
                timestamp: Date(),
                positionX: Double(t.x),
                positionY: Double(t.y),
                positionZ: Double(t.z)
            )
        }

        private func currentImageOrientation() -> CGImagePropertyOrientation {
            let uiOrientation = sceneView?.window?.windowScene?.interfaceOrientation ?? .portrait
            switch uiOrientation {
            case .portrait:
                return .right
            case .portraitUpsideDown:
                return .left
            case .landscapeLeft:
                return .down
            case .landscapeRight:
                return .up
            default:
                return .right
            }
        }

        private func currentEdgeLimitMeters(multiplier: Double) -> Float {
            let voxelM = max(0.002, min(0.02, processingOptions.voxelSizeMillimeters / 1000.0))
            let simplifyFactor = 1.0 + (processingOptions.simplificationPercent / 100.0)
            return Float(voxelM * simplifyFactor * multiplier)
        }
    }
}

