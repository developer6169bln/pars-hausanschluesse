import Foundation
import ARKit
import SceneKit
import UIKit

/// Einzelner Punkt mit Position (Weltkoordinaten) und Farbe (0–255).
struct ColoredPoint {
    var x: Float
    var y: Float
    var z: Float
    var r: UInt8
    var g: UInt8
    var b: UInt8
}

/// Sammelt Tiefenbild + Kamerabild zu einer RGB-Punktwolke (ScanAce-ähnlich). Thread-sicher.
final class PointCloudService {
    /// Voxel-Kantenlänge in Metern – kleiner = feinere Punktwolke (z. B. 0.005 = 5 mm).
    var voxelSize: Float = 0.005

    /// Jeder N-te Pixel in X/Y wird verarbeitet (1 = volle Auflösung, 2 = jede 2. Zeile/Spalte).
    var depthStep: Int = 1

    /// Harte Obergrenze für gespeicherte Punkte, um RAM-Spitzen bei langen Scans zu vermeiden.
    var maxStoredPoints: Int = 280_000

    private var voxelToPoint: [String: ColoredPoint] = [:]
    private let lock = NSLock()

    /// Gibt die aktuelle Punktanzahl zurück.
    var pointCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return voxelToPoint.count
    }

    /// Fügt Punkte aus einem AR-Frame hinzu (Tiefenbild + Kamerabild). Sollte von einem Hintergrund-Queue aufgerufen werden.
    func addPoints(from frame: ARFrame) {
        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth,
              let depthMap = depthData.depthMap as CVPixelBuffer?
        else { return }

        let camImage = frame.capturedImage
        let camera = frame.camera
        let transform = camera.transform

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let camWidth = CVPixelBufferGetWidth(camImage)
        let camHeight = CVPixelBufferGetHeight(camImage)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let depthFormat = CVPixelBufferGetPixelFormatType(depthMap)
        guard depthFormat == kCVPixelFormatType_DepthFloat32 || depthFormat == kCVPixelFormatType_DisparityFloat32 else { return }

        // Intrinsics sind für das Kamerabild (camWidth x camHeight). Auf Tiefenkarten-Auflösung skalieren.
        let intrinsics = camera.intrinsics
        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y
        let scaleX = Float(camWidth) / Float(max(1, depthWidth))
        let scaleY = Float(camHeight) / Float(max(1, depthHeight))
        let fxD = fx / scaleX
        let fyD = fy / scaleY
        let cxD = cx / scaleX
        let cyD = cy / scaleY

        var confBase: UnsafeMutableRawPointer?
        var confBytesPerRow = 0
        var confidenceBuffer: CVPixelBuffer?
        if let conf = depthData.confidenceMap as CVPixelBuffer?, CVPixelBufferGetPixelFormatType(conf) == kCVPixelFormatType_OneComponent8 {
            CVPixelBufferLockBaseAddress(conf, .readOnly)
            confidenceBuffer = conf
            confBase = CVPixelBufferGetBaseAddress(conf)
            confBytesPerRow = CVPixelBufferGetBytesPerRow(conf)
        }
        defer { if let conf = confidenceBuffer { CVPixelBufferUnlockBaseAddress(conf, .readOnly) } }

        var added: [(String, ColoredPoint)] = []

        for j in stride(from: 0, to: depthHeight, by: depthStep) {
            for i in stride(from: 0, to: depthWidth, by: depthStep) {
                let offset = j * depthBytesPerRow + i * 4
                var depth = (depthBase + offset).assumingMemoryBound(to: Float.self).pointee
                if depthFormat == kCVPixelFormatType_DisparityFloat32, depth > 0 {
                    depth = 1.0 / depth
                }
                if depth <= 0.01 || depth > 10 { continue }

                if let confBase = confBase {
                    let confOffset = j * confBytesPerRow + i
                    let confVal = (confBase + confOffset).assumingMemoryBound(to: UInt8.self).pointee
                    if confVal < 1 { continue }
                }

                let u = Float(i) + 0.5
                let v = Float(j) + 0.5
                let camX = (u - cxD) * depth / fxD
                let camY = -(v - cyD) * depth / fyD
                let camZ = -depth
                let camPt = simd_float4(camX, camY, camZ, 1)
                let worldPt = transform * camPt

                let voxX = Int(worldPt.x / voxelSize)
                let voxY = Int(worldPt.y / voxelSize)
                let voxZ = Int(worldPt.z / voxelSize)
                let key = "\(voxX)_\(voxY)_\(voxZ)"

                let sx = Int((Float(i) / Float(depthWidth)) * Float(camWidth))
                let sy = Int((Float(j) / Float(depthHeight)) * Float(camHeight))
                let clampedX = min(max(0, sx), camWidth - 1)
                let clampedY = min(max(0, sy), camHeight - 1)
                let (r, g, b) = sampleRGB(from: camImage, x: clampedX, y: clampedY)

                added.append((key, ColoredPoint(
                    x: worldPt.x,
                    y: worldPt.y,
                    z: worldPt.z,
                    r: r, g: g, b: b
                )))
            }
        }

        lock.lock()
        for (key, pt) in added {
            voxelToPoint[key] = pt
        }
        trimIfNeededLocked()
        lock.unlock()
    }

    /// Liest RGB an Pixel (x,y) aus dem Kamerabuffer (typ. YpCbCr).
    private func sampleRGB(from pixelBuffer: CVPixelBuffer, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_32RGBA {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return (128, 128, 128) }
            let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let bytesPerPixel = 4
            let offset = y * bpr + x * bytesPerPixel
            let b = (base + offset).assumingMemoryBound(to: UInt8.self).pointee
            let g = (base + offset + 1).assumingMemoryBound(to: UInt8.self).pointee
            let r = (base + offset + 2).assumingMemoryBound(to: UInt8.self).pointee
            return (r, g, b)
        }
        if format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            guard let baseY = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
                  let baseCbCr = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
                return (128, 128, 128)
            }
            let bprY = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let bprCbCr = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let luma = (baseY + y * bprY + x).assumingMemoryBound(to: UInt8.self).pointee
            let cx2 = x / 2
            let cy2 = y / 2
            let cb = (baseCbCr + cy2 * bprCbCr + cx2 * 2).assumingMemoryBound(to: UInt8.self).pointee
            let cr = (baseCbCr + cy2 * bprCbCr + cx2 * 2 + 1).assumingMemoryBound(to: UInt8.self).pointee
            let r = yuvToR(y: Int(luma), cb: Int(cb), cr: Int(cr))
            let g = yuvToG(y: Int(luma), cb: Int(cb), cr: Int(cr))
            let b = yuvToB(y: Int(luma), cb: Int(cb), cr: Int(cr))
            return boostedColor(r: r, g: g, b: b)
        }
        return (128, 128, 128)
    }

    private func yuvToR(y: Int, cb: Int, cr: Int) -> Int {
        return y + Int(1.402 * Double(cr - 128))
    }
    private func yuvToG(y: Int, cb: Int, cr: Int) -> Int {
        return y - Int(0.344 * Double(cb - 128)) - Int(0.714 * Double(cr - 128))
    }
    private func yuvToB(y: Int, cb: Int, cr: Int) -> Int {
        return y + Int(1.772 * Double(cb - 128))
    }

    /// Macht Farben in der Live-Punktwolke sichtbarer (etwas mehr Kontrast + Sättigung).
    private func boostedColor(r: Int, g: Int, b: Int) -> (UInt8, UInt8, UInt8) {
        let rf = max(0.0, min(255.0, Double(r))) / 255.0
        let gf = max(0.0, min(255.0, Double(g))) / 255.0
        let bf = max(0.0, min(255.0, Double(b))) / 255.0
        let luma = 0.2126 * rf + 0.7152 * gf + 0.0722 * bf
        let satBoost = 1.30
        let contrast = 1.08
        let rr = ((luma + (rf - luma) * satBoost) - 0.5) * contrast + 0.5
        let gg = ((luma + (gf - luma) * satBoost) - 0.5) * contrast + 0.5
        let bb = ((luma + (bf - luma) * satBoost) - 0.5) * contrast + 0.5
        return (
            UInt8(max(0, min(255, Int(rr * 255.0)))),
            UInt8(max(0, min(255, Int(gg * 255.0)))),
            UInt8(max(0, min(255, Int(bb * 255.0))))
        )
    }

    /// Reduziert die Punktmenge in Blöcken, um Speicher stabil zu halten.
    private func trimIfNeededLocked() {
        guard voxelToPoint.count > maxStoredPoints else { return }
        let targetCount = Int(Double(maxStoredPoints) * 0.82)
        let keys = Array(voxelToPoint.keys)
        let removeCount = max(0, keys.count - targetCount)
        guard removeCount > 0 else { return }
        for key in keys.shuffled().prefix(removeCount) {
            voxelToPoint.removeValue(forKey: key)
        }
    }

    /// Kopie aller Punkte für Anzeige oder Export.
    func copyPoints() -> [ColoredPoint] {
        lock.lock()
        defer { lock.unlock() }
        return Array(voxelToPoint.values)
    }

    /// Erstellt eine SCNGeometry für die Punktwolke (für Anzeige). Optional: max Punkte begrenzen.
    func makeSceneKitGeometry(maxPoints: Int? = nil, pointSize: CGFloat = 1.0) -> SCNGeometry? {
        var points = copyPoints()
        if let max = maxPoints, points.count > max {
            points = Array(points.shuffled().prefix(max))
        }
        guard !points.isEmpty else { return nil }

        var vertices: [SCNVector3] = points.map { SCNVector3($0.x, $0.y, $0.z) }
        var colors: [UInt8] = []
        for p in points {
            colors.append(p.r)
            colors.append(p.g)
            colors.append(p.b)
            colors.append(255)
        }

        let vertexData = Data(bytes: &vertices, count: vertices.count * MemoryLayout<SCNVector3>.size)
        let colorData = Data(colors)

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
            usesFloatComponents: false,
            componentsPerVector: 4,
            bytesPerComponent: 1,
            dataOffset: 0,
            dataStride: 4
        )
        var indices = [Int32](repeating: 0, count: points.count)
        for i in 0..<points.count { indices[i] = Int32(i) }
        let element = SCNGeometryElement(
            data: Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size),
            primitiveType: .point,
            primitiveCount: points.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        let s = max(0.5, min(8.0, pointSize))
        element.pointSize = s
        element.minimumPointScreenSpaceRadius = s
        element.maximumPointScreenSpaceRadius = s

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let mat = geometry.firstMaterial ?? SCNMaterial()
        mat.diffuse.contents = UIColor.white
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        geometry.materials = [mat]
        return geometry
    }

    /// Export als PLY (ASCII) mit x,y,z,red,green,blue.
    func exportPLY() -> Data? {
        let points = copyPoints()
        guard !points.isEmpty else { return nil }
        var header = "ply\nformat ascii 1.0\nelement vertex \(points.count)\n"
        header += "property float x\nproperty float y\nproperty float z\n"
        header += "property uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n"
        var body = ""
        for p in points {
            body += "\(p.x) \(p.y) \(p.z) \(p.r) \(p.g) \(p.b)\n"
        }
        return (header + body).data(using: .utf8)
    }

    /// Setzt die Punktwolke zurück.
    func reset() {
        lock.lock()
        voxelToPoint.removeAll()
        lock.unlock()
    }
}
