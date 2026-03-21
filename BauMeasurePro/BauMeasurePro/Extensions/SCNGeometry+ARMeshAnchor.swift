import SceneKit
import ARKit
import UIKit
import CoreImage

extension SCNGeometry {

    /// Konvertiert das Kamerabild (CVPixelBuffer) in eine UIImage für SceneKit-Material.
    static func image(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Erstellt SCNGeometry mit Kameratextur: projiziert das Kamerabild auf das Mesh (UV aus Projektion).
    /// Wird beim Speichern verwendet (ScanAce-Stil: Modell in reeller Farbe). orientation = windowScene.interfaceOrientation.
    static func fromAnchor(meshAnchor: ARMeshAnchor, frame: ARFrame, orientation: UIInterfaceOrientation = .landscapeRight) -> SCNGeometry? {
        let geom = meshAnchor.geometry
        let vertices = geom.vertices
        let faces = geom.faces
        let vertexCount = vertices.count
        guard vertexCount > 0, faces.count > 0 else { return nil }
        guard let cameraImage = image(from: frame.capturedImage) else { return nil }
        let imageSize = CGSize(width: CVPixelBufferGetWidth(frame.capturedImage), height: CVPixelBufferGetHeight(frame.capturedImage))
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let vertexSource = SCNGeometrySource(
            buffer: vertices.buffer,
            vertexFormat: vertices.format,
            semantic: .vertex,
            vertexCount: vertexCount,
            dataOffset: vertices.offset,
            dataStride: vertices.stride
        )
        var texCoords = [CGPoint](repeating: .zero, count: vertexCount)
        let transform = meshAnchor.transform
        let camera = frame.camera
        let orient = orientation

        let vOffset = vertices.offset
        let vStride = vertices.stride
        for i in 0..<vertexCount {
            let ptr = vertices.buffer.contents().advanced(by: vOffset + i * vStride)
            let x = ptr.assumingMemoryBound(to: Float.self).pointee
            let y = ptr.advanced(by: 4).assumingMemoryBound(to: Float.self).pointee
            let z = ptr.advanced(by: 8).assumingMemoryBound(to: Float.self).pointee
            let local = simd_float4(x, y, z, 1)
            let world = transform * local
            let world3 = simd_float3(world.x, world.y, world.z)
            let pt = camera.projectPoint(world3, orientation: orient, viewportSize: imageSize)
            let u = max(0, min(1, pt.x / imageSize.width))
            let v = 1 - max(0, min(1, pt.y / imageSize.height))
            texCoords[i] = CGPoint(x: u, y: v)
        }

        let uvData = texCoords.flatMap { [Float($0.x), Float($0.y)] }
        let uvBuffer = uvData.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvSource = SCNGeometrySource(
            data: uvBuffer,
            semantic: .texcoord,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 2,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 2 * MemoryLayout<Float>.size
        )
        let faceData = Data(
            bytesNoCopy: faces.buffer.contents(),
            count: faces.buffer.length,
            deallocator: .none
        )
        let geometryElement = SCNGeometryElement(
            data: faceData,
            primitiveType: .triangles,
            primitiveCount: faces.count,
            bytesPerIndex: faces.bytesPerIndex
        )
        let geometry = SCNGeometry(sources: [vertexSource, uvSource], elements: [geometryElement])
        let mat = SCNMaterial()
        mat.diffuse.contents = cameraImage
        mat.lightingModel = .constant
        mat.transparency = 0.98
        mat.fillMode = .fill
        mat.transparencyMode = .singleLayer
        geometry.materials = [mat]
        return geometry
    }

    /// Erstellt SCNGeometry aus einem ARMeshAnchor (für Live-Anzeige).
    /// Ohne Klassifikationsfarben – nur halbtransparentes Grau, Kamera scheint durch, App bleibt flüssig.
    static func fromAnchor(meshAnchor: ARMeshAnchor) -> SCNGeometry {
        let geom = meshAnchor.geometry
        let vertices = geom.vertices
        let faces = geom.faces
        let vertexSource = SCNGeometrySource(
            buffer: vertices.buffer,
            vertexFormat: vertices.format,
            semantic: .vertex,
            vertexCount: vertices.count,
            dataOffset: vertices.offset,
            dataStride: vertices.stride
        )
        let faceData = Data(
            bytesNoCopy: faces.buffer.contents(),
            count: faces.buffer.length,
            deallocator: .none
        )
        let geometryElement = SCNGeometryElement(
            data: faceData,
            primitiveType: .triangles,
            primitiveCount: faces.count,
            bytesPerIndex: faces.bytesPerIndex
        )
        let geometry = SCNGeometry(sources: [vertexSource], elements: [geometryElement])
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemGray.withAlphaComponent(0.45)
        mat.transparency = 0.65
        mat.fillMode = .fill
        mat.transparencyMode = .singleLayer
        geometry.materials = [mat]
        return geometry
    }

    /// Erstellt eine Kopie der Geometry mit eigenen Puffer-Daten (für Speicherung/Export).
    /// Volle Auflösung (keine Vereinfachung); halbtransparentes Grau, geringe Last.
    static func copyFromAnchor(meshAnchor: ARMeshAnchor) -> SCNGeometry? {
        let geom = meshAnchor.geometry
        let vertices = geom.vertices
        let faces = geom.faces
        let vertexByteLength = vertices.count * vertices.stride
        guard vertexByteLength > 0, faces.buffer.length > 0 else { return nil }
        var vertexData = Data(count: vertexByteLength)
        vertexData.withUnsafeMutableBytes { dst in
            if let base = dst.baseAddress {
                let src = vertices.buffer.contents().advanced(by: vertices.offset)
                base.copyMemory(from: src, byteCount: vertexByteLength)
            }
        }
        var faceData = Data(count: faces.buffer.length)
        faceData.withUnsafeMutableBytes { dst in
            if let base = dst.baseAddress {
                base.copyMemory(from: faces.buffer.contents(), byteCount: faces.buffer.length)
            }
        }
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: 4,
            dataOffset: 0,
            dataStride: vertices.stride
        )
        let geometryElement = SCNGeometryElement(
            data: faceData,
            primitiveType: .triangles,
            primitiveCount: faces.count,
            bytesPerIndex: faces.bytesPerIndex
        )
        let geometry = SCNGeometry(sources: [vertexSource], elements: [geometryElement])
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemGray.withAlphaComponent(0.6)
        mat.transparency = 0.75
        mat.fillMode = .fill
        geometry.materials = [mat]
        return geometry
    }

