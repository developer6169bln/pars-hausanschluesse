import SwiftUI
import SceneKit
import UIKit

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

/// Kamera hinzufügen, die auf den Ursprung blickt.
private func addDefaultCamera(to scene: SCNScene) {
    let cam = SCNNode()
    cam.name = cameraNodeName
    cam.camera = SCNCamera()
    cam.position = SCNVector3(0, 0, 5)
    cam.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    scene.rootNode.addChildNode(cam)
}

/// UIKit-SCNView als Ersatz für SwiftUI SceneView – zuverlässigere Darstellung.
struct SceneKitContainerView: UIViewRepresentable {
    let scene: SCNScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.scene = scene
        view.pointOfView = scene.rootNode.childNode(withName: cameraNodeName, recursively: true)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = scene
        uiView.pointOfView = scene.rootNode.childNode(withName: cameraNodeName, recursively: true)
    }
}

struct Scan3DViewerView: View {
    let scan: ThreeDScan
    private let storage = StorageService()
    @State private var scene: SCNScene = makePlaceholderScene()
    @AppStorage("pointCloudDisplayStyle") private var displayStyle: String = PointCloudDisplayStyle.standard.rawValue

    private var currentStyle: PointCloudDisplayStyle {
        PointCloudDisplayStyle(rawValue: displayStyle) ?? .standard
    }

    private var isPointCloudScan: Bool {
        scan.filePath.lowercased().hasSuffix(".ply")
    }

    var body: some View {
        Color(red: 0.15, green: 0.15, blue: 0.2)
            .overlay {
                SceneKitContainerView(scene: scene)
            }
            .ignoresSafeArea()
            .frame(minWidth: 200, minHeight: 200)
        .navigationTitle(scan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPointCloudScan {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Darstellung", selection: $displayStyle) {
                        ForEach(PointCloudDisplayStyle.allCases, id: \.rawValue) { style in
                            Text(style.rawValue).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .task(id: "\(scan.id)-\(displayStyle)") {
            await Task.yield()
            await loadAndApplyScene()
        }
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
        case .standard: maxPoints = 120_000
        case .fineCloud: maxPoints = 120_000
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
        let quadSize: Float
        switch displayStyle {
        case .standard: quadSize = max(size * 0.004, 0.003)
        case .fineCloud: quadSize = max(size * 0.0022, 0.0018)
        }
        let h = quadSize
        var quadVertices: [SCNVector3] = []
        var quadColorsFloat: [Float] = []
        var quadIndices: [Int32] = []
        for i in 0..<useVertices.count {
            let x = useVertices[i].x
            let y = useVertices[i].y
            let z = useVertices[i].z
            let r = Float(colors[i * 4]) / 255
            let g = Float(colors[i * 4 + 1]) / 255
            let b = Float(colors[i * 4 + 2]) / 255
            let base = Int32(quadVertices.count)
            quadVertices.append(contentsOf: [
                SCNVector3(x - h, y - h, z),
                SCNVector3(x + h, y - h, z),
                SCNVector3(x + h, y + h, z),
                SCNVector3(x - h, y + h, z)
            ])
            for _ in 0..<4 {
                quadColorsFloat.append(contentsOf: [r, g, b, 1.0])
            }
            quadIndices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
        var qv = quadVertices
        let vertexData = Data(bytes: &qv, count: qv.count * MemoryLayout<SCNVector3>.size)
        var qcf = quadColorsFloat
        let colorData = Data(bytes: &qcf, count: qcf.count * MemoryLayout<Float>.size)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: quadVertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: quadVertices.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 4 * MemoryLayout<Float>.size
        )
        let element = SCNGeometryElement(
            data: Data(bytes: quadIndices, count: quadIndices.count * MemoryLayout<Int32>.size),
            primitiveType: .triangles,
            primitiveCount: quadIndices.count / 3,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let mat = geometry.firstMaterial ?? SCNMaterial()
        mat.diffuse.contents = nil
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.emission.contents = nil
        geometry.materials = [mat]
        let node = SCNNode(geometry: geometry)
        let scene = SCNScene()
        setSceneBackground(scene)
        scene.rootNode.addChildNode(node)
        let cam = SCNNode()
        cam.name = cameraNodeName
        cam.camera = SCNCamera()
        cam.position = SCNVector3(0, 0, camDist)
        cam.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(cam)
        return scene
    }
}

