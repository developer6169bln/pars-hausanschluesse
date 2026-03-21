import Foundation

struct AuftraegeClient {
    var baseURL: URL

    func fetchAuftraege() async throws -> [Auftrag] {
        let url = baseURL.appendingPathComponent("api").appendingPathComponent("auftraege")
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Auftrag].self, from: data)
    }

    func saveAuftraege(_ list: [Auftrag]) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api").appendingPathComponent("auftraege"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(list)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}