    /// Vereinfacht ein Mesh, indem Vertices auf ein Raster quantisiert werden und zu kleine Dreiecke
    /// (Kantenlänge < `triangleEdgeLimitMeters`) entfernt werden.
    ///
    /// Das ist eine praxisnahe „Triangle Edge Limit“-Optimierung, um Noise durch zu feine Dreiecke zu reduzieren
    /// (typisch 0.03–0.05 m).
    func optimized(triangleEdgeLimitMeters: Float) -> SCNGeometry {
        let edge = max(0.005, triangleEdgeLimitMeters)

        guard let vertexSource = sources.first(where: { $0.semantic == .vertex }),
              let element = elements.first,
              element.primitiveType == .triangles else { return self }

        let hasUV = sources.contains(where: { $0.semantic == .texcoord })
        let uvSource = sources.first(where: { $0.semantic == .texcoord })

        // --- Vertex Positions lesen
        let vCount = vertexSource.vectorCount
        guard vCount > 0 else { return self }

        var positions = [SIMD3<Float>](repeating: .zero, count: vCount)
        vertexSource.data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for i in 0..<vCount {
                let ptr = base.advanced(by: vertexSource.dataOffset + i * vertexSource.dataStride)
                let fptr = UnsafeRawPointer(ptr).assumingMemoryBound(to: Float.self)
                let fx = fptr[0]
                let fy = fptr[1]
                let fz = fptr[2]
                positions[i] = SIMD3<Float>(fx, fy, fz)
            }
        }

        // --- UVs lesen (optional)
        var uvs: [SIMD2<Float>] = []
        if hasUV, let uvSource {
            let uvCount = uvSource.vectorCount
            if uvCount == vCount {
                uvs = [SIMD2<Float>](repeating: .zero, count: uvCount)
                uvSource.data.withUnsafeBytes { raw in
                    let base = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    for i in 0..<uvCount {
                        let ptr = base.advanced(by: uvSource.dataOffset + i * uvSource.dataStride)
                        let fptr = UnsafeRawPointer(ptr).assumingMemoryBound(to: Float.self)
                        let fu = fptr[0]
                        let fv = fptr[1]
                        uvs[i] = SIMD2<Float>(fu, fv)
                    }
                }
            }
        }

        // --- Indizes lesen
        let indexCount = element.primitiveCount * 3
        guard indexCount > 0 else { return self }

        func readIndex(_ ptr: UnsafeRawPointer, bytesPerIndex: Int) -> Int {
            switch bytesPerIndex {
            case 2: return Int(ptr.assumingMemoryBound(to: UInt16.self).pointee)
            default: return Int(ptr.assumingMemoryBound(to: UInt32.self).pointee)
            }
        }

        var indices = [Int](repeating: 0, count: indexCount)
        element.data.withUnsafeBytes { raw in
            let base = raw.baseAddress!
            let bpi = element.bytesPerIndex
            for i in 0..<indexCount {
                let p = base.advanced(by: i * bpi)
                indices[i] = readIndex(p, bytesPerIndex: bpi)
            }
        }

        // --- Quantisierung & Remap
        struct Key: Hashable {
            let x: Int
            let y: Int
            let z: Int
        }

