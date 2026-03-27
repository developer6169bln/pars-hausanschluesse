import SwiftUI
import ARKit
import SceneKit
import CoreLocation
import simd

struct ARLeitungenGeoView: View {
    @State private var features: [GeoFeature] = []
    @State private var statusText = "Lade GeoJSON..."
    @State private var calibrateTrigger = 0
    @State private var reloadTrigger = 0
    @State private var arPitCaptureTrigger = 0
    @State private var arPitScanExecuteTrigger = 0
    @State private var showCaptureSheet = false
    @State private var showFeatureListSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ARLeitungenSceneRepresentable(
                features: features,
                statusText: $statusText,
                calibrateTrigger: calibrateTrigger,
                reloadTrigger: reloadTrigger,
                arPitCaptureTrigger: arPitCaptureTrigger,
                arPitScanExecuteTrigger: arPitScanExecuteTrigger
            ) { captured in
                let newFeature = GeoFeature(
                    point: captured.coordinate,
                    depth: captured.depth,
                    width: captured.width,
                    length: captured.length
                )
                features.append(newFeature)
                let ok = GeoJSONLoader.save(features: features, filename: "leitungen")
                statusText = ok
                    ? String(format: "AR-Grube gespeichert (B %.2f m, L %.2f m, T %.2f m)", captured.width, captured.length, captured.depth)
                    : "Speichern fehlgeschlagen."
                reloadTrigger += 1
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Referenzpunkt setzen") { calibrateTrigger += 1 }
                        .buttonStyle(.borderedProminent)
                    Button("AR-Erfassung starten") { arPitCaptureTrigger += 1 }
                        .buttonStyle(.borderedProminent)
                    Button("Scan jetzt ausführen") { arPitScanExecuteTrigger += 1 }
                        .buttonStyle(.borderedProminent)
                    Button("Letztes rückgängig") {
                        undoLastFeature()
                    }
                    .buttonStyle(.bordered)
                    .disabled(features.isEmpty)
                    Button("GeoJSON neu laden") {
                        loadFeatures()
                        reloadTrigger += 1
                    }
                    .buttonStyle(.bordered)
                    Button("Erfassen") { showCaptureSheet = true }
                        .buttonStyle(.bordered)
                    Button("Löschen") { showFeatureListSheet = true }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Leitungen AR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    Button {
                        undoLastFeature()
                    } label: {
                        Label("Rückgängig", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(features.isEmpty)
                    Button {
                        showFeatureListSheet = true
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                    Button {
                        showCaptureSheet = true
                    } label: {
                        Label("Erfassen", systemImage: "plus.circle")
                    }
                }
            }
        }
        .onAppear {
            loadFeatures()
        }
        .sheet(isPresented: $showCaptureSheet) {
            GeoFeatureCaptureView { newFeature in
                features.append(newFeature)
                let ok = GeoJSONLoader.save(features: features, filename: "leitungen")
                statusText = ok
                    ? "Feature gespeichert (\(features.count) gesamt)."
                    : "Speichern fehlgeschlagen."
                reloadTrigger += 1
            }
        }
        .sheet(isPresented: $showFeatureListSheet) {
            GeoFeatureListView(
                features: features,
                onDelete: { index in
                    guard features.indices.contains(index) else { return }
                    features.remove(at: index)
                    let ok = GeoJSONLoader.save(features: features, filename: "leitungen")
                    statusText = ok
                        ? "Feature gelöscht (\(features.count) verbleibend)."
                        : "Löschen lokal, aber Speichern fehlgeschlagen."
                    reloadTrigger += 1
                },
                onDeleteAll: {
                    features.removeAll()
                    let ok = GeoJSONLoader.save(features: features, filename: "leitungen")
                    statusText = ok
                        ? "Alle Features gelöscht."
                        : "Alle gelöscht, aber Speichern fehlgeschlagen."
                    reloadTrigger += 1
                }
            )
        }
    }

    private func loadFeatures() {
        features = GeoJSONLoader.load(filename: "leitungen")
        statusText = features.isEmpty
            ? "Keine GeoJSON-Features gefunden."
            : "\(features.count) Feature(s) geladen."
    }

    private func undoLastFeature() {
        guard !features.isEmpty else { return }
        _ = features.popLast()
        let ok = GeoJSONLoader.save(features: features, filename: "leitungen")
        statusText = ok
            ? "Letztes Feature entfernt (\(features.count) verbleibend)."
            : "Rückgängig lokal, aber Speichern fehlgeschlagen."
        reloadTrigger += 1
    }
}

