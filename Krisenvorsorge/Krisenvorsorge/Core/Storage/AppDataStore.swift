import Foundation

/// Offline-first lokaler Speicher (kein Cloud-Zwang).
/// Für MVP wird JSON im Documents-Ordner gespeichert.
final class AppDataStore {
    private let fileName = "krisenvorsorge-appdata.json"

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent(fileName)
    }

    func load() -> AppData? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AppData.self, from: data)
        } catch {
            return nil
        }
    }

    func save(_ data: AppData) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let payload = try encoder.encode(data)
            try payload.write(to: fileURL, options: [.atomic])
        } catch {
            // MVP: still, weil App-UI offline-first funktionieren soll.
        }
    }
}