        func key(for p: SIMD3<Float>) -> Key {
            Key(
                x: Int((p.x / edge).rounded()),
                y: Int((p.y / edge).rounded()),
                z: Int((p.z / edge).rounded())
            )
        }

        var keyToNewIndex: [Key: Int] = [:]
        var newPositions: [SIMD3<Float>] = []
        newPositions.reserveCapacity(vCount / 2)

        var uvSum: [SIMD2<Float>] = []
        var uvCount: [Int] = []

        func getOrCreateVertex(oldIndex: Int) -> Int {
            let k = key(for: positions[oldIndex])
            if let existing = keyToNewIndex[k] { return existing }
            let np = SIMD3<Float>(Float(k.x) * edge, Float(k.y) * edge, Float(k.z) * edge)
            let newIdx = newPositions.count
            keyToNewIndex[k] = newIdx
            newPositions.append(np)
            if hasUV, !uvs.isEmpty {
                uvSum.append(uvs[oldIndex])
                uvCount.append(1)
            }
            return newIdx
        }

        func addUV(oldIndex: Int, newIndex: Int) {
            guard hasUV, !uvs.isEmpty else { return }
            uvSum[newIndex] += uvs[oldIndex]
            uvCount[newIndex] += 1
        }

        var newIndices: [UInt32] = []
        newIndices.reserveCapacity(indexCount)

        func dist(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
            simd_length(a - b)
        }

        for t in stride(from: 0, to: indices.count, by: 3) {
            let i0 = indices[t]
            let i1 = indices[t + 1]
            let i2 = indices[t + 2]
            if i0 < 0 || i1 < 0 || i2 < 0 || i0 >= vCount || i1 >= vCount || i2 >= vCount { continue }

            let n0 = getOrCreateVertex(oldIndex: i0)
            let n1 = getOrCreateVertex(oldIndex: i1)
            let n2 = getOrCreateVertex(oldIndex: i2)

            // UV-Akkumulation (für gemergte Vertices)
            if hasUV, !uvs.isEmpty {
                addUV(oldIndex: i0, newIndex: n0)
                addUV(oldIndex: i1, newIndex: n1)
                addUV(oldIndex: i2, newIndex: n2)
            }

            // Degenerate
            if n0 == n1 || n1 == n2 || n0 == n2 { continue }

            let p0 = newPositions[n0]
            let p1 = newPositions[n1]
            let p2 = newPositions[n2]
            let e01 = dist(p0, p1)
            let e12 = dist(p1, p2)
            let e20 = dist(p2, p0)

            // Triangle Edge Limit: zu kleine Dreiecke entfernen
            if e01 < edge || e12 < edge || e20 < edge { continue }

            newIndices.append(UInt32(n0))
            newIndices.append(UInt32(n1))
            newIndices.append(UInt32(n2))
        }

        // Falls zu aggressiv: Original zurückgeben
        guard newPositions.count >= 3, newIndices.count >= 3 else { return self }

        // --- Neue Geometry bauen
        var vData = Data(count: newPositions.count * MemoryLayout<Float>.size * 3)
        vData.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            for p in newPositions {
                let arr: [Float] = [p.x, p.y, p.z]
                base.advanced(by: offset).copyMemory(from: arr, byteCount: MemoryLayout<Float>.size * 3)
                offset += MemoryLayout<Float>.size * 3
            }
        }

        let newVertexSource = SCNGeometrySource(
            data: vData,
            semantic: .vertex,
            vectorCount: newPositions.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )

        var sources: [SCNGeometrySource] = [newVertexSource]

        if hasUV, !uvSum.isEmpty, uvSum.count == newPositions.count, uvCount.count == newPositions.count {
            var uvAvg = [SIMD2<Float>](repeating: .zero, count: uvSum.count)
            for i in 0..<uvSum.count {
                let c = max(1, uvCount[i])
                uvAvg[i] = uvSum[i] / Float(c)
            }
            var uvData = Data(count: uvAvg.count * MemoryLayout<Float>.size * 2)
            uvData.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                for uv in uvAvg {
                    let arr: [Float] = [uv.x, uv.y]
                    base.advanced(by: offset).copyMemory(from: arr, byteCount: MemoryLayout<Float>.size * 2)
                    offset += MemoryLayout<Float>.size * 2
                }
            }
            let newUVSource = SCNGeometrySource(
                data: uvData,
                semantic: .texcoord,
                vectorCount: uvAvg.count,
                usesFloatComponents: true,
                componentsPerVector: 2,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<Float>.size * 2
            )
            sources.append(newUVSource)
        }

        let iData = newIndices.withUnsafeBufferPointer { Data(buffer: $0) }
        let newElement = SCNGeometryElement(
            data: iData,
            primitiveType: .triangles,
            primitiveCount: newIndices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let out = SCNGeometry(sources: sources, elements: [newElement])
        out.materials = materials
        return out
    }
}