private struct GeoFeatureListView: View {
    @Environment(\.dismiss) private var dismiss
    let features: [GeoFeature]
    let onDelete: (Int) -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if features.isEmpty {
                    Text("Keine Features vorhanden.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(features.enumerated()), id: \.element.id) { idx, feature in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title(for: feature))
                                    .font(.headline)
                                Text(subtitle(for: feature))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                onDelete(idx)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("Features löschen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !features.isEmpty {
                        Button("Alle löschen", role: .destructive) {
                            onDeleteAll()
                        }
                    }
                }
            }
        }
    }

    private func title(for feature: GeoFeature) -> String {
        switch feature.geometry.type {
        case "Point":
            return "Grube"
        case "LineString":
            return "Leitung"
        default:
            return "Feature"
        }
    }

    private func subtitle(for feature: GeoFeature) -> String {
        switch feature.geometry.type {
        case "Point":
            if let c = feature.geometry.pointCoordinates, c.count >= 2 {
                return String(format: "Lat %.6f, Lon %.6f", c[1], c[0])
            }
            return "Punkt ohne Koordinate"
        case "LineString":
            let count = feature.geometry.lineCoordinates?.count ?? 0
            return "Punkte: \(count)"
        default:
            return "Unbekannter Typ"
        }
    }
}

private struct GeoFeatureCaptureView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case grube = "Grube"
        case leitung = "Leitung"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationProvider = CaptureLocationProvider()

    @State private var mode: Mode = .grube
    @State private var depthText = "2.5"
    @State private var widthText = "2.0"
    @State private var lengthText = "3.0"
    @State private var linePoints: [[Double]] = []
    @State private var manualLatText = ""
    @State private var manualLonText = ""
    @State private var infoText = ""

    let onSave: (GeoFeature) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Typ") {
                    Picker("Feature", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .grube {
                    Section("Grube Maße (m)") {
                        TextField("Tiefe", text: $depthText).keyboardType(.decimalPad)
                        TextField("Breite", text: $widthText).keyboardType(.decimalPad)
                        TextField("Länge", text: $lengthText).keyboardType(.decimalPad)
                    }
                } else {
                    Section("Leitungs-Punkte") {
                        Text("Punkte: \(linePoints.count)")
                            .foregroundStyle(.secondary)
                        Button("Aktuellen GPS-Punkt hinzufügen") {
                            guard let c = locationProvider.currentCoordinate else {
                                infoText = "Kein GPS verfügbar."
                                return
                            }
                            linePoints.append([c.longitude, c.latitude])
                            infoText = "Punkt hinzugefügt."
                        }
                        .buttonStyle(.borderedProminent)

                        HStack {
                            TextField("Lat", text: $manualLatText).keyboardType(.decimalPad)
                            TextField("Lon", text: $manualLonText).keyboardType(.decimalPad)
                        }
                        Button("Manuellen Punkt hinzufügen") {
                            guard let lat = Double(manualLatText.replacingOccurrences(of: ",", with: ".")),
                                  let lon = Double(manualLonText.replacingOccurrences(of: ",", with: ".")),
                                  (-90...90).contains(lat),
                                  (-180...180).contains(lon) else {
                                infoText = "Ungültige Koordinaten."
                                return
                            }
                            linePoints.append([lon, lat])
                            manualLatText = ""
                            manualLonText = ""
                            infoText = "Manueller Punkt hinzugefügt."
                        }
                        .buttonStyle(.bordered)

                        Button("Letzten Punkt entfernen", role: .destructive) {
                            _ = linePoints.popLast()
                        }
                        .disabled(linePoints.isEmpty)
                    }
                }

                Section("Status") {
                    if let c = locationProvider.currentCoordinate {
                        Text("GPS: \(String(format: "%.6f", c.latitude)), \(String(format: "%.6f", c.longitude))")
                            .font(.footnote)
                    } else {
                        Text("GPS: noch kein Fix")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !infoText.isEmpty {
                        Text(infoText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Feature erfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard let feature = buildFeature() else {
                            infoText = "Bitte Eingaben prüfen."
                            return
                        }
                        onSave(feature)
                        dismiss()
                    }
                }
            }
        }
    }

    private func buildFeature() -> GeoFeature? {
        switch mode {
        case .grube:
            guard let c = locationProvider.currentCoordinate,
                  let depth = parseNumber(depthText),
                  let width = parseNumber(widthText),
                  let length = parseNumber(lengthText) else { return nil }
            return GeoFeature(point: c, depth: depth, width: width, length: length)
        case .leitung:
            guard linePoints.count >= 2 else { return nil }
            return GeoFeature(lineCoordinates: linePoints)
        }
    }

    private func parseNumber(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}

