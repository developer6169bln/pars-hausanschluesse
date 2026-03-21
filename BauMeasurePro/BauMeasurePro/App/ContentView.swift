import SwiftUI
import UIKit
import UserNotifications

struct ContentView: View {
    @StateObject private var viewModel = MapViewModel()
    private let storage = StorageService()

    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var newStrasse = ""
    @State private var newHausnummer = ""
    @State private var newPostleitzahl = ""
    @State private var newOrt = ""
    @State private var newNvtNummer = ""
    @State private var newVerbundGroesse = ""
    @State private var newVerbundFarbe = ""
    @State private var newPipesFarbe1 = ""
    @State private var newPipesFarbe2 = ""
    @State private var newAuftragAbgeschlossen = false
    @State private var newTermin: Date?
    @State private var newGoogleDriveLink = ""
    @State private var newNotizen = ""
    @State private var newKundeName = ""
    @State private var newKundeTelefon = ""
    @State private var newKundeEmail = ""
    @State private var newKolonne = ""
    @State private var kolonnenList: [String] = []
    @State private var showAddKolonne = false
    @State private var newKolonneName = ""
    @State private var showDeviceIdSettings = false

    var body: some View {
        TabView {
            NavigationStack {
                projectList
            }
            .tabItem {
                Label("Projekte", systemImage: "folder.fill")
            }

            NavigationStack {
                MapView()
                    .environmentObject(viewModel)
                    .navigationTitle("Karte")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Karte", systemImage: "map.fill")
            }
        }
        .onAppear {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            var loaded = storage.loadProjects()
            // Migration/Normalisierung: fortlaufende Nummern setzen, falls noch keine vorhanden sind.
            for pIndex in loaded.indices {
                let sortedIds = loaded[pIndex].measurements.sorted { $0.date < $1.date }.map(\.id)
                let indexById = Dictionary(uniqueKeysWithValues: sortedIds.enumerated().map { ($0.element, $0.offset + 1) })
                for mIndex in loaded[pIndex].measurements.indices {
                    if loaded[pIndex].measurements[mIndex].index == nil {
                        loaded[pIndex].measurements[mIndex].index = indexById[loaded[pIndex].measurements[mIndex].id]
                    }
                }
            }
            viewModel.projects = loaded
            Task { await removeProjectsDeletedOnServer() }
        }
        .onChange(of: viewModel.projects) { _, new in
            storage.saveProjects(new)
        }
        .sheet(isPresented: $showNewProject) {
            newProjectSheet
        }
        .sheet(isPresented: $showAddKolonne) {
            addKolonneSheetForNewProject
        }
        .sheet(isPresented: $showDeviceIdSettings) {
            DeviceIdSettingsView(viewModel: viewModel, storage: storage)
        }
    }

    /// Entfernt in der App Projekte, die in der Admin-Web-App gelöscht wurden (Abgleich mit Server beim Start).
    private func removeProjectsDeletedOnServer() async {
        let deviceId = storage.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = storage.serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceId.isEmpty, !base.isEmpty else { return }
        do {
            let fetched = try await AssignedProjectsService.fetchAssignedProjects(deviceId: deviceId, serverBaseURL: base)
            await MainActor.run {
                let fetchedServerIds = Set(fetched.compactMap { $0.serverProjectId })
                let kept = viewModel.projects.filter { p in
                    guard let sid = p.serverProjectId else { return true }
                    return fetchedServerIds.contains(sid)
                }
                if kept.count != viewModel.projects.count {
                    viewModel.projects = kept
                    storage.saveProjects(kept)
                }
            }
        } catch { }
    }

    private var openProjects: [Project] {
        viewModel.projects
            .filter { $0.auftragAbgeschlossen != true }
            .sorted { (lhs, rhs) in
                (lhs.termin ?? .distantFuture) < (rhs.termin ?? .distantFuture)
            }
    }

    private var closedProjects: [Project] {
        viewModel.projects
            .filter { $0.auftragAbgeschlossen == true }
            .sorted { (lhs, rhs) in
                (lhs.termin ?? .distantFuture) < (rhs.termin ?? .distantFuture)
            }
    }

