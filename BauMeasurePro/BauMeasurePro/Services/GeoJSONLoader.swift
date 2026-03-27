import Foundation

enum GeoJSONLoader {
    static func load(filename: String) -> [GeoFeature] {
        if let docsURL = documentsURL(filename: filename), FileManager.default.fileExists(atPath: docsURL.path) {
            if let loaded = loadFromURL(docsURL) { return loaded }
        }
        guard let bundleURL = Bundle.main.url(forResource: filename, withExtension: "geojson") else { return [] }
        return loadFromURL(bundleURL) ?? []
    }

    static func save(features: [GeoFeature], filename: String) -> Bool {
        guard let url = documentsURL(filename: filename) else { return false }
        let payload = FeatureCollection(type: "FeatureCollection", features: features)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(payload)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            print("GeoJSONLoader Save Fehler:", error.localizedDescription)
            return false
        }
    }

    private static func documentsURL(filename: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("\(filename).geojson")
    }

    private static func loadFromURL(_ url: URL) -> [GeoFeature]? {
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(FeatureCollection.self, from: data)
            return decoded.features
        } catch {
            print("GeoJSONLoader Fehler:", error.localizedDescription)
            return nil
        }
    }
}