private final class CaptureLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentCoordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 20 else { return }
        currentCoordinate = loc.coordinate
    }
}

private struct ARLeitungenSceneRepresentable: UIViewRepresentable {
    struct CapturedPit {
        let coordinate: CLLocationCoordinate2D
        let width: Double
        let length: Double
        let depth: Double
    }

    let features: [GeoFeature]
    @Binding var statusText: String
    let calibrateTrigger: Int
    let reloadTrigger: Int
    let arPitCaptureTrigger: Int
    let arPitScanExecuteTrigger: Int
    let onCapturedPit: (CapturedPit) -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        context.coordinator.attach(sceneView: view)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.update(features: features, statusText: $statusText, onCapturedPit: onCapturedPit)
        context.coordinator.handle(
            calibrateTrigger: calibrateTrigger,
            reloadTrigger: reloadTrigger,
            arPitCaptureTrigger: arPitCaptureTrigger,
            arPitScanExecuteTrigger: arPitScanExecuteTrigger
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, CLLocationManagerDelegate {
        private let locationManager = CLLocationManager()
        private weak var sceneView: ARSCNView?
        private let contentRoot = SCNNode()
        private let maxRenderDistanceMeters: Float = 250
        private var referenceWorldOffset = SCNVector3Zero
        private var captureHandler: ((CapturedPit) -> Void)?
        private var objectReferencePoint: SCNVector3?
        private var lastMeasurementPoint: SCNVector3?

        private enum PitScanStep {
            case idle
            case waitingObjectReference
            case waitingLastMeasurementPoint
            case readyForScan
            case waitingPitTopA
            case waitingPitTopB(first: SCNVector3)
            case waitingPitBottom(first: SCNVector3, second: SCNVector3)
        }
        private var pitScanStep: PitScanStep = .idle

        private var features: [GeoFeature] = []
        private var statusText: Binding<String>?
        private var lastLocation: CLLocation?
        private var smoothedHeading: Double = 0
        private var hasHeading = false
        private var originLocation: CLLocation?
        private var lastRenderedAt: Date = .distantPast
        private var lastCalibrateTrigger: Int = 0
        private var lastReloadTrigger: Int = 0
        private var lastARPitCaptureTrigger: Int = 0
        private var lastARPitScanExecuteTrigger: Int = 0

        override init() {
            super.init()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.headingFilter = 2
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }

        func attach(sceneView: ARSCNView) {
            self.sceneView = sceneView
            sceneView.scene.rootNode.addChildNode(contentRoot)
            let config = ARWorldTrackingConfiguration()
            config.worldAlignment = .gravity
            config.planeDetection = [.horizontal]
            if ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth]) {
                config.frameSemantics.insert(.sceneDepth)
            }
            sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            sceneView.addGestureRecognizer(tap)
        }

        func update(features: [GeoFeature], statusText: Binding<String>, onCapturedPit: @escaping (CapturedPit) -> Void) {
            self.features = features
            self.statusText = statusText
            self.captureHandler = onCapturedPit
        }

