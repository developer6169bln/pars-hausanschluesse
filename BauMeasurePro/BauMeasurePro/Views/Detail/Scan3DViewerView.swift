import SwiftUI
import SceneKit
import UIKit
import CoreGraphics

/// 3D-Viewer für gespeicherte Scans. Unterstützte Formate:
/// - **.ply** = Punktwolke (RGB) aus dem LiDAR-Punktwolken-Scan (ScanAce-ähnlich)
/// - **.scn** = Mesh aus dem klassischen Mesh-Scan
/// Erkennt PLY auch am Dateiinhalt (Magic "ply"), falls die Endung fehlt.
/// Ergebnis des asynchronen Ladens – nur Daten/URL, keine SceneKit-Objekte.
private enum SceneLoadResult {
    case placeholder
    case scnFile(url: URL)
    case ply(vertices: [SCNVector3], colors: [UInt8])
}

private let cameraNodeName = "mainCamera"

/// Darstellungsart der Punktwolke im 3D-Viewer (nur bei .ply relevant).
enum PointCloudDisplayStyle: String, CaseIterable {
    case standard = "Standard"
    case fineCloud = "Feine Wolke"
}

/// Szenen-Hintergrundfarbe, damit man sieht, dass der Viewer aktiv ist.
private func setSceneBackground(_ scene: SCNScene) {
    scene.background.contents = UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1)
}

/// Verschiebt das gescannte Objekt so, dass sein Schwerpunkt im Ursprung liegt.
/// Dadurch liegt die Orbit-Achse (Kamera-Rotation) im Zentrum des Modells.
private func recenterModelInScene(_ scene: SCNScene) {
    guard let root = scene.rootNode.childNode(withName: "modelRoot", recursively: true) ?? scene.rootNode.childNodes.first else {
        return
    }
    let (minB, maxB) = root.boundingBox
    // Prüfen, ob eine gültige Bounding-Box vorhanden ist
    if minB.x == maxB.x && minB.y == maxB.y && minB.z == maxB.z {
        return
    }
    let center = SCNVector3(
        (minB.x + maxB.x) * 0.5,
        (minB.y + maxB.y) * 0.5,
        (minB.z + maxB.z) * 0.5
    )
    // Verschiebe das Modell so, dass sein Mittelpunkt im Ursprung (0,0,0) liegt.
    root.position.x -= center.x
    root.position.y -= center.y
    root.position.z -= center.z
}

/// Fügt im Ursprung ein kleines Orbit-Achsensystem (XYZ) hinzu,
/// damit der Nutzer die Rotationsachse des Modells erkennt.
private func addAxisGizmo(to scene: SCNScene) {
    let axisRoot = SCNNode()
    axisRoot.name = "axisGizmo"

    let radius: CGFloat = 0.004
    let length: CGFloat = 0.18

    // X-Achse (rot)
    let xGeom = SCNCylinder(radius: radius, height: length)
    xGeom.firstMaterial?.diffuse.contents = UIColor.systemRed
    let xNode = SCNNode(geometry: xGeom)
    xNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
    xNode.position = SCNVector3(Float(length / 2), 0, 0)
    axisRoot.addChildNode(xNode)

    // Y-Achse (grün)
    let yGeom = SCNCylinder(radius: radius, height: length)
    yGeom.firstMaterial?.diffuse.contents = UIColor.systemGreen
    let yNode = SCNNode(geometry: yGeom)
    yNode.position = SCNVector3(0, Float(length / 2), 0)
    axisRoot.addChildNode(yNode)

    // Z-Achse (blau)
    let zGeom = SCNCylinder(radius: radius, height: length)
    zGeom.firstMaterial?.diffuse.contents = UIColor.systemBlue
    let zNode = SCNNode(geometry: zGeom)
    zNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
    zNode.position = SCNVector3(0, 0, Float(length / 2))
    axisRoot.addChildNode(zNode)

    scene.rootNode.addChildNode(axisRoot)
}

/// Platzhalter-Szene: gut sichtbarer orangener Würfel + Kamera.
private func makePlaceholderScene() -> SCNScene {
    let scene = SCNScene()
    setSceneBackground(scene)
    let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
    box.firstMaterial?.diffuse.contents = UIColor.orange
    box.firstMaterial?.emission.contents = UIColor.orange
    let node = SCNNode(geometry: box)
    node.position = SCNVector3(0, 0, 0)
    scene.rootNode.addChildNode(node)
    addDefaultCamera(to: scene)
    return scene
}

