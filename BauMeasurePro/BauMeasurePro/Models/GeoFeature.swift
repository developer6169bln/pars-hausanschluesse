import Foundation
import CoreLocation

struct FeatureCollection: Codable {
    let type: String
    let features: [GeoFeature]
}

struct GeoFeature: Codable, Identifiable {
    let id = UUID()
    let type: String
    let geometry: Geometry
    let properties: Properties

    private enum CodingKeys: String, CodingKey {
        case type
        case geometry
        case properties
    }
}

struct Geometry: Decodable {
    let type: String
    let pointCoordinates: [Double]?
    let lineCoordinates: [[Double]]?

    private enum CodingKeys: String, CodingKey {
        case type
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)

        switch type {
        case "Point":
            pointCoordinates = try container.decode([Double].self, forKey: .coordinates)
            lineCoordinates = nil
        case "LineString":
            pointCoordinates = nil
            lineCoordinates = try container.decode([[Double]].self, forKey: .coordinates)
        default:
            pointCoordinates = nil
            lineCoordinates = nil
        }
    }

    init(type: String, pointCoordinates: [Double]?, lineCoordinates: [[Double]]?) {
        self.type = type
        self.pointCoordinates = pointCoordinates
        self.lineCoordinates = lineCoordinates
    }
}

extension Geometry: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if type == "Point" {
            try container.encode(pointCoordinates ?? [], forKey: .coordinates)
        } else {
            try container.encode(lineCoordinates ?? [], forKey: .coordinates)
        }
    }
}

struct Properties: Codable {
    let featureType: String
    let depth: Double?
    let width: Double?
    let length: Double?

    private enum CodingKeys: String, CodingKey {
        case featureType = "type"
        case depth
        case width
        case length
    }

    init(featureType: String, depth: Double?, width: Double?, length: Double?) {
        self.featureType = featureType
        self.depth = depth
        self.width = width
        self.length = length
    }
}

extension GeoFeature {
    init(point coordinate: CLLocationCoordinate2D, depth: Double, width: Double, length: Double) {
        self.type = "Feature"
        self.geometry = Geometry(
            type: "Point",
            pointCoordinates: [coordinate.longitude, coordinate.latitude],
            lineCoordinates: nil
        )
        self.properties = Properties(
            featureType: "grube",
            depth: depth,
            width: width,
            length: length
        )
    }

    init(lineCoordinates: [[Double]]) {
        self.type = "Feature"
        self.geometry = Geometry(
            type: "LineString",
            pointCoordinates: nil,
            lineCoordinates: lineCoordinates
        )
        self.properties = Properties(
            featureType: "leitung",
            depth: nil,
            width: nil,
            length: nil
        )
    }
}

extension Array where Element == Double {
    var asCoordinate: CLLocationCoordinate2D? {
        guard count >= 2 else { return nil }
        let lon = self[0]
        let lat = self[1]
        guard (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