        func handle(calibrateTrigger: Int, reloadTrigger: Int, arPitCaptureTrigger: Int, arPitScanExecuteTrigger: Int) {
            if calibrateTrigger != lastCalibrateTrigger {
                lastCalibrateTrigger = calibrateTrigger
                guard let current = lastLocation else {
                    setStatus("Referenz nicht gesetzt: Noch kein GPS-Fix.")
                    return
                }
                originLocation = current
                if let nearest = nearestFeaturePointToCamera() {
                    referenceWorldOffset = nearest
                    setStatus("Referenz auf nächstgelegenes Objekt gesetzt.")
                } else {
                    referenceWorldOffset = SCNVector3Zero
                    setStatus("Referenz gesetzt (kein Objekt gefunden, Ursprung verwendet).")
                }
                renderIfPossible(force: true)
            }
            if reloadTrigger != lastReloadTrigger {
                lastReloadTrigger = reloadTrigger
                renderIfPossible(force: true)
            }
            if arPitCaptureTrigger != lastARPitCaptureTrigger {
                lastARPitCaptureTrigger = arPitCaptureTrigger
                objectReferencePoint = nil
                lastMeasurementPoint = nil
                pitScanStep = .waitingObjectReference
                setStatus("AR-Erfassung: 1/2 Objektpunkt antippen.")
            }
            if arPitScanExecuteTrigger != lastARPitScanExecuteTrigger {
                lastARPitScanExecuteTrigger = arPitScanExecuteTrigger
                if case .readyForScan = pitScanStep {
                    pitScanStep = .waitingPitTopA
                    setStatus("Grubenscan: 1/3 obere Ecke antippen.")
                } else {
                    setStatus("Erst Objektpunkt + letzten Messpunkt setzen, dann Scan ausführen.")
                }
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            guard newHeading.headingAccuracy >= 0 else { return }
            let h = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
            if hasHeading {
                smoothedHeading = 0.85 * smoothedHeading + 0.15 * h
            } else {
                smoothedHeading = h
                hasHeading = true
            }
            renderIfPossible()
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let raw = locations.last else { return }
            guard raw.horizontalAccuracy > 0, raw.horizontalAccuracy <= 15 else {
                setStatus("Warte auf präzises GPS (\(Int(raw.horizontalAccuracy)) m).")
                return
            }
            lastLocation = raw
            if originLocation == nil { originLocation = raw }
            renderIfPossible()
        }

        func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
            true
        }

        @objc
        private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = sceneView else { return }
            let point = gesture.location(in: view)
            guard let world = worldPoint(from: point, in: view) else { return }

