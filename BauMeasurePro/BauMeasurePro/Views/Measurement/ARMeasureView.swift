import SwiftUI
import ARKit
import SceneKit
import CoreLocation
import UIKit

// MARK: - SwiftUI AR-Messung (im Projekt)

struct ARMeasureView: View {
    let projectId: UUID
    @EnvironmentObject var viewModel: MapViewModel
    @StateObject private var locationService = LocationService()
    private let storage = StorageService()

    @State private var distanceMeters: Double?
    @State private var pointACounted = false
    @State private var requestSnapshot = false
    @State private var capturedImage: UIImage?
    @State private var showSavedAlert = false
    @State private var sceneResetTrigger = 0
    @State private var raycastFailed = false
    @State private var requestUndo = false
    @State private var zoomFactor: Double = 1.0
    @State private var pendingImage: UIImage?

    /// true = Polylinie (mehrere Punkte), false = Einzelstrecke (A–B)
    @State private var isPolylineMode = false
    @State private var polylinePointCount = 0
    @State private var polylinePointsState: [PolylinePoint] = []
    @State private var pendingPolylinePoints: [PolylinePoint]?
    @State private var pendingPolylineMeters: Double?
    @State private var polylineSegmentMeters: [Double] = []
    @State private var pendingPolylineSegmentMeters: [Double]?
    /// AR-Tracking-Status: „normal“, „limited“, „notAvailable“ – bei limited/notAvailable Warnung anzeigen.
    @State private var trackingStateMessage: String = "normal"

    private var nextMeasurementIndex: Int {
        (viewModel.project(byId: projectId)?.measurements.count ?? 0) + 1
    }

    var body: some View {
        mainContent
            .onChange(of: capturedImage) { _, img in
                guard let img = img else { return }
                capturedImage = nil
                if isPolylineMode, polylinePointCount >= 2 {
                    pendingImage = img
                    pendingPolylinePoints = self.polylinePointsState
                    pendingPolylineMeters = distanceMeters
                    pendingPolylineSegmentMeters = polylineSegmentMeters
                    finishSaveWithCurrentPendingImage()
                } else {
                    pendingImage = img
                    pendingPolylinePoints = nil
                    pendingPolylineMeters = nil
                    pendingPolylineSegmentMeters = nil
                    finishSaveWithCurrentPendingImage()
                }
        }
        .alert("Gespeichert", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Die AR-Messung wurde dem Projekt hinzugefügt. Oberfläche & Verlegeart kannst du in den Messungsdetails nachträglich eintragen.")
        }
    }

    /// Speichert die Messung mit dem aktuell vorbereiteten `pendingImage` / Polyline-Daten (reine AR-Messung, kein 3D-Scan).
    private func finishSaveWithCurrentPendingImage() {
        guard let baseImage = pendingImage else { return }
        saveARMeasurement(image: baseImage, polylinePoints: pendingPolylinePoints, polylineMeters: pendingPolylineMeters, polylineSegmentMeters: pendingPolylineSegmentMeters)
        pendingImage = nil
        pendingPolylinePoints = nil
        pendingPolylineMeters = nil
        pendingPolylineSegmentMeters = nil
        resetForNewMeasurement()
        showSavedAlert = true
    }

    private var mainContent: some View {
        ZStack {
            arScene
            overlayContent
        }
    }

    private var arScene: some View {
        ARMeasureSceneView(
            distanceMeters: $distanceMeters,
            pointACounted: $pointACounted,
            requestSnapshot: $requestSnapshot,
            capturedImage: $capturedImage,
            raycastFailed: $raycastFailed,
            resetTrigger: sceneResetTrigger,
            requestUndo: $requestUndo,
            zoomFactor: zoomFactor,
            measurementIndex: nextMeasurementIndex,
            isPolylineMode: isPolylineMode,
            polylinePointCount: $polylinePointCount,
            onPolyPointAdded: {
                let loc = locationService.location
                let coord = loc?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                polylinePointsState.append(
                    PolylinePoint(
                        latitude: coord.latitude,
                        longitude: coord.longitude,
                        horizontalAccuracy: loc?.horizontalAccuracy,
                        verticalAccuracy: loc?.verticalAccuracy,
                        altitude: loc?.altitude,
                        course: loc?.course,
                        courseAccuracy: loc?.courseAccuracy
                    )
                )
            },
            onPolySegmentAdded: { meters in
                polylineSegmentMeters.append(meters)
            },
            onPolySegmentRemoved: {
                if !polylineSegmentMeters.isEmpty { polylineSegmentMeters.removeLast() }
            },
            storage: storage,
            projectId: projectId,
            onTrackingStateChange: { trackingStateMessage = $0 }
        )
        .ignoresSafeArea()
        .zIndex(0)
    }