/// Kamera hinzufügen, die auf den Ursprung blickt. Immer als direktes Kind von rootNode (nie im modelRoot).
private func addDefaultCamera(to scene: SCNScene) {
    let cam = SCNNode()
    cam.name = cameraNodeName
    let scnCam = SCNCamera()
    scnCam.zNear = 0.01
    scnCam.zFar = 1000
    cam.camera = scnCam
    cam.position = SCNVector3(0, 0, 5)
    cam.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    scene.rootNode.addChildNode(cam)
}

/// UIKit-SCNView mit eigener Orbit-Steuerung (stabile, langsame Kamera um Objektzentrum).
struct SceneKitContainerView: UIViewRepresentable {
    let scene: SCNScene

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: SCNView?
        var yaw: Float = 0
        var pitch: Float = 0.25
        var distance: Float = 2.0
        var target: SCNVector3 = SCNVector3(0, 0, 0)
        private var lastPan: CGPoint = .zero
        private var lastPanTwo: CGPoint = .zero
        var didInitCamera = false

        private func cameraNode(in scene: SCNScene) -> SCNNode {
            if let existing = scene.rootNode.childNode(withName: cameraNodeName, recursively: true) {
                return existing
            }
            addDefaultCamera(to: scene)
            return scene.rootNode.childNode(withName: cameraNodeName, recursively: true)!
        }

        /// Initiale Kameraposition anhand Bounding-Box des Modells bestimmen (nur einmal pro Szene).
        func configureInitialCameraIfNeeded(for scene: SCNScene) {
            guard !didInitCamera else {
                applyCamera()
                return
            }
            didInitCamera = true

            // Bounding-Box des modelltragenden Knotens (modelRoot oder erster Child).
            let root = scene.rootNode.childNode(withName: "modelRoot", recursively: true) ?? scene.rootNode.childNodes.first
            if let r = root {
                let (minB, maxB) = r.boundingBox
                if !(minB.x == maxB.x && minB.y == maxB.y && minB.z == maxB.z) {
                    let sizeX = maxB.x - minB.x
                    let sizeY = maxB.y - minB.y
                    let sizeZ = maxB.z - minB.z
                    let size = max(sizeX, max(sizeY, sizeZ))
                    if size.isFinite, size > 0 {
                        // Start-Zoom: etwas Abstand, damit das ganze Objekt sichtbar ist.
                        distance = max(size * 3.0, 0.5)
                    }
                }
            }
            // Startwinkel leicht schräg von vorne.
            yaw = 0
            pitch = 0.3
            applyCamera()
        }

        /// Kamera anhand yaw/pitch/distance/target setzen.
        func applyCamera() {
            guard let view, let scene = view.scene else { return }
            let cam = cameraNode(in: scene)

            let minPitch: Float = -Float.pi * 0.49
            let maxPitch: Float =  Float.pi * 0.49
            pitch = max(minPitch, min(maxPitch, pitch))
            distance = max(0.2, min(distance, 500))

            let x = target.x + distance * cosf(pitch) * sinf(yaw)
            let y = target.y + distance * sinf(pitch)
            let z = target.z + distance * cosf(pitch) * cosf(yaw)
            cam.position = SCNVector3(x, y, z)
            cam.look(at: target, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            view.pointOfView = cam
        }

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard let view else { return }
            let p = gr.translation(in: view)
            if gr.state == .began { lastPan = p }
            let dx = Float(p.x - lastPan.x)
            let dy = Float(p.y - lastPan.y)
            lastPan = p

            // Langsame Rotation um Objektzentrum.
            yaw   += dx * 0.005
            pitch -= dy * 0.005
            applyCamera()
        }

        @objc func handleTwoFingerPan(_ gr: UIPanGestureRecognizer) {
            guard let view else { return }
            let p = gr.translation(in: view)
            if gr.state == .began { lastPanTwo = p }
            let dx = Float(p.x - lastPanTwo.x)
            let dy = Float(p.y - lastPanTwo.y)
            lastPanTwo = p

            // Verschieben in Bildschirmebene, Stärke abhängig von Distanz.
            let k = distance * 0.001
            target.x += -dx * k
            target.y +=  dy * k
            applyCamera()
        }

        @objc func handlePinch(_ gr: UIPinchGestureRecognizer) {
            guard gr.state == .changed || gr.state == .ended else { return }
            let s = Float(gr.scale)
            if s.isFinite, s > 0.01 {
                // Sanftes Zoom
                distance /= max(0.5, min(s, 2.0))
            }
            gr.scale = 1.0
            applyCamera()
        }

