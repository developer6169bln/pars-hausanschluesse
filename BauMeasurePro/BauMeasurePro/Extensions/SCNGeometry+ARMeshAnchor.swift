import SceneKit
import ARKit
import UIKit

extension SCNGeometry {

    /// Erstellt SCNGeometry aus einem ARMeshAnchor (für Live-Anzeige).
    /// Hinweis: Die Vertex-Daten gehören dem Anchor; bei Export Kopie verwenden.
    static func fromAnchor(meshAnchor: ARMeshAnchor) -> SCNGeometry {
        let vertices = meshAnchor.geometry.vertices
        let faces = meshAnchor.geometry.faces
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
        mat.diffuse.contents = UIColor.systemGray.withAlphaComponent(0.8)
        mat.fillMode = .fill
        geometry.materials = [mat]
        return geometry
    }

    /// Erstellt eine Kopie der Geometry mit eigenen Puffer-Daten (für Speicherung/Export).
    static func copyFromAnchor(meshAnchor: ARMeshAnchor) -> SCNGeometry? {
        let vertices = meshAnchor.geometry.vertices
        let faces = meshAnchor.geometry.faces
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
        mat.diffuse.contents = UIColor.systemGray.withAlphaComponent(0.8)
        mat.fillMode = .fill
        geometry.materials = [mat]
        return geometry
    }
}