    private var overlayContent: some View {
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .overlay(alignment: .top) { topOverlay }
            .overlay(alignment: .bottom) { bottomOverlay }
            .zIndex(1)
    }

    @ViewBuilder
    private var topOverlay: some View {
        VStack(spacing: 8) {
            if trackingStateMessage == "limited" || trackingStateMessage == "notAvailable" {
                Text(trackingStateMessage == "limited"
                     ? "Tracking eingeschränkt – Kamera langsam bewegen, mehr Textur/Struktur erfassen"
                     : "Tracking nicht verfügbar – Gerät bewegen bis AR wieder erkannt")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.orange.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if raycastFailed {
                Text("Keine Fläche erkannt – Kamera langsam bewegen und erneut tippen")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if pointACounted && distanceMeters == nil {
                Text("Tippe für Endpunkt")
                    .font(.headline)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let d = distanceMeters {
                Text(String(format: "%.2f m", d))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 4, x: 1, y: 1)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        VStack(spacing: 12) {
            if !pointACounted && polylinePointCount == 0 && distanceMeters == nil {
                Picker("Modus", selection: $isPolylineMode) {
                    Text("Einzelstrecke").tag(false)
                    Text("Polylinie").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)
            }
            zoomButtons
            actionButtons
        }
        .padding(.bottom, 40)
    }

    @ViewBuilder
    private var zoomButtons: some View {
        HStack(spacing: 8) {
            ForEach([1.0, 1.5, 2.0], id: \.self) { factor in
                if zoomFactor == factor {
                    Button(String(format: "%.1f×", factor)) {
                        zoomFactor = factor
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(String(format: "%.1f×", factor)) {
                        zoomFactor = factor
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 16) {
            if isPolylineMode {
                if polylinePointCount > 0 {
                    Button {
                        requestUndo = true
                    } label: {
                        Label("Rückgängig", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                }
                if polylinePointCount >= 2 {
                    Button("Polymessung beenden") {
                        requestSnapshot = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                if pointACounted || distanceMeters != nil {
                    Button {
                        requestUndo = true
                    } label: {
                        Label("Rückgängig", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                }
                if distanceMeters != nil {
                    Button("Speichern") { requestSnapshot = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            if distanceMeters != nil || (isPolylineMode && polylinePointCount >= 2) {
                Button("Neue Messung") {
                    resetForNewMeasurement()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func resetForNewMeasurement() {
        distanceMeters = nil
        pointACounted = false
        raycastFailed = false
        polylinePointCount = 0
        polylinePointsState.removeAll()
        polylineSegmentMeters.removeAll()
        sceneResetTrigger += 1
    }

    private func saveARMeasurement(image: UIImage, polylinePoints: [PolylinePoint]?, polylineMeters: Double?, polylineSegmentMeters: [Double]?) {
        let project = viewModel.project(byId: projectId)
        let projectName = project?.name
        let overlay = StorageService.PhotoOverlayInfo(
            strasse: project?.strasse,
            hausnummer: project?.hausnummer,
            nvtNummer: project?.nvtNummer,
            date: Date(),
            oberflaecheText: nil,
            verlegeartText: nil
        )
        let meters: Double
        if let poly = polylineMeters, !(polylinePoints?.isEmpty ?? true) {
            meters = poly
        } else if let m = distanceMeters {
            meters = m
        } else {
            return
        }
        guard let path = storage.saveImage(image, projectName: projectName, overlay: overlay) else { return }
        let loc = locationService.location
        let lat = loc?.coordinate.latitude ?? 0
        let lon = loc?.coordinate.longitude ?? 0
        let horizAcc = loc?.horizontalAccuracy
        let vertAcc = loc?.verticalAccuracy
        let alt = loc?.altitude
        let course = loc?.course
        let courseAcc = loc?.courseAccuracy
        let firstPoly = polylinePoints?.first
        let lastPoly = polylinePoints?.last

        func addMeasurement(address: String) {
            var m = Measurement(
                imagePath: path,
                latitude: lat,
                longitude: lon,
                horizontalAccuracy: horizAcc,
                verticalAccuracy: vertAcc,
                altitude: alt,
                course: course,
                courseAccuracy: courseAcc,
                address: address,
                points: [],
                totalDistance: 0,
                referenceMeters: meters,
                date: Date(),
                polylinePoints: polylinePoints,
                polylineSegmentMeters: polylineSegmentMeters
            )
            if let project = viewModel.project(byId: projectId) {
                let nextIndex = project.measurements.count + 1
                m.index = nextIndex
            }
            m.isARMeasurement = true
            if let poly = polylinePoints, !poly.isEmpty {
                m.startLatitude = firstPoly?.latitude ?? lat
                m.startLongitude = firstPoly?.longitude ?? lon
                m.endLatitude = lastPoly?.latitude ?? lat
                m.endLongitude = lastPoly?.longitude ?? lon
            } else {
                m.startLatitude = lat
                m.startLongitude = lon
                m.endLatitude = lat
                m.endLongitude = lon
            }
            viewModel.addMeasurement(toProjectId: projectId, m)
        }

        if let l = loc {
            locationService.getAddress(from: l) { addr in
                addMeasurement(address: addr.isEmpty ? "Standort unbekannt" : addr)
            }
        } else {
            addMeasurement(address: "Standort unbekannt")
        }
    }

}

// MARK: - ARSCNView mit Raycast, Punkten, Linie und Snapshot

struct ARMeasureSceneView: UIViewRepresentable {
    @Binding var distanceMeters: Double?
    @Binding var pointACounted: Bool
    @Binding var requestSnapshot: Bool
    @Binding var capturedImage: UIImage?
    @Binding var raycastFailed: Bool
    var resetTrigger: Int
    @Binding var requestUndo: Bool
    var zoomFactor: Double
    var measurementIndex: Int
    var isPolylineMode: Bool
    @Binding var polylinePointCount: Int
    var onPolyPointAdded: () -> Void
    var onPolySegmentAdded: (Double) -> Void
    var onPolySegmentRemoved: () -> Void
    var storage: StorageService
    var projectId: UUID
    /// Wird aufgerufen bei Änderung des AR-Tracking-Status („normal“, „limited“, „notAvailable“).
    var onTrackingStateChange: ((String) -> Void)?

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.clipsToBounds = true

        let sceneView = ARSCNView(frame: .zero)
        sceneView.delegate = context.coordinator
        sceneView.session.delegate = context.coordinator
        sceneView.autoenablesDefaultLighting = true
        sceneView.antialiasingMode = .multisampling4X

        // Reine AR-Messung: nur Plane-Tracking + Raycast, kein LiDAR/Mesh (3D-Scan ausgeklammert).
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        sceneView.session.run(config)

        container.addSubview(sceneView)
        // SceneView immer in Containergröße halten; Zoom per Transform (verhindert riesige Snapshots + Layout-Jitter).
        sceneView.frame = container.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        container.addGestureRecognizer(tap)

        context.coordinator.containerView = container
        context.coordinator.sceneView = sceneView
        context.coordinator.storage = storage
        context.coordinator.projectId = projectId
        context.coordinator.onTrackingStateChange = onTrackingStateChange
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.storage = storage
        context.coordinator.projectId = projectId
        context.coordinator.onTrackingStateChange = onTrackingStateChange
        // Zoom: nur per Transform anwenden (Frame bleibt stabil -> kein Zittern).
        if let sceneView = context.coordinator.sceneView {
            let z = max(1.0, min(zoomFactor, 2.0))
            if abs(context.coordinator.currentZoomFactor - z) > 0.0001 {
                context.coordinator.currentZoomFactor = z
                // Transform um die Mitte, damit Zoom "in place" bleibt.
                sceneView.transform = CGAffineTransform(scaleX: z, y: z)
                sceneView.center = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
            }
        }

        if requestSnapshot {
            let distance = distanceMeters
            let coord = context.coordinator
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let img = coord.sceneView?.snapshot() ?? UIImage()
                capturedImage = addReadableOverlay(to: img, distance: distance)
                requestSnapshot = false
            }
        }
        if resetTrigger > 0, resetTrigger != context.coordinator.lastResetTrigger {
            context.coordinator.lastResetTrigger = resetTrigger
            context.coordinator.clearMeasurementNodes()
        }
        if requestUndo {
            requestUndo = false
            context.coordinator.undoLastPoint()
        }
    }

    private func addReadableOverlay(to image: UIImage, distance: Double?) -> UIImage? {
        guard let d = distance else { return image }
        let text = String(format: "%.2f m", d)
        let w = image.size.width
        let h = image.size.height
        let fontSize = min(w, h) * 0.12
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(at: .zero)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle,
                .strokeColor: UIColor.black,
                .strokeWidth: -min(4, fontSize * 0.15)
            ]
            let rect = CGRect(x: 0, y: h * 0.4 - fontSize, width: w, height: fontSize * 2)
            (text as NSString).draw(in: rect, withAttributes: attrs)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        var parent: ARMeasureSceneView
        weak var containerView: UIView?
        weak var sceneView: ARSCNView?
        var pointANode: SCNNode?
        var pointBNode: SCNNode?
        var lineNode: SCNNode?
        var labelANode: SCNNode?
        var labelBNode: SCNNode?
        var pointA: simd_float3?
        var pointB: simd_float3?
        var lastResetTrigger = 0
        var currentZoomFactor: Double = 1.0

        var polyPoints: [simd_float3] = []
        var polyPointNodes: [SCNNode] = []
        var polyLineNodes: [SCNNode] = []
        var measurementAnchors: [ARAnchor] = []
        /// Drift-Korrektur: alle ~20 m ein Anchor, damit ARKit die Strecke segmentweise stabil hält.
        var segmentAnchors: [ARAnchor] = []
        var lastSegmentAnchorDistanceM: Float = 0
        var distanceKalman: KalmanFilter?
        var onTrackingStateChange: ((String) -> Void)?
        var lastReportedTrackingState: String = ""

        weak var pathLineNode: SCNNode?
        var pathPositions: [simd_float3] = []
        var lastPathPosition: simd_float3?
        var frameCount = 0
        var storage: StorageService?
        var projectId: UUID?

        init(_ parent: ARMeasureSceneView) {
            self.parent = parent
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            frameCount += 1
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
                    self?.onTrackingStateChange?(stateStr)
                }
            }
        }

        private func updateDashedPathLine() {
            guard let pathNode = pathLineNode, pathPositions.count >= 2 else { return }
            pathNode.childNodes.forEach { $0.removeFromParentNode() }
            let dashLength: Float = 0.08
            let gapLength: Float = 0.05
            let step = dashLength + gapLength
            let radius: CGFloat = 0.012
            for i in 0 ..< (pathPositions.count - 1) {
                let a = pathPositions[i]
                let b = pathPositions[i + 1]
                let seg = b - a
                let len = simd_length(seg)
                guard len > 0.001 else { continue }
                let dir = seg / len
                var t: Float = 0
                while t < len {
                    let tEnd = min(t + dashLength, len)
                    let start = a + dir * t
                    let end = a + dir * tEnd
                    let segLen = simd_length(end - start)
                    guard segLen > 0.001 else { t += step; continue }
                    let cylinder = SCNCylinder(radius: radius, height: CGFloat(segLen))
                    cylinder.firstMaterial?.diffuse.contents = UIColor.systemOrange
                    cylinder.firstMaterial?.lightingModel = .constant
                    let node = SCNNode(geometry: cylinder)
                    node.simdPosition = (start + end) * 0.5
                    node.simdOrientation = simd_quatf(from: simd_make_float3(0, 1, 0), to: simd_normalize(end - start))
                    pathNode.addChildNode(node)
                    t += step
                }
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let container = containerView, let view = sceneView else { return }
            let locInContainer = gesture.location(in: container)
            let locInScene = CGPoint(x: locInContainer.x - view.frame.origin.x, y: locInContainer.y - view.frame.origin.y)
            if parent.isPolylineMode {
                addPolyPoint(view: view, at: locInScene)
            } else {
                trySetPoint(view: view, at: locInScene)
            }
        }

        /// Raycast mit Mesh-Snapping: zuerst .existingPlaneGeometry (LiDAR-Mesh), sonst .estimatedPlane.
        private func raycastResult(view: ARSCNView, at point: CGPoint) -> (ARRaycastResult, simd_float3)? {
            let targets: [ARRaycastQuery.Target] = [.existingPlaneGeometry, .estimatedPlane]
            for target in targets {
                guard let query = view.raycastQuery(from: point, allowing: target, alignment: .any) else { continue }
                let results = view.session.raycast(query)
                guard let first = results.first else { continue }
                let pos = simd_make_float3(first.worldTransform.columns.3.x, first.worldTransform.columns.3.y, first.worldTransform.columns.3.z)
                return (first, pos)
            }
            return nil
        }

        private func trySetPoint(view: ARSCNView, at loc: CGPoint) {
            let hasPointA = pointANode?.parent != nil
            let hasPointB = pointBNode?.parent != nil
            if !hasPointA {
                setPointA(view: view, at: loc)
            } else if !hasPointB {
                setPointB(view: view, at: loc)
            }
        }

        private func addPolyPoint(view: ARSCNView, at point: CGPoint) {
            guard let (first, pos) = raycastResult(view: view, at: point) else {
                DispatchQueue.main.async { self.parent.raycastFailed = true }
                return
            }
            DispatchQueue.main.async { self.parent.raycastFailed = false }

            let anchor = ARAnchor(transform: first.worldTransform)
            view.session.add(anchor: anchor)
            measurementAnchors.append(anchor)

            polyPoints.append(pos)

            let sphere = SCNSphere(radius: 0.04)
            sphere.firstMaterial?.diffuse.contents = UIColor.systemRed
            let node = SCNNode(geometry: sphere)
            node.simdPosition = pos
            view.scene.rootNode.addChildNode(node)
            polyPointNodes.append(node)

            let label = makeBillboardLabel(text: "\(polyPoints.count)")
            label.position = SCNVector3(0, 0.06, 0)
            node.addChildNode(label)

            if polyPoints.count >= 2 {
                let prev = polyPoints[polyPoints.count - 2]
                addLineSegment(from: prev, to: pos, in: view)
                let segmentMeters = Double(simd_distance(prev, pos))
                DispatchQueue.main.async {
                    self.parent.onPolySegmentAdded(segmentMeters)
                }
            }

            var total: Float = 0
            for i in 1 ..< polyPoints.count {
                total += simd_distance(polyPoints[i - 1], polyPoints[i])
            }
            // Drift-Korrektur: alle 20 m einen zusätzlichen Anchor setzen (Segment-Mapping).
            let totalM = total
            if totalM >= lastSegmentAnchorDistanceM + 20 {
                let driftAnchor = ARAnchor(transform: first.worldTransform)
                view.session.add(anchor: driftAnchor)
                segmentAnchors.append(driftAnchor)
                lastSegmentAnchorDistanceM = (totalM / 20).rounded(.down) * 20
            }
            DispatchQueue.main.async {
                self.parent.distanceMeters = Double(total)
                self.parent.onPolyPointAdded()
                self.parent.polylinePointCount = self.polyPoints.count
            }
        }

        private func addLineSegment(from start: simd_float3, to end: simd_float3, in view: ARSCNView) {
            let vec = end - start
            let length = simd_length(vec)
            guard length > 0.001 else { return }
            let cylinder = SCNCylinder(radius: 0.015, height: CGFloat(length))
            cylinder.firstMaterial?.diffuse.contents = UIColor.systemYellow
            let node = SCNNode(geometry: cylinder)
            node.simdPosition = (start + end) * 0.5
            let direction = vec / length
            node.simdOrientation = simd_quatf(from: simd_make_float3(0, 1, 0), to: direction)
            view.scene.rootNode.addChildNode(node)
            polyLineNodes.append(node)
        }

        private func setPointA(view: ARSCNView, at point: CGPoint) {
            guard let (first, pos) = raycastResult(view: view, at: point) else {
                DispatchQueue.main.async { self.parent.raycastFailed = true }
                return
            }
            DispatchQueue.main.async { self.parent.raycastFailed = false }

            let anchor = ARAnchor(transform: first.worldTransform)
            view.session.add(anchor: anchor)
            measurementAnchors.append(anchor)

            pointA = pos
            pointBNode?.removeFromParentNode()
            pointBNode = nil
            pointB = nil
            lineNode?.removeFromParentNode()
            lineNode = nil

            let sphere = SCNSphere(radius: 0.04)
            sphere.firstMaterial?.diffuse.contents = UIColor.systemRed
            let node = SCNNode(geometry: sphere)
            node.simdPosition = pos
            node.name = "pointA"
            view.scene.rootNode.addChildNode(node)
            pointANode = node
            
            labelANode?.removeFromParentNode()
            let label = makeBillboardLabel(text: "\(parent.measurementIndex)A")
            label.position = SCNVector3(0, 0.06, 0)
            node.addChildNode(label)
            labelANode = label

            DispatchQueue.main.async {
                self.parent.pointACounted = true
            }
        }

        private func setPointB(view: ARSCNView, at point: CGPoint) {
            guard let (first, pos) = raycastResult(view: view, at: point) else {
                DispatchQueue.main.async { self.parent.raycastFailed = true }
                return
            }
            DispatchQueue.main.async { self.parent.raycastFailed = false }

            let anchor = ARAnchor(transform: first.worldTransform)
            view.session.add(anchor: anchor)
            measurementAnchors.append(anchor)

            pointB = pos

            let sphere = SCNSphere(radius: 0.04)
            sphere.firstMaterial?.diffuse.contents = UIColor.systemRed
            let node = SCNNode(geometry: sphere)
            node.simdPosition = pos
            node.name = "pointB"
            view.scene.rootNode.addChildNode(node)
            pointBNode = node
            
            labelBNode?.removeFromParentNode()
            let label = makeBillboardLabel(text: "\(parent.measurementIndex)B")
            label.position = SCNVector3(0, 0.06, 0)
            node.addChildNode(label)
            labelBNode = label

            if let a = pointA {
                let raw = simd_distance(a, pos)
                addLine(from: a, to: pos, in: view)
                DispatchQueue.main.async {
                    let filtered: Double
                    if var k = self.distanceKalman {
                        filtered = Double(k.update(measurement: raw))
                        self.distanceKalman = k
                    } else {
                        var k = KalmanFilter(initialValue: raw)
                        self.distanceKalman = k
                        filtered = Double(raw)
                    }
                    self.parent.distanceMeters = filtered
                }
            }
        }

        private func addLine(from start: simd_float3, to end: simd_float3, in view: ARSCNView) {
            let vec = end - start
            let length = simd_length(vec)
            guard length > 0.001 else { return }
            let cylinder = SCNCylinder(radius: 0.015, height: CGFloat(length))
            cylinder.firstMaterial?.diffuse.contents = UIColor.systemYellow
            let node = SCNNode(geometry: cylinder)
            node.simdPosition = (start + end) * 0.5
            let direction = vec / length
            node.simdOrientation = simd_quatf(from: simd_make_float3(0, 1, 0), to: direction)
            view.scene.rootNode.addChildNode(node)
            lineNode = node
        }
        
        private func makeBillboardLabel(text: String) -> SCNNode {
            let t = SCNText(string: text, extrusionDepth: 0.5)
            t.font = UIFont.boldSystemFont(ofSize: 10)
            t.flatness = 0.1
            t.firstMaterial?.diffuse.contents = UIColor.white
            t.firstMaterial?.isDoubleSided = true
            t.firstMaterial?.lightingModel = .constant
            
            let textNode = SCNNode(geometry: t)
            // Zentrieren
            let (minB, maxB) = t.boundingBox
            let dx = (maxB.x - minB.x) / 2
            let dy = (maxB.y - minB.y) / 2
            textNode.pivot = SCNMatrix4MakeTranslation(minB.x + dx, minB.y + dy, 0)
            // Skalierung auf AR-Weltgröße
            textNode.scale = SCNVector3(0.0035, 0.0035, 0.0035)
            
            let bg = SCNPlane(width: 0.08, height: 0.04)
            bg.cornerRadius = 0.008
            bg.firstMaterial?.diffuse.contents = UIColor.black.withAlphaComponent(0.65)
            bg.firstMaterial?.isDoubleSided = true
            bg.firstMaterial?.lightingModel = .constant
            let bgNode = SCNNode(geometry: bg)
            bgNode.position = SCNVector3(0, 0, -0.001)
            
            let holder = SCNNode()
            holder.addChildNode(bgNode)
            holder.addChildNode(textNode)
            
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .Y
            holder.constraints = [billboard]
            return holder
        }

        func clearMeasurementNodes() {
            distanceKalman = nil
            lastSegmentAnchorDistanceM = 0
            if let session = sceneView?.session {
                for anchor in measurementAnchors { session.remove(anchor: anchor) }
                for anchor in segmentAnchors { session.remove(anchor: anchor) }
            }
            measurementAnchors.removeAll()
            segmentAnchors.removeAll()
            pointANode?.removeFromParentNode()
            pointBNode?.removeFromParentNode()
            lineNode?.removeFromParentNode()
            labelANode?.removeFromParentNode()
            labelBNode?.removeFromParentNode()
            pointANode = nil
            pointBNode = nil
            lineNode = nil
            labelANode = nil
            labelBNode = nil
            pointA = nil
            pointB = nil
            for n in polyPointNodes { n.removeFromParentNode() }
            for n in polyLineNodes { n.removeFromParentNode() }
            polyPointNodes.removeAll()
            polyLineNodes.removeAll()
            polyPoints.removeAll()
            pathPositions.removeAll()
            lastPathPosition = nil
            pathLineNode?.childNodes.forEach { $0.removeFromParentNode() }
        }

        func undoLastPoint() {
            if parent.isPolylineMode {
                guard !polyPoints.isEmpty else { return }
                if let lastAnchor = measurementAnchors.popLast() {
                    sceneView?.session.remove(anchor: lastAnchor)
                }
                polyPointNodes.last?.removeFromParentNode()
                polyPointNodes.removeLast()
                polyLineNodes.last?.removeFromParentNode()
                polyLineNodes.removeLast()
                polyPoints.removeLast()
                DispatchQueue.main.async {
                    self.parent.onPolySegmentRemoved()
                }
                var total: Float = 0
                for i in 1 ..< polyPoints.count {
                    total += simd_distance(polyPoints[i - 1], polyPoints[i])
                }
                DispatchQueue.main.async {
                    self.parent.distanceMeters = self.polyPoints.isEmpty ? nil : Double(total)
                    self.parent.polylinePointCount = self.polyPoints.count
                }
            } else if pointBNode?.parent != nil {
                if let lastAnchor = measurementAnchors.popLast() {
                    sceneView?.session.remove(anchor: lastAnchor)
                }
                pointBNode?.removeFromParentNode()
                pointBNode = nil
                pointB = nil
                lineNode?.removeFromParentNode()
                lineNode = nil
                labelBNode?.removeFromParentNode()
                labelBNode = nil
                self.parent.distanceMeters = nil
                self.parent.raycastFailed = false
            } else if pointANode?.parent != nil {
                if let lastAnchor = measurementAnchors.popLast() {
                    sceneView?.session.remove(anchor: lastAnchor)
                }
                pointANode?.removeFromParentNode()
                pointANode = nil
                pointA = nil
                labelANode?.removeFromParentNode()
                labelANode = nil
                self.parent.pointACounted = false
                self.parent.raycastFailed = false
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {}
        func sessionWasInterrupted(_ session: ARSession) {}
        func sessionInterruptionEnded(_ session: ARSession) {}
    }
}

#Preview {
    ARMeasureView(projectId: UUID())
        .environmentObject(MapViewModel())
}