    @ViewBuilder
    private func projectRow(_ p: Project) -> some View {
        HStack(spacing: 12) {
            Button {
                openGoogleMapsNavigation(project: p)
            } label: {
                Image(systemName: "location.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            Button {
                markProjectWorkStarted(p)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            NavigationLink {
                ProjectDetailView(projectId: p.id)
                    .environmentObject(viewModel)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.name)
                            .font(.headline)
                        Text("\(p.measurements.count) Foto(s)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(p.termin.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Kein Termin")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    verbundColorBoxes(project: p)
                    pipesColorBoxes(project: p)
                    if p.totalMeters > 0 {
                        Text(String(format: "%.2f m", p.totalMeters))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(Int(p.totalLength)) px")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func markProjectWorkStarted(_ project: Project) {
        // Kein Start für fertige Projekte nötig.
        if project.auftragAbgeschlossen == true { return }
        if project.ampelStatus == "orange" { return }

        var updated = project
        updated.ampelStatus = "orange"
        viewModel.updateProject(updated)

        // Direkt an die Admin-Web-App senden, damit Ampel sofort sichtbar ist.
        let base = storage.serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        Task {
            if let synced = try? await ProjectSyncService.syncOrCreate(project: updated, storage: storage, serverBaseURL: base) {
                await MainActor.run { viewModel.updateProject(synced) }
            }
        }
    }

    private var projectList: some View {
        Group {
            if viewModel.projects.isEmpty {
                ContentUnavailableView(
                    "Keine Projekte",
                    systemImage: "folder.badge.plus",
                    description: Text("Tippe auf + um ein Projekt anzulegen und Fotos zu messen.")
                )
            } else {
                List {
                    Section("Offene Aufträge") {
                        ForEach(openProjects) { p in
                            projectRow(p)
                        }
                    }
                    Section("Abgeschlossene Aufträge") {
                        ForEach(closedProjects) { p in
                            projectRow(p)
                        }
                    }
                }
            }
        }
        .navigationTitle("Projekte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showDeviceIdSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newProjectName = ""
                    newStrasse = ""
                    newHausnummer = ""
                    newPostleitzahl = ""
                    newOrt = ""
                    newNvtNummer = ""
                    newVerbundGroesse = ""
                    newVerbundFarbe = ""
                    newPipesFarbe1 = ""
                    newPipesFarbe2 = ""
                    newAuftragAbgeschlossen = false
                    newTermin = nil
                    newGoogleDriveLink = ""
                    newNotizen = ""
                    newKolonne = ""
                    newKundeName = ""
                    newKundeTelefon = ""
                    newKundeEmail = ""
                    kolonnenList = storage.loadKolonnen()
                    showNewProject = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
    }

    private var newProjectSheet: some View {
        NavigationStack {
            Form {
                Section("Grunddaten") {
                    TextField("Projektname", text: $newProjectName)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                    TextField("Name Kunde", text: $newKundeName)
                    TextField("Telefon Kunde", text: $newKundeTelefon)
                        .keyboardType(.phonePad)
                    TextField("E-Mail Kunde", text: $newKundeEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Kolonne") {
                    Picker("Kolonne", selection: $newKolonne) {
                        Text("—").tag("")
                        ForEach(kolonnenList, id: \.self) { Text($0).tag($0) }
                    }
                    Button {
                        showAddKolonne = true
                    } label: {
                        Label("Neue Kolonne hinzufügen", systemImage: "plus.circle.fill")
                    }
                }
                Section("Adresse") {
                    TextField("Straße", text: $newStrasse)
                    TextField("Hausnummer (z. B. 22A)", text: $newHausnummer)
                    TextField("Postleitzahl", text: $newPostleitzahl)
                        .keyboardType(.numberPad)
                    TextField("Ort", text: $newOrt)
                }
                Section("Auftrag") {
                    TextField("NVT-Nummer", text: $newNvtNummer)
                    Picker("Verbund Größe", selection: $newVerbundGroesse) {
                        Text("—").tag("")
                        ForEach(ProjectOptions.verbundGroessen, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Verbund Farbe", selection: $newVerbundFarbe) {
                        Text("—").tag("")
                        ForEach(ProjectOptions.verbundFarben, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Pipes Farbe 1", selection: $newPipesFarbe1) {
                        Text("—").tag("")
                        ForEach(ProjectOptions.pipesFarben, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Pipes Farbe 2", selection: $newPipesFarbe2) {
                        Text("—").tag("")
                        ForEach(ProjectOptions.pipesFarben, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Auftrag abgeschlossen", isOn: $newAuftragAbgeschlossen)
                    DatePicker("Termin", selection: Binding(get: { newTermin ?? Date() }, set: { newTermin = $0 }), displayedComponents: [.date, .hourAndMinute])
                    TextField("Google Drive Link", text: $newGoogleDriveLink)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Notizen") {
                    TextField("Notizen", text: $newNotizen, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Neues Projekt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        showNewProject = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        createProject()
                    }
                    .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var addKolonneSheetForNewProject: some View {
        NavigationStack {
            Form {
                TextField("Name der Kolonne", text: $newKolonneName)
                Button("Hinzufügen") {
                    let t = newKolonneName.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    if !kolonnenList.contains(t) {
                        kolonnenList.append(t)
                        storage.saveKolonnen(kolonnenList)
                    }
                    newKolonne = t
                    newKolonneName = ""
                    showAddKolonne = false
                }
                .disabled(newKolonneName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .navigationTitle("Neue Kolonne")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { newKolonneName = "" }
        }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let project = Project(
            name: name,
            measurements: [],
            createdAt: Date(),
            strasse: newStrasse.isEmpty ? nil : newStrasse.trimmingCharacters(in: .whitespaces),
            hausnummer: newHausnummer.isEmpty ? nil : newHausnummer.trimmingCharacters(in: .whitespaces),
            postleitzahl: newPostleitzahl.isEmpty ? nil : newPostleitzahl.trimmingCharacters(in: .whitespaces),
            ort: newOrt.isEmpty ? nil : newOrt.trimmingCharacters(in: .whitespaces),
            nvtNummer: newNvtNummer.isEmpty ? nil : newNvtNummer.trimmingCharacters(in: .whitespaces),
            kolonne: newKolonne.isEmpty ? nil : newKolonne,
            verbundGroesse: newVerbundGroesse.isEmpty ? nil : newVerbundGroesse,
            verbundFarbe: newVerbundFarbe.isEmpty ? nil : newVerbundFarbe,
            pipesFarbe1: newPipesFarbe1.isEmpty ? nil : newPipesFarbe1,
            pipesFarbe2: newPipesFarbe2.isEmpty ? nil : newPipesFarbe2,
            auftragAbgeschlossen: newAuftragAbgeschlossen,
            termin: newTermin,
            googleDriveLink: newGoogleDriveLink.isEmpty ? nil : newGoogleDriveLink.trimmingCharacters(in: .whitespaces),
            notizen: newNotizen.isEmpty ? nil : newNotizen.trimmingCharacters(in: .whitespaces),
            kundeName: newKundeName.isEmpty ? nil : newKundeName.trimmingCharacters(in: .whitespaces),
            kundeTelefon: newKundeTelefon.isEmpty ? nil : newKundeTelefon.trimmingCharacters(in: .whitespaces),
            kundeEmail: newKundeEmail.isEmpty ? nil : newKundeEmail.trimmingCharacters(in: .whitespaces)
        )
        viewModel.addProject(project)
        showNewProject = false
    }

    @ViewBuilder
    private func verbundColorBoxes(project: Project) -> some View {
        if let (c1, c2) = ProjectOptions.verbundColors(for: project.verbundFarbe) {
            HStack(spacing: 2) {
                colorBox(c1)
                colorBox(c2)
            }
        }
    }

    @ViewBuilder
    private func pipesColorBoxes(project: Project) -> some View {
        let f1 = project.pipesFarbe1 ?? project.pipesFarbe
        let f2 = project.pipesFarbe2
        if let c1 = ProjectOptions.pipesColor(for: f1) {
            HStack(spacing: 2) {
                colorBox(c1)
                if let c2 = ProjectOptions.pipesColor(for: f2) {
                    colorBox(c2)
                } else {
                    colorBox(c1)
                }
            }
        }
    }

    private func colorBox(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.5), lineWidth: 1))
    }

    /// Öffnet Google Maps mit Navigation zur Projektadresse (Straße, Hausnummer, PLZ, Ort).
    private func openGoogleMapsNavigation(project: Project) {
        var parts: [String] = []
        if let s = project.strasse, !s.isEmpty { parts.append(s) }
        if let h = project.hausnummer, !h.isEmpty { parts.append(h) }
        if let plz = project.postleitzahl, !plz.isEmpty { parts.append(plz) }
        if let o = project.ort, !o.isEmpty { parts.append(o) }
        guard !parts.isEmpty else { return }
        let address = parts.joined(separator: " ")
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    ContentView()
}
