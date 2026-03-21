import Foundation
import SwiftUI
import Combine

@MainActor
final class AuftraegeStore: ObservableObject {
    @Published var auftraege: [Auftrag] = []
    @Published var isLoading = false
    @Published var error: String?

    private let client: AuftraegeClient

    init(client: AuftraegeClient) {
        self.client = client
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            let list = try await client.fetchAuftraege()
            auftraege = list
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func save() async {
        do {
            try await client.saveAuftraege(auftraege)
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
    }

    func gesamtLaengeBaugruben(_ a: Auftrag) -> Double {
        let arr = a.baugrubenLaengen ?? []
        return arr.reduce(0) { $0 + $1 }
    }
}