        @objc func handleDoubleTap(_ gr: UITapGestureRecognizer) {
            // Zur Standardansicht zurück (Winkel, Ziel bleibt Mittelpunkt).
            yaw = 0
            pitch = 0.3
            applyCamera()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1)
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.scene = scene

        // Sofort pointOfView setzen, damit das erste Bild nicht leer ist.
        if let cam = scene.rootNode.childNode(withName: cameraNodeName, recursively: true) {
            view.pointOfView = cam
        }

        context.coordinator.view = view

        // 1 Finger: Orbit
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        // 2 Finger: Verschieben
        let panTwo = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerPan(_:)))
        panTwo.minimumNumberOfTouches = 2
        panTwo.maximumNumberOfTouches = 2
        panTwo.delegate = context.coordinator
        view.addGestureRecognizer(panTwo)

        // Pinch: Zoom
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        // Doppeltipp: Reset
        let dbl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        dbl.delegate = context.coordinator
        view.addGestureRecognizer(dbl)

        // Orbit-Kamera auf Objektgröße anpassen (einmalig pro Szene).
        context.coordinator.configureInitialCameraIfNeeded(for: scene)

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = scene
        context.coordinator.view = uiView
        if let cam = scene.rootNode.childNode(withName: cameraNodeName, recursively: true) {
            uiView.pointOfView = cam
        }
        context.coordinator.didInitCamera = false
        context.coordinator.configureInitialCameraIfNeeded(for: scene)
    }
}

struct Scan3DViewerView: View {
    private enum ViewerTab: String, CaseIterable {
        case model = "Modell"
        case walkthrough = "Walkthrough"
    }

    private enum PlaybackMode: String, CaseIterable {
        case once = "Einmal"
        case loop = "Loop"
        case pingPong = "Ping-Pong"
    }

    let scan: ThreeDScan
    private let storage = StorageService()
    @State private var scene: SCNScene = makePlaceholderScene()
    @AppStorage("pointCloudDisplayStyle") private var displayStyle: String = PointCloudDisplayStyle.standard.rawValue
    @AppStorage("pointCloudPointSize") private var pointCloudPointSize: Double = 1.0
    @State private var volumeM3: Double?
    @State private var showVolumeError = false
    @State private var volumeErrorMessage: String?
    @State private var selectedTab: ViewerTab = .model
    @State private var currentKeyframeIndex = 0
    @State private var showKeyframeImage = true
    @State private var autoPlayEnabled = false
    @State private var playbackInterval: Double = 0.7
    @State private var playbackProgress: Double = 0
    @State private var playbackMode: PlaybackMode = .once
    @State private var pingPongDirection: Double = 1.0
    @State private var walkthroughFullscreen = false

    private var currentStyle: PointCloudDisplayStyle {
        PointCloudDisplayStyle(rawValue: displayStyle) ?? .standard
    }

    private var isPointCloudScan: Bool {
        scan.filePath.lowercased().hasSuffix(".ply")
    }

    private var hasWalkthrough: Bool {
        !scan.keyframes.isEmpty
    }

    private var currentKeyframe: ScanKeyframe? {
        guard hasWalkthrough else { return nil }
        let idx = min(max(0, displayedKeyframeIndex), scan.keyframes.count - 1)
        return scan.keyframes[idx]
    }

    private var displayedKeyframeIndex: Int {
        guard hasWalkthrough else { return 0 }
        let maxIdx = scan.keyframes.count - 1
        return min(max(0, Int(round(playbackProgress))), maxIdx)
    }

    private var interpolatedTrajectoryPoint: CGPoint? {
        guard !trajectoryPoints.isEmpty else { return nil }
        if trajectoryPoints.count == 1 { return trajectoryPoints[0] }
        let maxIdx = trajectoryPoints.count - 1
        let clamped = min(max(0, playbackProgress), Double(maxIdx))
        let fromIdx = Int(floor(clamped))
        let toIdx = min(fromIdx + 1, maxIdx)
        let t = clamped - Double(fromIdx)
        let a = trajectoryPoints[fromIdx]
        let b = trajectoryPoints[toIdx]
        return CGPoint(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t
        )
    }

    private var blendSegment: (from: Int, to: Int, alpha: Double)? {
        guard scan.keyframes.count > 1 else { return nil }
        let maxIdx = scan.keyframes.count - 1
        let clamped = min(max(0, playbackProgress), Double(maxIdx))
        let from = Int(floor(clamped))
        let to = min(from + 1, maxIdx)
        let alpha = clamped - Double(from)
        return (from: from, to: to, alpha: alpha)
    }

