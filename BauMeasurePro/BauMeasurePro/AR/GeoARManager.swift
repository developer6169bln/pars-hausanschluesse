import Foundation
import SceneKit
import CoreLocation
import simd

enum GeoARManager {
    static func createGrube(feature: GeoFeature) -> SCNNode {
        let width = CGFloat(feature.properties.width ?? 1.0)
        let length = CGFloat(feature.properties.length ?? 1.0)
        let depth = CGFloat(feature.properties.depth ?? 1.0)

        let box = SCNBox(width: width, height: depth, length: length, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = UIColor.systemOrange.withAlphaComponent(0.7)
        box.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: box)
        node.position.y = -Float(depth * 0.5)
        return node
    }

    static func createLeitung(start: SCNVector3, end: SCNVector3) -> SCNNode {
        let startV = simd_float3(start.x, start.y, start.z)
        let endV = simd_float3(end.x, end.y, end.z)
        let vector = endV - startV
        let distance = simd_length(vector)

        let cylinder = SCNCylinder(radius: 0.05, height: CGFloat(max(distance, 0.001)))
        cylinder.firstMaterial?.diffuse.contents = UIColor.systemBlue
        let node = SCNNode(geometry: cylinder)

        node.simdPosition = (startV + endV) * 0.5
        node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: simd_normalize(vector))
        return node
    }

    /// Echte lokale Meterprojektion (East/North) + Heading-Korrektur.
    static func positionFromGPS(
        target: CLLocationCoordinate2D,
        user: CLLocationCoordinate2D,
        origin: CLLocationCoordinate2D,
        headingDegrees: Double
    ) -> SCNVector3 {
        let metersPerDegLat = 111_320.0
        let meanLat = ((target.latitude + origin.latitude) * 0.5) * .pi / 180.0
        let metersPerDegLon = 111_320.0 * cos(meanLat)

        let east = (target.longitude - origin.longitude) * metersPerDegLon
        let north = (target.latitude - origin.latitude) * metersPerDegLat

        let userEast = (user.longitude - origin.longitude) * metersPerDegLon
        let userNorth = (user.latitude - origin.latitude) * metersPerDegLat

        let relEast = east - userEast
        let relNorth = north - userNorth

        let headingRad = headingDegrees * .pi / 180.0
        let x = relEast * cos(headingRad) - relNorth * sin(headingRad)
        let z = relEast * sin(headingRad) + relNorth * cos(headingRad)
        return SCNVector3(Float(x), 0, Float(-z))
    }
}
