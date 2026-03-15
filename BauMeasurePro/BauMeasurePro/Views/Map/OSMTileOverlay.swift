import MapKit

/// Lädt Kartenkacheln von OpenStreetMap. OSM-Daten werden community-gepflegt und sind oft aktueller als Apple-Karten.
/// Nutzungsbedingungen: https://operations.osmfoundation.org/policies/tiles/ – erkennbarer User-Agent erforderlich.
final class OSMTileOverlay: MKTileOverlay {

    private static let template = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    private static let userAgent = "BauMeasurePro/1.0 (iOS; HA-Messung)"

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let urlString = Self.template
            .replacingOccurrences(of: "{z}", with: "\(path.z)")
            .replacingOccurrences(of: "{x}", with: "\(path.x)")
            .replacingOccurrences(of: "{y}", with: "\(path.y)")
        guard let url = URL(string: urlString) else {
            result(nil, NSError(domain: "OSMTileOverlay", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            result(data, error)
        }.resume()
    }
}