    private var trajectoryPoints: [CGPoint] {
        let points = scan.keyframes.compactMap { keyframe -> CGPoint? in
            guard let x = keyframe.positionX, let z = keyframe.positionZ else { return nil }
            return CGPoint(x: x, y: z)
        }
        guard !points.isEmpty else { return [] }
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 1
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 1
        let width = max(maxX - minX, 0.001)
        let height = max(maxY - minY, 0.001)
        return points.map { p in
            CGPoint(x: (p.x - minX) / width, y: (p.y - minY) / height)
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.15, green: 0.15, blue: 0.2)
                .ignoresSafeArea()

            if selectedTab == .model {
                SceneKitContainerView(scene: scene)
            } else {
                walkthroughView
            }
        }
        .overlay(alignment: .top) {
            if !(selectedTab == .walkthrough && walkthroughFullscreen) {
                Picker("Ansicht", selection: $selectedTab) {
                    ForEach(ViewerTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
        }
        .overlay(alignment: .bottom) {
            if selectedTab == .model, let v = volumeM3 {
                Text(String(format: "Volumen: %.2f m³", v))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 16)
            } else if selectedTab == .model, isPointCloudScan {
                HStack(spacing: 10) {
                    Text("Punktgröße")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))
                    Slider(value: $pointCloudPointSize, in: 0.5...4.0, step: 0.1)
                    Text(String(format: "%.1f", pointCloudPointSize))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(minWidth: 200, minHeight: 200)
        .navigationTitle(scan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selectedTab == .model, isPointCloudScan {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Darstellung", selection: $displayStyle) {
                        ForEach(PointCloudDisplayStyle.allCases, id: \.rawValue) { style in
                            Text(style.rawValue).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } else if selectedTab == .model {
                ToolbarItem(placement: .primaryAction) {
                    Button("Volumen") {
                        do {
                            let v = try MeshVolumeCalculator.volumeM3(of: scene)
                            volumeM3 = v
                        } catch {
                            volumeErrorMessage = error.localizedDescription
                            showVolumeError = true
                        }
                    }
                }
            }
        }
        .task(id: "\(scan.id)-\(displayStyle)-\(String(format: "%.1f", pointCloudPointSize))") {
            await Task.yield()
            await loadAndApplyScene()
        }
        .onAppear {
            currentKeyframeIndex = 0
            playbackProgress = 0
        }
        .onDisappear {
            autoPlayEnabled = false
            walkthroughFullscreen = false
        }
        .task(id: autoPlayTaskKey) {
            guard autoPlayEnabled, scan.keyframes.count > 1 else { return }
            let fps: Double = 30
            let stepSeconds = 1.0 / fps
            let segmentDuration = max(0.15, playbackInterval)
            let stepPerTick = stepSeconds / segmentDuration
            while autoPlayEnabled {
                try? await Task.sleep(nanoseconds: UInt64(stepSeconds * 1_000_000_000))
                guard autoPlayEnabled else { break }
                await MainActor.run {
                    let endProgress = Double(max(0, scan.keyframes.count - 1))
                    switch playbackMode {
                    case .once:
                        if playbackProgress >= endProgress {
                            autoPlayEnabled = false
                        } else {
                            playbackProgress = min(endProgress, playbackProgress + stepPerTick)
                        }
                    case .loop:
                        if endProgress > 0 {
                            let next = playbackProgress + stepPerTick
                            playbackProgress = next > endProgress ? 0 : next
                        }
                    case .pingPong:
                        if endProgress <= 0 {
                            autoPlayEnabled = false
                        } else {
                            let next = playbackProgress + (stepPerTick * pingPongDirection)
                            if next >= endProgress {
                                playbackProgress = endProgress
                                pingPongDirection = -1
                            } else if next <= 0 {
                                playbackProgress = 0
                                pingPongDirection = 1
                            } else {
                                playbackProgress = next
                            }
                        }
                    }
                    currentKeyframeIndex = displayedKeyframeIndex
                }
            }
        }
        .alert("Volumenberechnung", isPresented: $showVolumeError) {
            Button("OK", role: .cancel) { showVolumeError = false }
        } message: {
            Text(volumeErrorMessage ?? "Volumen konnte nicht berechnet werden.")
        }
    }

    private var autoPlayTaskKey: String {
        "\(scan.id.uuidString)-\(autoPlayEnabled)-\(String(format: "%.2f", playbackInterval))"
    }

    private func keyframeImage(at index: Int) -> UIImage? {
        guard scan.keyframes.indices.contains(index) else { return nil }
        let path = storage.fullPath(forStoredPath: scan.keyframes[index].imagePath)
        return UIImage(contentsOfFile: path)
    }

    private var walkthroughView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: walkthroughFullscreen ? 8 : 40)
            if let keyframe = currentKeyframe {
                if showKeyframeImage {
                    if let blend = blendSegment,
                       let fromImage = keyframeImage(at: blend.from) {
                        ZStack {
                            Image(uiImage: fromImage)
                                .resizable()
                                .scaledToFit()
                                .opacity(1.0 - blend.alpha)
                            if let toImage = keyframeImage(at: blend.to) {
                                Image(uiImage: toImage)
                                    .resizable()
                                    .scaledToFit()
                                    .opacity(blend.alpha)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: walkthroughFullscreen ? .infinity : 420)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                    } else {
                        let fullPath = storage.fullPath(forStoredPath: keyframe.imagePath)
                        if let image = UIImage(contentsOfFile: fullPath) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: walkthroughFullscreen ? .infinity : 420)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)
                        } else {
                            Text("Keyframe-Bild nicht gefunden")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Frame \(displayedKeyframeIndex + 1) / \(scan.keyframes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(keyframe.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !trajectoryPoints.isEmpty && !walkthroughFullscreen {
                    trajectoryView
                }
            } else {
                Text("Keine Walkthrough-Keyframes verfügbar. Bitte neuen 3D-Scan starten, dann wird Walkthrough automatisch aufgezeichnet.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            Spacer(minLength: walkthroughFullscreen ? 8 : 0)
            if walkthroughFullscreen {
                HStack {
                    Spacer()
                    Button("Vollbild beenden") {
                        walkthroughFullscreen = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.7))
                    .padding(.trailing, 16)
                }
            }
            if !walkthroughFullscreen {
            HStack(spacing: 10) {
                Button("Zurück") {
                    currentKeyframeIndex = max(0, currentKeyframeIndex - 1)
                    playbackProgress = Double(currentKeyframeIndex)
                    autoPlayEnabled = false
                }
                .buttonStyle(.bordered)
                .disabled(currentKeyframeIndex <= 0)

                Button(showKeyframeImage ? "Bild aus" : "Bild an") {
                    showKeyframeImage.toggle()
                }
                .buttonStyle(.bordered)

                Button("Vollbild") {
                    walkthroughFullscreen = true
                }
                .buttonStyle(.bordered)

                Button(autoPlayEnabled ? "Stop" : "Auto") {
                    if autoPlayEnabled {
                        autoPlayEnabled = false
                    } else {
                        if currentKeyframeIndex >= max(0, scan.keyframes.count - 1) {
                            currentKeyframeIndex = 0
                            playbackProgress = 0
                        }
                        pingPongDirection = 1
                        autoPlayEnabled = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(autoPlayEnabled ? .red : .blue)
                .disabled(scan.keyframes.count < 2)

                Button("Weiter") {
                    currentKeyframeIndex = min(max(0, scan.keyframes.count - 1), currentKeyframeIndex + 1)
                    playbackProgress = Double(currentKeyframeIndex)
                    autoPlayEnabled = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentKeyframeIndex >= max(0, scan.keyframes.count - 1))
            }
            if hasWalkthrough {
                HStack(spacing: 10) {
                    Text("Tempo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $playbackInterval, in: 0.2...1.8, step: 0.1)
                    Text(String(format: "%.1fs", playbackInterval))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)

                Picker("Modus", selection: $playbackMode) {
                    ForEach(PlaybackMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
            }
            Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 20)
    }

    private var trajectoryView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.18))
            Canvas { context, size in
                guard trajectoryPoints.count > 1 else { return }
                var path = Path()
                for (idx, p) in trajectoryPoints.enumerated() {
                    let pt = CGPoint(x: p.x * size.width, y: (1.0 - p.y) * size.height)
                    if idx == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                context.stroke(path, with: .color(.cyan), lineWidth: 2)

                if let current = interpolatedTrajectoryPoint ?? trajectoryPoints.last {
                    let marker = CGRect(
                        x: current.x * size.width - 4,
                        y: (1.0 - current.y) * size.height - 4,
                        width: 8,
                        height: 8
                    )
                    context.fill(Path(ellipseIn: marker), with: .color(.yellow))
                }
            }
            .padding(8)
        }
        .frame(height: 120)
        .padding(.horizontal, 16)
    }

    /// Lädt im Hintergrund, wendet Ergebnis auf dem Hauptthread an.
    private func loadAndApplyScene() async {
        let path = scan.filePath
        let fullPath = storage.fullPath(forStoredPath: path)
        let style = currentStyle
        let result = await Task.detached(priority: .userInitiated) {
            loadSceneData(path: path, fullPath: fullPath, displayStyle: style)
        }.value
        let newScene: SCNScene = await MainActor.run {
            buildSceneOnMain(result: result, displayStyle: style)
        }
        await MainActor.run {
            scene = newScene
            volumeM3 = nil
        }
    }

    private enum VolumeError: LocalizedError {
        case noMesh
        case unsupportedGeometry
        case invalidMesh

        var errorDescription: String? {
            switch self {
            case .noMesh:
                return "Kein Mesh gefunden. Volumen funktioniert nur für geschlossene Mesh-Scans (.scn)."
            case .unsupportedGeometry:
                return "Mesh-Geometrie wird nicht unterstützt (nur Dreiecke)."
            case .invalidMesh:
                return "Mesh ist nicht geschlossen oder enthält ungültige Daten – Volumen kann nicht zuverlässig berechnet werden."
            }
        }
    }

    private enum MeshVolumeCalculator {
        /// Berechnet das Volumen eines geschlossenen Dreiecks-Meshes in \(m^3\).
        /// Hinweis: funktioniert zuverlässig nur bei „watertight“ Mesh (Baugrube idealerweise oben+Wände+Boden scannen).
        static func volumeM3(of scene: SCNScene) throws -> Double {
            var foundAnyTriangles = false
            var sum: Double = 0

            scene.rootNode.enumerateChildNodes { node, _ in
                // Hilfsknoten ignorieren
                if node.name == cameraNodeName || node.name == "axisGizmo" { return }
                guard let geom = node.geometry else { return }
                guard let vertexSource = geom.sources.first(where: { $0.semantic == .vertex }) else { return }

                // Vertices lesen
                let vCount = vertexSource.vectorCount
                guard vCount > 0 else { return }
                var vertices = [SIMD3<Float>](repeating: .zero, count: vCount)
                vertexSource.data.withUnsafeBytes { raw in
                    let base = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    for i in 0..<vCount {
                        let ptr = base.advanced(by: vertexSource.dataOffset + i * vertexSource.dataStride)
                        let fptr = UnsafeRawPointer(ptr).assumingMemoryBound(to: Float.self)
                        vertices[i] = SIMD3<Float>(fptr[0], fptr[1], fptr[2])
                    }
                }

                let world = node.simdWorldTransform
                func toWorld(_ p: SIMD3<Float>) -> SIMD3<Float> {
                    let v4 = SIMD4<Float>(p.x, p.y, p.z, 1)
                    let w4 = world * v4
                    return SIMD3<Float>(w4.x, w4.y, w4.z)
                }

                for element in geom.elements {
                    guard element.primitiveType == .triangles else { continue }
                    foundAnyTriangles = true
                    let triCount = element.primitiveCount
                    let indexCount = triCount * 3
                    guard indexCount > 0 else { continue }

                    func readIndex(_ ptr: UnsafeRawPointer, bytesPerIndex: Int) -> Int {
                        switch bytesPerIndex {
                        case 2: return Int(ptr.assumingMemoryBound(to: UInt16.self).pointee)
                        default: return Int(ptr.assumingMemoryBound(to: UInt32.self).pointee)
                        }
                    }

                    element.data.withUnsafeBytes { raw in
                        let base = raw.baseAddress!
                        let bpi = element.bytesPerIndex
                        for i in stride(from: 0, to: indexCount, by: 3) {
                            let i0 = readIndex(base.advanced(by: (i + 0) * bpi), bytesPerIndex: bpi)
                            let i1 = readIndex(base.advanced(by: (i + 1) * bpi), bytesPerIndex: bpi)
                            let i2 = readIndex(base.advanced(by: (i + 2) * bpi), bytesPerIndex: bpi)
                            if i0 < 0 || i1 < 0 || i2 < 0 || i0 >= vCount || i1 >= vCount || i2 >= vCount { continue }

                            let p0 = toWorld(vertices[i0])
                            let p1 = toWorld(vertices[i1])
                            let p2 = toWorld(vertices[i2])

                            // Signed tetrahedron volume contribution: dot(p0, cross(p1, p2)) / 6
                            let c = simd_cross(p1, p2)
                            let v = Double(simd_dot(p0, c)) / 6.0
                            sum += v
                        }
                    }
                }
            }

            guard foundAnyTriangles else { throw VolumeError.noMesh }
            let volume = abs(sum)
            if !volume.isFinite || volume <= 0 {
                throw VolumeError.invalidMesh
            }
            return volume
        }
    }

    /// Lädt Szenendaten. Unterstützt: .ply = Punktwolke (RGB aus LiDAR-Scan), .scn = Mesh. Keine SceneKit-Objekte hier erzeugen. (nonisolated für Aufruf aus Task.detached.)
    private nonisolated func loadSceneData(path: String, fullPath: String, displayStyle: PointCloudDisplayStyle) -> SceneLoadResult {
        guard !path.isEmpty else { return .placeholder }
        guard FileManager.default.fileExists(atPath: fullPath) else { return .placeholder }
        let isPlyByExtension = path.lowercased().hasSuffix(".ply")
        var isPlyByContent = false
        if let stream = InputStream(url: URL(fileURLWithPath: fullPath)) {
            stream.open()
            defer { stream.close() }
            var buf = [UInt8](repeating: 0, count: 5)
            if stream.read(&buf, maxLength: 3) == 3 {
                isPlyByContent = (buf[0] == 0x70 && buf[1] == 0x6C && buf[2] == 0x79)
            }
        }
        if isPlyByExtension || isPlyByContent {
            if let (vertices, colors) = parsePLYToArrays(path: fullPath, displayStyle: displayStyle) {
                return .ply(vertices: vertices, colors: colors)
            }
            return .placeholder
        }
        return .scnFile(url: URL(fileURLWithPath: fullPath))
    }

    /// Auf dem Hauptthread: aus geladenen Daten die SCNScene bauen (SceneKit ist nicht thread-sicher). Muss auf MainActor laufen.
    private func buildSceneOnMain(result: SceneLoadResult, displayStyle: PointCloudDisplayStyle) -> SCNScene {
        switch result {
        case .placeholder:
            return makePlaceholderScene()
        case .scnFile(let url):
            do {
                let s = try SCNScene(url: url, options: nil)
                setSceneBackground(s)
                recenterModelInScene(s)
                addAxisGizmo(to: s)
                if s.rootNode.childNode(withName: cameraNodeName, recursively: true) == nil {
                    addDefaultCamera(to: s)
                }
                return s
            } catch {
                return makePlaceholderScene()
            }
        case .ply(let vertices, let colors):
            return buildPointCloudScene(vertices: vertices, colors: colors, displayStyle: displayStyle)
        }
    }

    /// PLY nur parsen → Arrays (im Hintergrund erlaubt). Keine SCN-Objekte. (nonisolated für Aufruf aus loadSceneData.)
    private nonisolated func parsePLYToArrays(path: String, displayStyle: PointCloudDisplayStyle) -> (vertices: [SCNVector3], colors: [UInt8])? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: .newlines)
        var vertexCount = 0
        var headerEndIndex = 0
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("element vertex ") {
                vertexCount = Int(t.replacingOccurrences(of: "element vertex ", with: "")) ?? 0
            }
            if t == "end_header" {
                headerEndIndex = i + 1
                break
            }
        }
        guard vertexCount > 0, headerEndIndex < lines.count else { return nil }
        var vertices: [SCNVector3] = []
        var colors: [UInt8] = []
        for i in headerEndIndex..<min(headerEndIndex + vertexCount, lines.count) {
            let parts = lines[i].split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 6,
                  let x = Float(parts[0]), let y = Float(parts[1]), let z = Float(parts[2]),
                  let r = UInt8(parts[3]), let g = UInt8(parts[4]), let b = UInt8(parts[5]) else { continue }
            vertices.append(SCNVector3(x, y, z))
            colors.append(contentsOf: [r, g, b, 255])
        }
        guard !vertices.isEmpty else { return nil }
        let maxPoints: Int
        switch displayStyle {
        case .standard: maxPoints = 20_000
        case .fineCloud: maxPoints = 35_000
        }
        if vertices.count > maxPoints {
            switch displayStyle {
            case .standard:
                let step = max(1, vertices.count / maxPoints)
                let indices = stride(from: 0, to: vertices.count, by: step)
                let v = indices.map { vertices[$0] }
                let c = Array(indices.map { i in [colors[i*4], colors[i*4+1], colors[i*4+2], 255] }.joined())
                return (v, c)
            case .fineCloud:
                var indices = Array(0..<vertices.count)
                indices.shuffle()
                let selected = indices.prefix(maxPoints).sorted()
                let v = selected.map { vertices[$0] }
                var c: [UInt8] = []
                c.reserveCapacity(selected.count * 4)
                for i in selected {
                    c.append(colors[i*4])
                    c.append(colors[i*4+1])
                    c.append(colors[i*4+2])
                    c.append(255)
                }
                return (v, c)
            }
        }
        return (vertices, colors)
    }

    /// SCNScene aus Punktwolken-Daten. Jeder Punkt wird als kleines Quad (2 Dreiecke) gezeichnet, damit es sichtbar ist.
    private func buildPointCloudScene(vertices: [SCNVector3], colors: [UInt8], displayStyle: PointCloudDisplayStyle) -> SCNScene {
        guard !vertices.isEmpty, colors.count >= vertices.count * 4 else { return makePlaceholderScene() }
        var useVertices = vertices
        var cx: Float = 0, cy: Float = 0, cz: Float = 0
        for v in useVertices {
            cx += v.x
            cy += v.y
            cz += v.z
        }
        let n = Float(useVertices.count)
        cx /= n
        cy /= n
        cz /= n
        for i in useVertices.indices {
            useVertices[i].x -= cx
            useVertices[i].y -= cy
            useVertices[i].z -= cz
        }
        var minX: Float = .greatestFiniteMagnitude, maxX: Float = -.greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude, maxY: Float = -.greatestFiniteMagnitude
        var minZ: Float = .greatestFiniteMagnitude, maxZ: Float = -.greatestFiniteMagnitude
        for v in useVertices {
            minX = min(minX, v.x); maxX = max(maxX, v.x)
            minY = min(minY, v.y); maxY = max(maxY, v.y)
            minZ = min(minZ, v.z); maxZ = max(maxZ, v.z)
        }
        let size = max(maxX - minX, maxY - minY, maxZ - minZ, 1)
        let camDist = size * 2.5
        var points = useVertices
        let vertexData = Data(bytes: &points, count: points.count * MemoryLayout<SCNVector3>.size)
        var pointColorsFloat: [Float] = []
        pointColorsFloat.reserveCapacity(points.count * 4)
        for i in 0..<points.count {
            pointColorsFloat.append(Float(colors[i * 4]) / 255.0)
            pointColorsFloat.append(Float(colors[i * 4 + 1]) / 255.0)
            pointColorsFloat.append(Float(colors[i * 4 + 2]) / 255.0)
            pointColorsFloat.append(1.0)
        }
        var pcf = pointColorsFloat
        let colorData = Data(bytes: &pcf, count: pcf.count * MemoryLayout<Float>.size)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: points.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: points.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 4 * MemoryLayout<Float>.size
        )
        var pointIndices = [Int32](repeating: 0, count: points.count)
        for i in 0..<points.count { pointIndices[i] = Int32(i) }
        let element = SCNGeometryElement(
            data: Data(bytes: pointIndices, count: pointIndices.count * MemoryLayout<Int32>.size),
            primitiveType: .point,
            primitiveCount: points.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        // Punktgröße auf Element-Ebene (nicht Material) einstellen.
        switch displayStyle {
        case .standard:
            let s = CGFloat(max(0.5, min(8.0, pointCloudPointSize)))
            element.pointSize = s
            element.minimumPointScreenSpaceRadius = s
            element.maximumPointScreenSpaceRadius = s
        case .fineCloud:
            let s = CGFloat(max(0.5, min(8.0, pointCloudPointSize)))
            element.pointSize = s
            element.minimumPointScreenSpaceRadius = s
            element.maximumPointScreenSpaceRadius = s
        }
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let mat = geometry.firstMaterial ?? SCNMaterial()
        mat.diffuse.contents = nil
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.emission.contents = nil
        geometry.materials = [mat]
        let node = SCNNode(geometry: geometry)
        let modelRoot = SCNNode()
        modelRoot.name = "modelRoot"
        modelRoot.addChildNode(node)

        let scene = SCNScene()
        setSceneBackground(scene)
        scene.rootNode.addChildNode(modelRoot)
        // Orbit-Achse im Mittelpunkt der Punktwolke + kleines Achsensystem anzeigen.
        recenterModelInScene(scene)
        addAxisGizmo(to: scene)
        let cam = SCNNode()
        cam.name = cameraNodeName
        cam.camera = SCNCamera()
        cam.position = SCNVector3(0, 0, camDist)
        cam.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(cam)
        return scene
    }
}