            switch pitScanStep {
            case .idle:
                return
            case .waitingObjectReference:
                objectReferencePoint = world
                pitScanStep = .waitingLastMeasurementPoint
                setStatus("AR-Erfassung: 2/2 letzten Messpunkt zur Grube antippen.")
                renderIfPossible(force: true)
            case .waitingLastMeasurementPoint:
                lastMeasurementPoint = world
                pitScanStep = .readyForScan
                setStatus("Messung gesetzt. Jetzt 'Scan jetzt ausführen' drücken.")
                renderIfPossible(force: true)
            case .readyForScan:
                return
            case .waitingPitTopA:
                pitScanStep = .waitingPitTopB(first: world)
                setStatus("Grubenscan: 2/3 zweite obere Ecke antippen.")
            case .waitingPitTopB(let first):
                pitScanStep = .waitingPitBottom(first: first, second: world)
                setStatus("Grubenscan: 3/3 unteren Punkt antippen (Tiefe).")
            case .waitingPitBottom(let first, let second):
                let width = hypot(Double(second.x - first.x), Double(second.z - first.z))
                let length = width
                let depth = abs(Double(first.y - world.y))
                if let c = lastLocation?.coordinate {
                    captureHandler?(CapturedPit(
                        coordinate: c,
                        width: max(width, 0.2),
                        length: max(length, 0.2),
                        depth: max(depth, 0.2)
                    ))
                    setStatus(String(format: "AR-Grube erfasst: B %.2f m, L %.2f m, T %.2f m", width, length, depth))
                } else {
                    setStatus("AR-Grube erfasst, aber GPS fehlt für Speicherung.")
                }
                pitScanStep = .idle
                objectReferencePoint = nil
                lastMeasurementPoint = nil
                renderIfPossible(force: true)
            }
        }

        private func worldPoint(from point: CGPoint, in view: ARSCNView) -> SCNVector3? {
            for target in [ARRaycastQuery.Target.existingPlaneGeometry, .estimatedPlane, .existingPlaneInfinite] {
                guard let query = view.raycastQuery(from: point, allowing: target, alignment: .any) else { continue }
                if let first = view.session.raycast(query).first {
                    let t = first.worldTransform
                    return SCNVector3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                }
            }
            return nil
        }

        private func renderIfPossible(force: Bool = false) {
            guard let user = lastLocation?.coordinate, let origin = originLocation?.coordinate else { return }
            guard hasHeading else {
                setStatus("Warte auf Kompass/Heading…")
                return
            }
            if !force, Date().timeIntervalSince(lastRenderedAt) < 0.35 { return }
            lastRenderedAt = Date()

            contentRoot.childNodes.forEach { $0.removeFromParentNode() }
            contentRoot.addChildNode(makeOriginMarkerNode())
            addCaptureHelperNodes()

            var renderedPoints = 0
            var renderedLineSegments = 0
            var skippedFar = 0

            for feature in features {
                switch feature.geometry.type {
                case "Point":
                    guard let c = feature.geometry.pointCoordinates?.asCoordinate else { continue }
                    let node = GeoARManager.createGrube(feature: feature)
                    node.position = GeoARManager.positionFromGPS(
                        target: c,
                        user: user,
                        origin: origin,
                        headingDegrees: smoothedHeading
                    )
                    if node.position.distanceFromOrigin > maxRenderDistanceMeters {
                        skippedFar += 1
                        continue
                    }
                    node.position += referenceWorldOffset
                    contentRoot.addChildNode(node)
                    renderedPoints += 1
                case "LineString":
                    guard let points = feature.geometry.lineCoordinates, points.count >= 2 else { continue }
                    for idx in 0..<(points.count - 1) {
                        guard let c1 = points[idx].asCoordinate, let c2 = points[idx + 1].asCoordinate else { continue }
                        let p1 = GeoARManager.positionFromGPS(
                            target: c1,
                            user: user,
                            origin: origin,
                            headingDegrees: smoothedHeading
                        )
                        let p2 = GeoARManager.positionFromGPS(
                            target: c2,
                            user: user,
                            origin: origin,
                            headingDegrees: smoothedHeading
                        )
                        if p1.distanceFromOrigin > maxRenderDistanceMeters && p2.distanceFromOrigin > maxRenderDistanceMeters {
                            skippedFar += 1
                            continue
                        }
                        let lineNode = GeoARManager.createLeitung(start: p1, end: p2)
                        lineNode.position += referenceWorldOffset
                        contentRoot.addChildNode(lineNode)
                        renderedLineSegments += 1
                    }
                default:
                    continue
                }
            }

            if renderedPoints == 0 && renderedLineSegments == 0 {
                setStatus("Keine sichtbaren Objekte. Features: \(features.count), außerhalb \(Int(maxRenderDistanceMeters))m: \(skippedFar).")
            } else {
                setStatus("Sichtbar: \(renderedPoints) Gruben, \(renderedLineSegments) Leitungssegmente | Heading \(Int(smoothedHeading))°")
            }
        }

        private func setStatus(_ text: String) {
            DispatchQueue.main.async { [weak self] in
                self?.statusText?.wrappedValue = text
            }
        }

        private func makeOriginMarkerNode() -> SCNNode {
            let sphere = SCNSphere(radius: 0.08)
            sphere.firstMaterial?.diffuse.contents = UIColor.systemRed
            let node = SCNNode(geometry: sphere)
            node.position = referenceWorldOffset
            return node
        }

        private func addCaptureHelperNodes() {
            if let obj = objectReferencePoint {
                let n = markerNode(color: .systemGreen, radius: 0.05)
                n.position = obj
                contentRoot.addChildNode(n)
            }
            if let last = lastMeasurementPoint {
                let n = markerNode(color: .systemYellow, radius: 0.05)
                n.position = last
                contentRoot.addChildNode(n)
            }
            if let obj = objectReferencePoint, let last = lastMeasurementPoint {
                let line = GeoARManager.createLeitung(start: obj, end: last)
                line.geometry?.firstMaterial?.diffuse.contents = UIColor.systemTeal
                contentRoot.addChildNode(line)
            }
        }

        private func markerNode(color: UIColor, radius: CGFloat) -> SCNNode {
            let sphere = SCNSphere(radius: radius)
            sphere.firstMaterial?.diffuse.contents = color
            return SCNNode(geometry: sphere)
        }

        private func nearestFeaturePointToCamera() -> SCNVector3? {
            guard let view = sceneView,
                  let frame = view.session.currentFrame,
                  let points = frame.rawFeaturePoints?.points,
                  points.count > 0 else { return nil }
            let camera = frame.camera.transform.columns.3
            var best: simd_float3?
            var bestDistance = Float.greatestFiniteMagnitude
            for p in points {
                let d = simd_distance(simd_float3(camera.x, camera.y, camera.z), p)
                if d < bestDistance {
                    bestDistance = d
                    best = p
                }
            }
            guard let b = best else { return nil }
            return SCNVector3(b.x, b.y, b.z)
        }
    }
}

#Preview {
    NavigationStack { ARLeitungenGeoView() }
}

private extension SCNVector3 {
    var distanceFromOrigin: Float {
        sqrtf((x * x) + (y * y) + (z * z))
    }

    static func += (lhs: inout SCNVector3, rhs: SCNVector3) {
        lhs = SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }
}
