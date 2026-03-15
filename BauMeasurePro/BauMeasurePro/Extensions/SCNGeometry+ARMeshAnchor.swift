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
}
