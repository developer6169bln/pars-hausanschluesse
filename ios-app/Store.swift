import Foundation
import SwiftUI
import Combine

/// Lokaler Cache – überlebt App-Updates und neue Builds (Documents-Verzeichnis).
private struct HausanschluessePersistedPayload: Codable {
    var schemaVersion: Int = 1
    var auftraege: [Auftrag]
}

@MainActor
final class AuftraegeStore: ObservableObject {
    @Published var auftraege: [Auftrag] = []
    @Published var isLoading = false
    @Published var error: String?

    private let client: AuftraegeClient

    private static var persistenceURL: URL {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents-Verzeichnis nicht verfügbar")
        }
        return dir.appendingPathComponent("hausanschluesse_auftraege.json", isDirectory: false)
    }

    init(client: AuftraegeClient) {
        self.client = client
        if let cached = Self.loadFromDisk() {
            self.auftraege = cached
        }
    }

    /// Beim Wechsel in den Hintergrund aufrufen, damit der letzte Stand sicher geschrieben wird.
    func persistLocalCache() {
        persistToDisk()
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            let list = try await client.fetchAuftraege()
            auftraege = list
            persistToDisk()
        } catch {
            if auftraege.isEmpty {
                self.error = error.localizedDescription
            } else {
                self.error = "Server nicht erreichbar – es werden die zuletzt gespeicherten lokalen Daten angezeigt."
            }
        }
        isLoading = false
    }

    func save() async {
        do {
            try await client.saveAuftraege(auftraege)
            persistToDisk()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func update(_ auftrag: Auftrag) {
        if let idx = auftraege.firstIndex(where: { $0.id == auftrag.id }) {
            auftraege[idx] = auftrag
        } else {
            auftraege.insert(auftrag, at: 0)
        }
        persistToDisk()
    }

    func gesamtLaengeBaugruben(_ a: Auftrag) -> Double {
        let arr = a.baugrubenLaengen ?? []
        return arr.reduce(0) { $0 + $1 }
    }

    // MARK: - Lokale Persistenz

    private static func loadFromDisk() -> [Auftrag]? {
        let url = persistenceURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(HausanschluessePersistedPayload.self, from: data) {
            return payload.auftraege
        }
        // Fallback: reines Array (ältere Versionen)
        return try? decoder.decode([Auftrag].self, from: data)
    }

    private func persistToDisk() {
        let payload = HausanschluessePersistedPayload(auftraege: auftraege)
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: Self.persistenceURL, options: [.atomic])
        } catch {
            print("Hausanschlüsse: lokale Speicherung fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}
