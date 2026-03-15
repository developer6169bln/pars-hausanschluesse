import SwiftUI

/// Einstellungen: Geräte-ID und Server-URL; lädt zugewiesene Projekte vom Admin-Server.
struct DeviceIdSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: MapViewModel
    let storage: StorageService

    @State private var deviceId: String = ""
    @State private var serverBaseURL: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false
    @State private var loadedCount = 0
    @State private var removedFromServerCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("z. B. monteur-01", text: $deviceId)
                        .textContentType(.username)
                        .autocapitalization(.none)
                    Text("Vom Admin in der Web-App vergebene ID. Ohne ID siehst du nur lokale Projekte.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Geräte-ID")
                }

                Section {
                    TextField("z. B. http://192.168.1.100:3010", text: $serverBaseURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    Text("Basis-URL des Servers (ohne abschließenden Schrägstrich).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Server-URL")
                }

                Section {
                    Button {
                        saveAndLoad()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isLoading ? "Laden…" : "Projekte vom Server laden")
                        }
                    }
                    .disabled(deviceId.trimmingCharacters(in: .whitespaces).isEmpty || serverBaseURL.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }
            .navigationTitle("Geräte-ID & Server")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                deviceId = storage.deviceId
                serverBaseURL = storage.serverBaseURL
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        storage.deviceId = deviceId
                        storage.serverBaseURL = serverBaseURL
                        dismiss()
                    }
                }
            }
            .alert("Fehler", isPresented: $showError) {
                Button("OK", role: .cancel) { showError = false }
            } message: {
                Text(errorMessage ?? "Unbekannter Fehler")
            }
            .alert(loadedCount == 0 && removedFromServerCount == 0 ? "Keine Änderungen" : "Projekte aktualisiert", isPresented: $showSuccess) {
                Button("OK", role: .cancel) { showSuccess = false; removedFromServerCount = 0; dismiss() }
            } message: {
                var parts: [String] = []
                if removedFromServerCount > 0 {
                    parts.append("\(removedFromServerCount) auf dem Server gelöschtes Projekt/Projekte wurden in der App entfernt.")
                }
                if loadedCount > 0 {
                    parts.append("\(loadedCount) neues Projekt/Projekte vom Server hinzugefügt.")
                }
                if parts.isEmpty {
                    parts.append("Alle zugewiesenen Projekte sind bereits vorhanden.")
                }
                Text(parts.joined(separator: " "))
            }
        }
    }

    private func saveAndLoad() {
        let id = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        storage.deviceId = id
        storage.serverBaseURL = url
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetched = try await AssignedProjectsService.fetchAssignedProjects(deviceId: id, serverBaseURL: url)
                await MainActor.run {
                    let existing = viewModel.projects
                    let fetchedServerIds = Set(fetched.compactMap { $0.serverProjectId })
                    let existingAfterRemoval = existing.filter { p in
                        guard let sid = p.serverProjectId else { return true }
                        return fetchedServerIds.contains(sid)
                    }
                    let removedCount = existing.count - existingAfterRemoval.count
                    let newOnly = fetched.filter { proj in
                        guard let sid = proj.serverProjectId else { return true }
                        return !existingAfterRemoval.contains(where: { $0.serverProjectId == sid })
                    }
                    viewModel.projects = existingAfterRemoval + newOnly
                    storage.saveProjects(viewModel.projects)
                    loadedCount = newOnly.count
                    removedFromServerCount = removedCount
                    showSuccess = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}
