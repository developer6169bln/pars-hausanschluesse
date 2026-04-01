import SwiftUI
import MapKit
import UIKit
import SceneKit
import ImageIO

/// Tabs: Fotos und AR-Messung. 3D-Scan vorübergehend ausgeblendet (Schwerpunkt: reine AR-Messung + Skizze auf Luftbild).
enum ProjectDetailTab: String, CaseIterable {
    case fotos = "Fotos"
    case ar = "AR-Messung"
    case threeD = "3D"
}

struct ProjectDetailView: View {
    @EnvironmentObject var viewModel: MapViewModel
    let projectId: UUID
    @State private var showAddPhoto = false
    @State private var selectedTab: ProjectDetailTab = .fotos
    /// Share-Sheet nur mit gültiger URL öffnen (vermeidet weißen Bildschirm).
    @State private var sharePDFItem: ShareablePDFItem?
    @State private var showEditProject = false
    @State private var showSignature = false
    @State private var showBauhinderungSignature = false
    @State private var isSyncing = false
    @State private var syncErrorMessage: String?
    @State private var showSyncError = false
    @State private var showSyncSuccess = false
    @State private var shareExportItem: ShareableExportItem?
    @State private var showAssignPhotoToPoint = false
    @State private var showAssignAfterNewPhoto = false
    @State private var pendingAssignPhotoMeasurementId: UUID?

    private let storage = StorageService()
    private var project: Project? {
        viewModel.project(byId: projectId)
    }

    var body: some View {
        Group {
            if let p = project {
                VStack(spacing: 0) {
                    Picker("", selection: $selectedTab) {
                        ForEach(ProjectDetailTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    if selectedTab == .fotos {
                        fotosList(project: p)
                    } else if selectedTab == .ar {
                        ARMeasureView(projectId: projectId)
                            .environmentObject(viewModel)
                    } else {
                        Baugrube3DScanModuleView(projectId: projectId)
                            .environmentObject(viewModel)
                    }
                }
                .navigationTitle(p.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 16) {
                            if selectedTab == .fotos {
                                Button {
                                    showEditProject = true
                                } label: {
                                    Image(systemName: "pencil.circle")
                                }
                                .accessibilityLabel("Projektdaten bearbeiten")
                                Button {
                                    showAddPhoto = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                }
                                .accessibilityLabel("Messung oder Foto für dieses Projekt hinzufügen")
                                Button {
                                    showAssignPhotoToPoint = true
                                } label: {
                                    Image(systemName: "link.badge.plus")
                                }
                                .accessibilityLabel("Foto einem Messpunkt zuweisen")
                            }
                            Button {
                                PDFService.createProjectReport(project: p) { url in
                                    sharePDFItem = ShareablePDFItem(url: url)
                                }
                            } label: {
                                Image(systemName: "doc.richtext")
                            }
                            .accessibilityLabel("Projekt-PDF erstellen und teilen")
                            if p.serverProjectId != nil && !storage.serverBaseURL.isEmpty {
                                Button {
                                    performSync(project: p)
                                } label: {
                                    if isSyncing {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                }
                                .disabled(isSyncing)
                                .accessibilityLabel("Mit Server synchronisieren")
                            }
                        }
                    }
                }
                .onChange(of: selectedTab) { _, newTab in
                    guard newTab == .ar else { return }
                    guard let current = viewModel.project(byId: projectId) else { return }
                    // Fertige Projekte bleiben grün.
                    if current.auftragAbgeschlossen == true {
                        guard current.ampelStatus != "gruen" else { return }
                        var updated = current
                        updated.ampelStatus = "gruen"
                        viewModel.updateProject(updated)
                        syncProjectSilent(project: updated)
                        return
                    }

                    // Arbeitsstart = AR-Messung starten -> Orange setzen.
                    guard current.ampelStatus != "orange" else { return }
                    var updated = current
                    updated.ampelStatus = "orange"
                    viewModel.updateProject(updated)
                    syncProjectSilent(project: updated)
                }
                .alert("Sync-Fehler", isPresented: $showSyncError) {
                    Button("OK", role: .cancel) { showSyncError = false; syncErrorMessage = nil }
                } message: {
                    Text(syncErrorMessage ?? "Unbekannter Fehler")
                }
                .alert("Synchronisiert", isPresented: $showSyncSuccess) {
                    Button("OK", role: .cancel) { showSyncSuccess = false }
                } message: {
                    Text("Projekt wurde auf den Server übertragen. Die Admin-Web-App zeigt nun alle Details, Fotos, AR-Messungen, 3D-Scans sowie Abnahme- und Bauhinderungsdaten.")
                }
                .sheet(isPresented: $showAddPhoto) {
                    AddPhotoSheetView(projectId: projectId) { saved in
                        guard let saved else { return }
                        guard let proj = viewModel.project(byId: projectId) else { return }
                        let hasARPolyline = proj.measurements.contains { m in
                            m.isARMeasurement && (m.polylinePoints?.count ?? 0) >= 2
                        }
                        guard hasARPolyline else { return }
                        pendingAssignPhotoMeasurementId = saved.id
                        DispatchQueue.main.async {
                            showAssignAfterNewPhoto = true
                        }
                    }
                    .environmentObject(viewModel)
                }
                .sheet(isPresented: $showAssignPhotoToPoint) {
                    AssignPhotoToMeasurementPointView(project: p, preselectedPhotoMeasurementId: nil)
                        .environmentObject(viewModel)
                        .id(projectId)
                }
                .sheet(isPresented: $showAssignAfterNewPhoto) {
                    if let p = viewModel.project(byId: projectId),
                       let photoId = pendingAssignPhotoMeasurementId {
                        AssignPhotoToMeasurementPointView(project: p, preselectedPhotoMeasurementId: photoId)
                            .environmentObject(viewModel)
                            .id("\(projectId)-assign-\(photoId)")
                    }
                }
                .onChange(of: showAssignAfterNewPhoto) { _, on in
                    if !on { pendingAssignPhotoMeasurementId = nil }
                }
                .sheet(item: $sharePDFItem) { item in
                    ShareSheet(items: [item.url])
                }
                .sheet(item: $shareExportItem) { item in
                    ShareSheet(items: [item.url])
                }
                .sheet(isPresented: $showEditProject) {
                    if let p = project {
                        EditProjectSheet(project: p) { updated in
                            viewModel.updateProject(updated)
                            showEditProject = false
                            // Beim „fertig“ (oder sonstigen Projektdaten) nicht auf manuellen Sync warten.
                            syncProjectSilent(project: updated)
                        }
                    }
                }
                .sheet(isPresented: $showSignature) {
                    if let p = project {
                        SignatureView { image in
                            let storage = StorageService()
                            if let path = storage.saveSignature(image) {
                                var updated = p
                                updated.abnahmeProtokollUnterschriftPath = path
                                updated.abnahmeProtokollDatum = Date()
                                viewModel.updateProject(updated)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showBauhinderungSignature) {
                    if let p = project {
                        SignatureView { image in
                            let storage = StorageService()
                            if let path = storage.saveSignature(image) {
                                var updated = p
                                var r = updated.bauhinderung ?? BauhinderungReport()
                                r.unterschriftPath = path
                                r.datum = Date()
                                r.ort = updated.ort
                                updated.bauhinderung = r
                                viewModel.updateProject(updated)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Projekt nicht gefunden", systemImage: "folder.badge.questionmark")
            }
        }
    }

    private func fotosList(project p: Project) -> some View {
        // Fallback-Nummerierung für alte Einträge ohne index (nur für Anzeige); getrennt nach Fotos und AR-Messungen.
        let sorted = p.measurements.sorted { $0.date < $1.date }
        let fotoIds = sorted.filter { !$0.isARMeasurement }.map(\.id)
        let arIds = sorted.filter { $0.isARMeasurement }.map(\.id)
        let fotoIndexById: [UUID: Int] = Dictionary(uniqueKeysWithValues: fotoIds.enumerated().map { ($0.element, $0.offset + 1) })
        let arIndexById: [UUID: Int] = Dictionary(uniqueKeysWithValues: arIds.enumerated().map { ($0.element, $0.offset + 1) })
        return VStack(spacing: 0) {
            List {
                Section("Projektdaten") {
                    if let s = p.strasse, !s.isEmpty { LabeledContent("Straße", value: s) }
                    if let h = p.hausnummer, !h.isEmpty { LabeledContent("Hausnummer", value: h) }
                    if let plz = p.postleitzahl, !plz.isEmpty { LabeledContent("Postleitzahl", value: plz) }
                    if let ort = p.ort, !ort.isEmpty { LabeledContent("Ort", value: ort) }
                    if let name = p.kundeName, !name.isEmpty { LabeledContent("Name Kunde", value: name) }
                    if let tel = p.kundeTelefon, !tel.isEmpty { LabeledContent("Telefon Kunde", value: tel) }
                    if let mail = p.kundeEmail, !mail.isEmpty { LabeledContent("E-Mail Kunde", value: mail) }
                    if let nvt = p.nvtNummer, !nvt.isEmpty { LabeledContent("NVT-Nummer", value: nvt) }
                    if let k = p.kolonne, !k.isEmpty { LabeledContent("Kolonne", value: k) }
                    if let vg = p.verbundGroesse, !vg.isEmpty { LabeledContent("Verbund Größe", value: vg) }
                    if let vf = p.verbundFarbe, !vf.isEmpty {
                        HStack {
                            Text("Verbund Farbe").foregroundStyle(.secondary)
                            Spacer()
                            Text(vf).font(.subheadline)
                            verbundColorBoxes(verbundFarbe: vf)
                        }
                    }
                    if p.pipesFarbe1 != nil || p.pipesFarbe2 != nil || (p.pipesFarbe != nil && !(p.pipesFarbe?.isEmpty ?? true)) {
                        HStack {
                            Text("Pipes Farbe").foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 8) {
                                pipesColorText(project: p)
                                pipesColorBoxes(project: p)
                            }
                        }
                    }
                    LabeledContent("Auftrag abgeschlossen", value: (p.auftragAbgeschlossen ?? false) ? "Ja" : "Nein")
                    if let t = p.termin {
                        LabeledContent("Termin", value: t.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let link = p.googleDriveLink, !link.isEmpty {
                        HStack {
                            Text("Google Drive").foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                if let url = URL(string: link) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Text("Ordner öffnen")
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if let n = p.notizen, !n.isEmpty {
                        LabeledContent("Notizen") {
                            Text(n).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Button("Projekt bearbeiten") {
                        showEditProject = true
                    }
                }
                Section("Kunden-Kommunikation") {
                    if let t = p.telefonNotizen, !t.isEmpty {
                        LabeledContent("Telefon-Notizen") {
                            Text(t).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let b = p.kundenBeschwerden, !b.isEmpty {
                        LabeledContent("Beschwerden") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(b).frame(maxWidth: .infinity, alignment: .leading)
                                if let d = p.kundenBeschwerdenUnterschriebenAm {
                                    Text("Vom Kunden bestätigt am \(d.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let t = p.auftragBestaetigtText, !t.isEmpty {
                        LabeledContent("Auftragsbestätigung") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t).frame(maxWidth: .infinity, alignment: .leading)
                                if let d = p.auftragBestaetigtUnterschriebenAm {
                                    Text("Unterschrieben am \(d.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    // Abnahmeprotokoll: Vorschau + Unterschrift + Auswahl + PDF
                    if let path = p.abnahmeProtokollUnterschriftPath {
                        let full = storage.fullPath(forStoredPath: path)
                        if FileManager.default.fileExists(atPath: full),
                           let img = UIImage(contentsOfFile: full) {
                            Text("Abnahmeprotokoll – Unterschrift")
                                .font(.subheadline.bold())
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 120)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.5), lineWidth: 1))
                            if let d = p.abnahmeProtokollDatum {
                                Text("Unterschrieben am \(d.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        showSignature = true
                    } label: {
                        Text(p.abnahmeProtokollUnterschriftPath == nil ? "Abnahmeprotokoll unterschreiben" : "Abnahmeprotokoll erneut unterschreiben")
                    }
                    .buttonStyle(.bordered)

                    // Auswahl (Punkt 1 / Punkt 2) – ohne Buttons-in-Buttons, damit Tap zuverlässig ist.
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Abnahmeprotokoll – Auswahl")
                            .font(.subheadline.bold())

                        let selectionBinding = Binding<Int>(
                            get: {
                                if p.abnahmeOhneMaengel == true { return 1 }
                                if p.abnahmeOhneMaengel == false { return 2 }
                                return 0
                            },
                            set: { newValue in
                                if newValue == 1 {
                                    updateAbnahmeStatus(for: p, ohneMaengel: true)
                                } else if newValue == 2 {
                                    updateAbnahmeStatus(for: p, ohneMaengel: false)
                                } else {
                                    updateAbnahmeStatus(for: p, ohneMaengel: true)
                                }
                            }
                        )

                        Picker("Abnahme", selection: selectionBinding) {
                            Text("—").tag(0)
                            Text("Keine sichtbaren Mängel").tag(1)
                            Text("Mängel festgestellt").tag(2)
                        }
                        .pickerStyle(.segmented)

                        if p.abnahmeOhneMaengel == false {
                            TextField("Mängelbeschreibung", text: Binding(
                                get: { p.abnahmeMaengelText ?? "" },
                                set: { newValue in
                                    updateAbnahmeMaengelText(for: p, text: newValue)
                                }
                            ), axis: .vertical)
                            .lineLimit(3...6)
                        }

                        Button("Abnahmeprotokoll als PDF") {
                            PDFService.createAbnahmeReport(project: p) { url in
                                sharePDFItem = ShareablePDFItem(url: url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(p.abnahmeProtokollUnterschriftPath == nil)
                    }

                    // Bauhindernisanzeige / Baustellenbericht
                    DisclosureGroup("Bauhindernisanzeige / Baustellenbericht") {
                        let report = p.bauhinderung ?? BauhinderungReport()

                        TextField("Projekt- / Ticketnummer", text: Binding(
                            get: { report.ticketNummer ?? "" },
                            set: { setBauhinderung(p, \.ticketNummer, $0) }
                        ))
                        TextField("Netzbetreiber / Auftraggeber", text: Binding(
                            get: { report.netzbetreiber ?? "" },
                            set: { setBauhinderung(p, \.netzbetreiber, $0) }
                        ))
                        TextField("Ausführendes Tiefbauunternehmen", text: Binding(
                            get: { report.tiefbauunternehmen ?? "" },
                            set: { setBauhinderung(p, \.tiefbauunternehmen, $0) }
                        ))

                        DatePicker("Datum des Einsatzes", selection: Binding(
                            get: { report.datumEinsatz ?? Date() },
                            set: { setBauhinderungDate(p, \.datumEinsatz, $0) }
                        ), displayedComponents: [.date])

                        DatePicker("Uhrzeit Ankunft Baustelle", selection: Binding(
                            get: { report.uhrzeitAnkunft ?? Date() },
                            set: { setBauhinderungDate(p, \.uhrzeitAnkunft, $0) }
                        ), displayedComponents: [.hourAndMinute])

                        DatePicker("Uhrzeit Verlassen Baustelle", selection: Binding(
                            get: { report.uhrzeitVerlassen ?? Date() },
                            set: { setBauhinderungDate(p, \.uhrzeitVerlassen, $0) }
                        ), displayedComponents: [.hourAndMinute])

                        TextField("Monteur / Kolonne", text: Binding(
                            get: { report.monteurKolonne ?? (p.kolonne ?? "") },
                            set: { setBauhinderung(p, \.monteurKolonne, $0) }
                        ))

                        Text("Allgemeine Bauhindernisse")
                            .font(.subheadline.bold())

                        Toggle("Kunde / Eigentümer nicht anwesend", isOn: Binding(
                            get: { report.kundeNichtAnwesend },
                            set: { setBauhinderungBool(p, \.kundeNichtAnwesend, $0) }
                        ))
                        Toggle("Kein Zugang zum Grundstück möglich", isOn: Binding(
                            get: { report.keinZugangGrundstueck },
                            set: { setBauhinderungBool(p, \.keinZugangGrundstueck, $0) }
                        ))
                        Toggle("Kein Zugang zum Gebäude / Keller / Hausanschlussraum", isOn: Binding(
                            get: { report.keinZugangGebaeude },
                            set: { setBauhinderungBool(p, \.keinZugangGebaeude, $0) }
                        ))
                        Toggle("Zustimmung zur Hauseinführung nicht erteilt", isOn: Binding(
                            get: { report.zustimmungHauseinfuehrungNichtErteilt },
                            set: { setBauhinderungBool(p, \.zustimmungHauseinfuehrungNichtErteilt, $0) }
                        ))
                        Toggle("Grundstück/Arbeitsbereich blockiert", isOn: Binding(
                            get: { report.arbeitsbereichBlockiert },
                            set: { setBauhinderungBool(p, \.arbeitsbereichBlockiert, $0) }
                        ))
                        Toggle("Oberfläche nicht zur Öffnung freigegeben", isOn: Binding(
                            get: { report.oberflaecheNichtFreigegeben },
                            set: { setBauhinderungBool(p, \.oberflaecheNichtFreigegeben, $0) }
                        ))
                        Toggle("Vorhandene Versorgungsleitungen verhindern Arbeiten", isOn: Binding(
                            get: { report.versorgungsleitungenVerhindern },
                            set: { setBauhinderungBool(p, \.versorgungsleitungenVerhindern, $0) }
                        ))
                        Toggle("Leerrohr / Anschlusspunkt nicht auffindbar oder beschädigt", isOn: Binding(
                            get: { report.leerrohrNichtAuffindbarOderBeschaedigt },
                            set: { setBauhinderungBool(p, \.leerrohrNichtAuffindbarOderBeschaedigt, $0) }
                        ))
                        Toggle("Sicherheitsrisiko auf der Baustelle", isOn: Binding(
                            get: { report.sicherheitsrisiko },
                            set: { setBauhinderungBool(p, \.sicherheitsrisiko, $0) }
                        ))
                        Toggle("Witterungsbedingte Bauhindernisse", isOn: Binding(
                            get: { report.witterung },
                            set: { setBauhinderungBool(p, \.witterung, $0) }
                        ))

                        Text("Technische Bauhindernisse")
                            .font(.subheadline.bold())

                        Toggle("Anschlusspunkt nicht auffindbar (Verbund öffentl. Bereich)", isOn: Binding(
                            get: { report.anschlusspunktNichtAuffindbar },
                            set: { setBauhinderungBool(p, \.anschlusspunktNichtAuffindbar, $0) }
                        ))
                        Toggle("Freilaufende Tiere verhinderten Arbeiten", isOn: Binding(
                            get: { report.tiereFreilaufend },
                            set: { setBauhinderungBool(p, \.tiereFreilaufend, $0) }
                        ))
                        Toggle("Kunde verweigerte Sichern der Tiere", isOn: Binding(
                            get: { report.tiereNichtGesichert },
                            set: { setBauhinderungBool(p, \.tiereNichtGesichert, $0) }
                        ))

                        TextField("Beschreibung des Bauhindernisses", text: Binding(
                            get: { report.beschreibungBauhindernis ?? "" },
                            set: { setBauhinderung(p, \.beschreibungBauhindernis, $0) }
                        ), axis: .vertical)
                        .lineLimit(3...6)

                        Text("Dokumentation")
                            .font(.subheadline.bold())
                        Toggle("Fotodokumentation erstellt", isOn: Binding(
                            get: { report.fotoDokuErstellt },
                            set: { setBauhinderungBool(p, \.fotoDokuErstellt, $0) }
                        ))
                        Toggle("Kunde / Eigentümer vor Ort informiert", isOn: Binding(
                            get: { report.kundeVorOrtInformiert },
                            set: { setBauhinderungBool(p, \.kundeVorOrtInformiert, $0) }
                        ))
                        Toggle("Kunde telefonisch kontaktiert", isOn: Binding(
                            get: { report.kundeTelefonischKontaktiert },
                            set: { setBauhinderungBool(p, \.kundeTelefonischKontaktiert, $0) }
                        ))
                        Picker("Ergebnis des Telefonats", selection: Binding(
                            get: { report.telefonErgebnis },
                            set: { setBauhinderungTelefonErgebnis(p, $0) }
                        )) {
                            ForEach(BauhinderungReport.TelefonErgebnis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        DatePicker("Uhrzeit des Anrufes", selection: Binding(
                            get: { report.uhrzeitAnruf ?? Date() },
                            set: { setBauhinderungDate(p, \.uhrzeitAnruf, $0) }
                        ), displayedComponents: [.hourAndMinute])

                        Text("Ergebnis / Status der Baustelle")
                            .font(.subheadline.bold())
                        Toggle("Arbeiten konnten nicht begonnen werden", isOn: Binding(
                            get: { report.arbeitenNichtBegonnen },
                            set: { setBauhinderungBool(p, \.arbeitenNichtBegonnen, $0) }
                        ))
                        Toggle("Arbeiten mussten unterbrochen werden", isOn: Binding(
                            get: { report.arbeitenUnterbrochen },
                            set: { setBauhinderungBool(p, \.arbeitenUnterbrochen, $0) }
                        ))
                        Toggle("Hausanschluss teilweise hergestellt", isOn: Binding(
                            get: { report.hausanschlussTeilweise },
                            set: { setBauhinderungBool(p, \.hausanschlussTeilweise, $0) }
                        ))
                        Toggle("Weitere Klärung durch Netzbetreiber / Bauleitung erforderlich", isOn: Binding(
                            get: { report.weitereKlaerungNoetig },
                            set: { setBauhinderungBool(p, \.weitereKlaerungNoetig, $0) }
                        ))
                        Toggle("Neuer Termin erforderlich", isOn: Binding(
                            get: { report.neuerTerminNoetig },
                            set: { setBauhinderungBool(p, \.neuerTerminNoetig, $0) }
                        ))

                        TextField("Hinweise für Auftraggeber / Bauleitung", text: Binding(
                            get: { report.hinweiseAuftraggeber ?? "" },
                            set: { setBauhinderung(p, \.hinweiseAuftraggeber, $0) }
                        ), axis: .vertical)
                        .lineLimit(3...6)

                        TextField("Name Monteur / Bauleiter", text: Binding(
                            get: { report.nameMonteurBauleiter ?? "" },
                            set: { setBauhinderung(p, \.nameMonteurBauleiter, $0) }
                        ))

                        Button(report.unterschriftPath == nil ? "Bauhinderung unterschreiben" : "Bauhinderung erneut unterschreiben") {
                            showBauhinderungSignature = true
                        }
                        .buttonStyle(.bordered)

                        Button("Bauhinderungsbericht als PDF") {
                            PDFService.createBauhinderungReport(project: p) { url in
                                sharePDFItem = ShareablePDFItem(url: url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(report.unterschriftPath == nil)
                    }
                }
                Section {
                    HStack {
                        Text("Gesamtlänge")
                            .font(.headline)
                        Spacer()
                        if p.totalMeters > 0 {
                            Text(String(format: "%.2f m", p.totalMeters))
                                .foregroundStyle(.secondary)
                        }
                        Text("\(Int(p.totalLength)) px")
                            .foregroundStyle(.secondary)
                    }
                    Text("\(p.measurements.count) Foto(s), Messungen addiert")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Fotos & Messungen") {
                    ForEach(Array(p.measurements.enumerated()), id: \.element.id) { _, m in
                        NavigationLink {
                            MeasurementDetailView(projectId: projectId, measurement: m)
                                .environmentObject(viewModel)
                        } label: {
                            HStack {
                                thumbnail(for: m)
                                VStack(alignment: .leading, spacing: 2) {
                                    let prefix = titlePrefix(for: m, fotoIndexById: fotoIndexById, arIndexById: arIndexById)
                                    Text(prefix + " · " + (m.address.isEmpty ? "Ohne Adresse" : m.address))
                                        .lineLimit(1)
                                    Text((m.referenceMeters != nil ? String(format: "%.2f m", m.referenceMeters!) : "\(Int(m.totalDistance)) px") + " · " + m.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if m.isARMeasurement {
                                        let ob = m.oberflaeche ?? m.oberflaecheSonstige ?? ""
                                        let ver = m.verlegeart ?? m.verlegeartSonstige ?? ""
                                        if !ob.isEmpty || !ver.isEmpty {
                                            Text([ob.isEmpty ? nil : "Oberfläche: \(ob)", ver.isEmpty ? nil : "Verlegeart: \(ver)"].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                        .listRowSeparator(.visible)
                    }
                    .onDelete { indexSet in
                        let idsToDelete = indexSet.compactMap { idx -> UUID? in
                            guard idx < p.measurements.count else { return nil }
                            return p.measurements[idx].id
                        }
                        for id in idsToDelete {
                            viewModel.deleteMeasurement(projectId: projectId, measurementId: id)
                        }
                    }
                }

                Section("Export (CAD / GIS)") {
                    let coords = ExportService.routeCoordinates(for: p)
                    if coords.count >= 2 {
                        Button("Als GeoJSON exportieren") {
                            if let url = ExportService.writeGeoJSONToTemp(project: p) {
                                shareExportItem = ShareableExportItem(url: url)
                            }
                        }
                        .disabled(coords.isEmpty)
                        Button("Als DXF exportieren") {
                            if let url = ExportService.writeDXFToTemp(project: p) {
                                shareExportItem = ShareableExportItem(url: url)
                            }
                        }
                        .disabled(coords.isEmpty)
                    } else {
                        Text("Mindestens 2 Punkte (Route) nötig für Export.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // Karte unten entfernt (Platz für Inhalte)
        }
    }

    private func titlePrefix(for m: Measurement,
                             fotoIndexById: [UUID: Int],
                             arIndexById: [UUID: Int]) -> String {
        let fotoIndex = fotoIndexById[m.id]
        let arIndex = arIndexById[m.id]
        if m.isARMeasurement, let n = arIndex {
            return "Messung \(n)"
        } else if let n = fotoIndex {
            return "Foto \(n)"
        } else if let n = m.index {
            return m.isARMeasurement ? "Messung \(n)" : "Foto \(n)"
        } else {
            return m.isARMeasurement ? "Messung" : "Foto"
        }
    }

    private func performSync(project: Project) {
        isSyncing = true
        syncErrorMessage = nil
        Task {
            do {
                let synced = try await ProjectSyncService.syncOrCreate(project: project, storage: storage, serverBaseURL: storage.serverBaseURL)
                // Falls es vorher ein lokales Projekt war, haben wir jetzt eine serverProjectId.
                await MainActor.run {
                    viewModel.updateProject(synced)
                }
                await MainActor.run {
                    isSyncing = false
                    showSyncSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    syncErrorMessage = error.localizedDescription
                    showSyncError = true
                }
            }
        }
    }

    /// Synchronisiert im Hintergrund, ohne den „Sync-Ok“-Alert auszulösen.
    private func syncProjectSilent(project: Project) {
        guard !isSyncing else { return }
        guard !storage.serverBaseURL.isEmpty else { return }
        isSyncing = true
        Task {
            do {
                let synced = try await ProjectSyncService.syncOrCreate(project: project, storage: storage, serverBaseURL: storage.serverBaseURL)
                await MainActor.run {
                    viewModel.updateProject(synced)
                }
            } catch {
                // Silent: Ampel-Status ist „Nice to have“; bei Fehler bleibt er lokal.
            }
            await MainActor.run { isSyncing = false }
        }
    }

    private func updateAbnahmeStatus(for project: Project, ohneMaengel: Bool) {
        var updated = project
        updated.abnahmeOhneMaengel = ohneMaengel
        if ohneMaengel {
            updated.abnahmeMaengelText = nil
        }
        viewModel.updateProject(updated)
    }

    private func updateAbnahmeMaengelText(for project: Project, text: String) {
        var updated = project
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.abnahmeMaengelText = trimmed.isEmpty ? nil : trimmed
        updated.abnahmeOhneMaengel = false
        viewModel.updateProject(updated)
    }

    private func updateBauhinderung(_ project: Project, mutate: (inout BauhinderungReport) -> Void) {
        var updated = project
        var r = updated.bauhinderung ?? BauhinderungReport()
        mutate(&r)
        updated.bauhinderung = r
        viewModel.updateProject(updated)
    }

    private func setBauhinderung(_ project: Project, _ keyPath: WritableKeyPath<BauhinderungReport, String?>, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        updateBauhinderung(project) { $0[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed }
    }

    private func setBauhinderungBool(_ project: Project, _ keyPath: WritableKeyPath<BauhinderungReport, Bool>, _ value: Bool) {
        updateBauhinderung(project) { $0[keyPath: keyPath] = value }
    }

    private func setBauhinderungDate(_ project: Project, _ keyPath: WritableKeyPath<BauhinderungReport, Date?>, _ value: Date) {
        updateBauhinderung(project) { $0[keyPath: keyPath] = value }
    }

    private func setBauhinderungTelefonErgebnis(_ project: Project, _ value: BauhinderungReport.TelefonErgebnis) {
        updateBauhinderung(project) { $0.telefonErgebnis = value }
    }

    @ViewBuilder
    private func verbundColorBoxes(verbundFarbe: String) -> some View {
        if let (c1, c2) = ProjectOptions.verbundColors(for: verbundFarbe) {
            HStack(spacing: 4) {
                colorBox(c1)
                colorBox(c2)
            }
        }
    }

    /// Farbnamen als Text nebeneinander (z. B. "rot, blau").
    private func pipesColorText(project: Project) -> some View {
        let f1 = project.pipesFarbe1 ?? project.pipesFarbe
        let f2 = project.pipesFarbe2
        let text: String
        if let n1 = f1, !n1.isEmpty {
            if let n2 = f2, !n2.isEmpty {
                text = "\(n1), \(n2)"
            } else {
                text = n1
            }
        } else {
            text = ""
        }
        return Text(text)
            .font(.subheadline)
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func pipesColorBoxes(project: Project) -> some View {
        let f1 = project.pipesFarbe1 ?? project.pipesFarbe
        let f2 = project.pipesFarbe2
        if let c1 = ProjectOptions.pipesColor(for: f1) {
            HStack(spacing: 4) {
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
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: 22, height: 22)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.5), lineWidth: 1))
    }

    @ViewBuilder
    private func thumbnail(for m: Measurement) -> some View {
        let path = storage.fullPath(forStoredPath: m.imagePath)
        Group {
            if FileManager.default.fileExists(atPath: path),
               let img = UIImage(contentsOfFile: path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.3))
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
    }

    /// Berechnet die Polyline-Punkte für das Projekt:
    /// Bei Polylinien-Messung: alle Stützpunkte; sonst 1A -> 2A -> ... -> (N-1)A -> N B
    private func projectRoute(for project: Project) -> [CLLocationCoordinate2D] {
        let sorted = project.measurements.sorted { ($0.index ?? 0, $0.date) < ($1.index ?? 0, $1.date) }
        var coords: [CLLocationCoordinate2D] = []
        for (i, m) in sorted.enumerated() {
            if let poly = m.polylinePoints, !poly.isEmpty {
                for p in poly {
                    coords.append(CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude))
                }
            } else {
                if i == sorted.count - 1 {
                    if let lat = m.endLatitude, let lon = m.endLongitude {
                        coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    } else {
                        coords.append(CLLocationCoordinate2D(latitude: m.latitude, longitude: m.longitude))
                    }
                } else {
                    if let lat = m.startLatitude, let lon = m.startLongitude {
                        coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    } else {
                        coords.append(CLLocationCoordinate2D(latitude: m.latitude, longitude: m.longitude))
                    }
                }
            }
        }
        return coords
    }
}

// MARK: - Foto -> Messpunkt zuweisen (Wizard)

private struct AssignPhotoToMeasurementPointView: View {
    @EnvironmentObject var viewModel: MapViewModel
    @Environment(\.dismiss) private var dismiss
    let project: Project
    /// Nach neuem Foto: dieses Foto vorauswählen (Schritt 3).
    var preselectedPhotoMeasurementId: UUID? = nil

    private let storage = StorageService()

    @State private var selectedMeasurementId: UUID?
    @State private var selectedPointIndex: Int?
    @State private var selectedPhotoMeasurementId: UUID?

    @State private var showAssignError = false
    @State private var assignErrorMessage: String = ""

    private var effectiveProject: Project {
        viewModel.project(byId: project.id) ?? project
    }

    private var arMeasurements: [Measurement] {
        effectiveProject.measurements.filter { m in
            m.isARMeasurement && (pointCount(for: m) >= 2)
        }
    }

    private var normalPhotos: [Measurement] {
        effectiveProject.measurements.filter { m in
            !m.isARMeasurement && !m.imagePath.isEmpty
        }
    }

    private var selectedARMeasurement: Measurement? {
        guard let id = selectedMeasurementId else { return nil }
        return arMeasurements.first { $0.id == id }
    }

    private var selectedPhotoMeasurement: Measurement? {
        guard let id = selectedPhotoMeasurementId else { return nil }
        return normalPhotos.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                // Schritt 1: Messung wählen
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1) Messung auswählen")
                            .font(.headline)
                        if arMeasurements.isEmpty {
                            Text("Keine AR‑Polylinienmessungen vorhanden.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("AR‑Messung", selection: $selectedMeasurementId) {
                                Text("—").tag(Optional<UUID>.none)
                                ForEach(arMeasurements) { m in
                                    let idx = m.index ?? 0
                                    Text("Messung \(idx == 0 ? "" : "\(idx)")").tag(Optional(m.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }

                // Schritt 2: Punkt auf Karte wählen (Zoom/Pan)
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("2) Messpunkt auf Karte auswählen")
                            .font(.headline)

                        if let m = selectedARMeasurement {
                            let names = pointNames(for: m)
                            if names.count >= 2 {
                                Text("Punkte")
                                    .font(.subheadline.bold())
                                ScrollView {
                                    LazyVStack(spacing: 8) {
                                        ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                                            Button {
                                                selectedPointIndex = i
                                            } label: {
                                                HStack {
                                                    Text(name)
                                                        .font(.headline)
                                                    Spacer()
                                                    if selectedPointIndex == i {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundStyle(.green)
                                                    }
                                                }
                                                .padding(.vertical, 10)
                                                .padding(.horizontal, 12)
                                                .background(selectedPointIndex == i ? Color.green.opacity(0.18) : Color.gray.opacity(0.08))
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .frame(maxHeight: 220)

                                if let idx = selectedPointIndex {
                                    Text("Ausgewählt: \(pointLabel(idx))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Punkt antippen für Zuordnung.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Diese Messung hat keine nutzbaren Messpunkte.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Bitte zuerst eine AR‑Messung auswählen.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Schritt 3: Foto wählen
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("3) Foto auswählen")
                            .font(.headline)
                        if normalPhotos.isEmpty {
                            Text("Keine normalen Fotos im Projekt vorhanden.")
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 10) {
                                    ForEach(normalPhotos) { ph in
                                        let isSel = selectedPhotoMeasurementId == ph.id
                                        Button {
                                            selectedPhotoMeasurementId = ph.id
                                        } label: {
                                            VStack(spacing: 6) {
                                                thumbnailView(path: ph.imagePath)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 10)
                                                            .stroke(isSel ? Color.green : Color.clear, lineWidth: 3)
                                                    )
                                                Text(ph.index.map { "Foto \($0)" } ?? "Foto")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Foto zuweisen")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let pre = preselectedPhotoMeasurementId {
                    selectedPhotoMeasurementId = pre
                    if arMeasurements.count == 1 {
                        selectedMeasurementId = arMeasurements.first?.id
                    }
                } else {
                    selectedMeasurementId = nil
                    selectedPhotoMeasurementId = nil
                    selectedPointIndex = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zuweisen") { assign() }
                        .disabled(!canAssign)
                }
            }
            .alert("Zuordnung nicht möglich", isPresented: $showAssignError) {
                Button("OK") { showAssignError = false }
            } message: {
                Text(assignErrorMessage)
            }
        }
    }

    private var canAssign: Bool {
        selectedARMeasurement != nil && selectedPointIndex != nil && selectedPhotoMeasurement != nil
    }

    private func pointLabel(_ index: Int) -> String {
        if index >= 0 && index < 26 { return String(Unicode.Scalar(65 + index)!) }
        return "\(index + 1)"
    }

    private func pointCount(for measurement: Measurement) -> Int {
        if let poly = measurement.polylinePoints, poly.count >= 2 { return poly.count }
        let gpsCount = measurement.orderedGPSPoints.count
        if gpsCount >= 2 { return gpsCount }
        if let seg = measurement.polylineSegmentMeters, !seg.isEmpty { return seg.count + 1 }
        return 0
    }

    private func pointNames(for measurement: Measurement) -> [String] {
        let n = pointCount(for: measurement)
        guard n >= 2 else { return [] }
        return (0..<n).map { pointLabel($0) }
    }

    @ViewBuilder
    private func thumbnailView(path: String) -> some View {
        let full = storage.fullPath(forStoredPath: path)
        if FileManager.default.fileExists(atPath: full),
           let img = loadThumbnail(at: full, maxPixel: 220) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.gray.opacity(0.2))
                .frame(width: 90, height: 90)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }

    /// Speicherfreundliches Thumbnail (Downsampling statt Vollbild-Decoding).
    private func loadThumbnail(at fullPath: String, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: fullPath) as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func assign() {
        let proj = effectiveProject
        guard let ar = selectedARMeasurement else {
            assignErrorMessage = "Keine AR‑Messung ausgewählt."
            showAssignError = true
            return
        }
        guard let photo = selectedPhotoMeasurement else {
            assignErrorMessage = "Kein Foto ausgewählt."
            showAssignError = true
            return
        }
        guard let pointIndex = selectedPointIndex else {
            assignErrorMessage = "Kein Messpunkt ausgewählt."
            showAssignError = true
            return
        }
        let count = pointCount(for: ar)
        guard count >= 2 else {
            assignErrorMessage = "AR‑Messung hat keine gültigen Messpunkte."
            showAssignError = true
            return
        }
        guard pointIndex < count else {
            assignErrorMessage = "Ungültiger Messpunkt."
            showAssignError = true
            return
        }

        let photoFull = storage.fullPath(forStoredPath: photo.imagePath)
        guard FileManager.default.fileExists(atPath: photoFull) else {
            assignErrorMessage = "Foto konnte nicht geladen werden (Datei fehlt)."
            showAssignError = true
            return
        }

        // Re-Assign global: alte Zuordnung dieses Fotos in allen AR-Messungen entfernen.
        removeOldAssignmentsForPhoto(photo, in: proj)

        var updated = ar
        var list = updated.polylinePointPhotos ?? []
        // Zusätzlich lokal absichern.
        list.removeAll { pp in
            pp.sourceMeasurementId == photo.id || pp.imagePath == photo.imagePath
        }
        list.append(
            PolylinePointPhoto(
                pointIndex: pointIndex,
                imagePath: photo.imagePath,
                date: Date(),
                sourceMeasurementId: photo.id
            )
        )
        updated.polylinePointPhotos = list

        viewModel.updateMeasurement(projectId: proj.id, updated)

        // Foto-Messung in der Liste nach Messpunkt benennen (Anzeige: „Foto n · …“).
        var renamedPhoto = photo
        renamedPhoto.address = "Messpunkt \(pointLabel(pointIndex))"
        viewModel.updateMeasurement(projectId: proj.id, renamedPhoto)

        dismiss()
    }

    private func removeOldAssignmentsForPhoto(_ photo: Measurement, in project: Project) {
        guard let fresh = viewModel.project(byId: project.id) else { return }
        for m in fresh.measurements where m.isARMeasurement {
            guard var list = m.polylinePointPhotos, !list.isEmpty else { continue }
            let before = list.count
            list.removeAll { pp in
                pp.sourceMeasurementId == photo.id || pp.imagePath == photo.imagePath
            }
            guard list.count != before else { continue }
            var updated = m
            updated.polylinePointPhotos = list.isEmpty ? nil : list
            viewModel.updateMeasurement(projectId: project.id, updated)
        }
    }

    // Label-Overlay ist nicht mehr nötig; Punktname kommt aus der Zuordnung im Bericht.
}

// MARK: - Kleine Projektkarte mit gespeicherter Route

struct ProjectMiniMapView: View {
    let route: [CLLocationCoordinate2D]
    let projectId: UUID
    @EnvironmentObject var viewModel: MapViewModel
    @State private var region: MKCoordinateRegion = .init()
    @State private var isSavingSnapshot = false

    var body: some View {
        VStack(spacing: 8) {
            Map {
                if route.count >= 2 {
                    let polyline = MKPolyline(coordinates: route, count: route.count)
                    MapPolyline(polyline)
                        .stroke(.blue, lineWidth: 3)
                }
                if let first = route.first {
                    Annotation("Start", coordinate: first) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                if let last = route.last {
                    Annotation("Ende", coordinate: last) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear {
                if let first = route.first {
                    region = MKCoordinateRegion(center: first,
                                                span: MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0015))
                }
            }

            HStack {
                Spacer()
                Button {
                    createAndSaveSnapshot()
                } label: {
                    if isSavingSnapshot {
                        ProgressView()
                    } else {
                        Label("Kartenfoto im Projekt speichern", systemImage: "square.and.arrow.down")
                    }
                }
                .font(.footnote)
            }
        }
        .padding([.horizontal, .bottom])
    }

    private func createAndSaveSnapshot() {
        guard !route.isEmpty else { return }
        isSavingSnapshot = true

        // Projekt vorab holen, um Gesamtlänge für Text zu kennen
        guard let project = viewModel.project(byId: projectId) else {
            isSavingSnapshot = false
            return
        }

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 600, height: 400)
        options.showsBuildings = true

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { result, error in
            DispatchQueue.main.async {
                isSavingSnapshot = false
            }
            guard let snap = result, error == nil else { return }

            let baseImage = snap.image
            // Polyline + Start/Ende + Text ins Bild rendern
            let renderer = UIGraphicsImageRenderer(size: baseImage.size)
            let rendered = renderer.image { ctx in
                baseImage.draw(at: .zero)
                let cg = ctx.cgContext

                // Projektname oben
                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor.white,
                    .strokeColor: UIColor.black,
                    .strokeWidth: -2
                ]
                (project.name as NSString).draw(in: CGRect(x: 12, y: 12, width: baseImage.size.width - 24, height: 28), withAttributes: nameAttrs)

                // Route-Linie
                if route.count >= 2 {
                    let points = route.map { snap.point(for: $0) }
                    cg.setStrokeColor(UIColor.systemBlue.cgColor)
                    cg.setLineWidth(4)
                    cg.addLines(between: points)
                    cg.strokePath()
                }
                // Start-/End-Markierungen
                if let first = route.first {
                    let p = snap.point(for: first)
                    cg.setFillColor(UIColor.systemGreen.cgColor)
                    cg.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
                }
                if let last = route.last {
                    let p = snap.point(for: last)
                    cg.setFillColor(UIColor.systemRed.cgColor)
                    cg.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
                }
                // Gesamtlänge unten links
                let text = String(format: "Gesamtlänge: %.2f m (%.0f px)", project.totalMeters, project.totalLength)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 18),
                    .foregroundColor: UIColor.white,
                    .strokeColor: UIColor.black,
                    .strokeWidth: -2
                ]
                let size = (text as NSString).size(withAttributes: attrs)
                let margin: CGFloat = 12
                let rect = CGRect(
                    x: margin,
                    y: baseImage.size.height - size.height - margin,
                    width: size.width,
                    height: size.height
                )
                (text as NSString).draw(in: rect, withAttributes: attrs)
            }

            let storage = StorageService()
            let overlay = StorageService.PhotoOverlayInfo(
                strasse: project.strasse,
                hausnummer: project.hausnummer,
                nvtNummer: project.nvtNummer,
                date: Date()
            )
            guard let path = storage.saveImage(rendered, projectName: project.name, overlay: overlay) else { return }

            // Als eigenes "Kartenfoto" im Projekt ablegen (kein AR, keine Messpunkte).
            DispatchQueue.main.async {
                guard let currentProject = viewModel.project(byId: projectId) else { return }
                let nextIndex = currentProject.measurements.count + 1
                let start = route.first
                let end = route.last
                var m = Measurement(
                    id: UUID(),
                    imagePath: path,
                    latitude: start?.latitude ?? 0,
                    longitude: start?.longitude ?? 0,
                    address: "Kartenfoto (Route)",
                    points: [],
                    totalDistance: 0,
                    referenceMeters: nil,
                    index: nextIndex,
                    startLatitude: start?.latitude,
                    startLongitude: start?.longitude,
                    endLatitude: end?.latitude,
                    endLongitude: end?.longitude,
                    isARMeasurement: false,
                    date: Date()
                )
                // explizit keine Polyline-Punkte; Route ist schon im Bild eingezeichnet
                viewModel.addMeasurement(toProjectId: projectId, m)
            }
        }
    }
}

/// Bearbeiten der erweiterten Projektdaten.
struct EditProjectSheet: View {
    let project: Project
    var onSave: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var strasse: String = ""
    @State private var hausnummer: String = ""
    @State private var postleitzahl: String = ""
    @State private var ort: String = ""
    @State private var nvtNummer: String = ""
    @State private var verbundGroesse: String = ""
    @State private var verbundFarbe: String = ""
    @State private var pipesFarbe1: String = ""
    @State private var pipesFarbe2: String = ""
    @State private var auftragAbgeschlossen: Bool = false
    @State private var termin: Date?
    @State private var googleDriveLink: String = ""
    @State private var notizen: String = ""
    @State private var kolonne: String = ""
    @State private var kolonnenList: [String] = []
    @State private var showAddKolonne = false
    @State private var newKolonneName = ""
    @State private var telefonNotizen: String = ""
    @State private var kundenBeschwerden: String = ""
    @State private var kundenBeschwerdenUnterschriebenAm: Date?
    @State private var auftragBestaetigtText: String = ""
    @State private var auftragBestaetigtUnterschriebenAm: Date?
    @State private var abnahmeProtokollUnterschriftPath: String?
    @State private var abnahmeProtokollDatum: Date?
    @State private var kundeName: String = ""
    @State private var kundeTelefon: String = ""
    @State private var kundeEmail: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Grunddaten") {
                    TextField("Projektname", text: $name)
                    TextField("Name Kunde", text: $kundeName)
                    TextField("Telefon Kunde", text: $kundeTelefon)
                        .keyboardType(.phonePad)
                    TextField("E-Mail Kunde", text: $kundeEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Kolonne") {
                    Picker("Kolonne", selection: $kolonne) {
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
                    TextField("Straße", text: $strasse)
                    TextField("Hausnummer (z. B. 22A)", text: $hausnummer)
                    TextField("Postleitzahl", text: $postleitzahl)
                        .keyboardType(.numberPad)
                    TextField("Ort", text: $ort)
                }
                Section("Auftrag") {
                    TextField("NVT-Nummer", text: $nvtNummer)
                    Picker("Verbund Größe", selection: $verbundGroesse) {
                        Text("—").tag("")
                        ForEach(ProjectOptions.verbundGroessen, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Verbund Farbe", selection: $verbundFarbe) {
                        Text("—").tag("")
                        ForEach(ProjectOptions.verbundFarben, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Pipes Farbe 1", selection: $pipesFarbe1) {
                        Text("—").tag("")
                        ForEach(ProjectOptions.pipesFarben, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Pipes Farbe 2", selection: $pipesFarbe2) {
                        Text("—").tag("")
                        ForEach(ProjectOptions.pipesFarben, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Auftrag abgeschlossen", isOn: $auftragAbgeschlossen)
                    DatePicker("Termin", selection: Binding(get: { termin ?? Date() }, set: { termin = $0 }), displayedComponents: [.date, .hourAndMinute])
                    TextField("Google Drive Link", text: $googleDriveLink)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Notizen") {
                    TextField("Notizen", text: $notizen, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Kunden-Kommunikation") {
                    TextField("Telefon-Notizen", text: $telefonNotizen, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Beschwerden", text: $kundenBeschwerden, axis: .vertical)
                        .lineLimit(2...4)
                    DatePicker(
                        "Beschwerden unterschrieben am",
                        selection: Binding(
                            get: { kundenBeschwerdenUnterschriebenAm ?? Date() },
                            set: { kundenBeschwerdenUnterschriebenAm = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .opacity(kundenBeschwerden.isEmpty ? 0.4 : 1.0)
                    .disabled(kundenBeschwerden.isEmpty)
                    TextField("Auftragsbestätigung (z. B. keine weiteren Ansprüche)", text: $auftragBestaetigtText, axis: .vertical)
                        .lineLimit(2...4)
                    DatePicker(
                        "Bestätigung unterschrieben am",
                        selection: Binding(
                            get: { auftragBestaetigtUnterschriebenAm ?? Date() },
                            set: { auftragBestaetigtUnterschriebenAm = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .opacity(auftragBestaetigtText.isEmpty ? 0.4 : 1.0)
                    .disabled(auftragBestaetigtText.isEmpty)
                }
            }
            .navigationTitle("Projekt bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                name = project.name
                strasse = project.strasse ?? ""
                hausnummer = project.hausnummer ?? ""
                postleitzahl = project.postleitzahl ?? ""
                ort = project.ort ?? ""
                kundeName = project.kundeName ?? ""
                kundeTelefon = project.kundeTelefon ?? ""
                kundeEmail = project.kundeEmail ?? ""
                nvtNummer = project.nvtNummer ?? ""
                kolonne = project.kolonne ?? ""
                kolonnenList = StorageService().loadKolonnen()
                verbundGroesse = project.verbundGroesse ?? ""
                verbundFarbe = project.verbundFarbe ?? ""
                pipesFarbe1 = project.pipesFarbe1 ?? project.pipesFarbe ?? ""
                pipesFarbe2 = project.pipesFarbe2 ?? ""
                auftragAbgeschlossen = project.auftragAbgeschlossen ?? false
                termin = project.termin
                googleDriveLink = project.googleDriveLink ?? ""
                notizen = project.notizen ?? ""
                telefonNotizen = project.telefonNotizen ?? ""
                kundenBeschwerden = project.kundenBeschwerden ?? ""
                kundenBeschwerdenUnterschriebenAm = project.kundenBeschwerdenUnterschriebenAm
                auftragBestaetigtText = project.auftragBestaetigtText ?? ""
                auftragBestaetigtUnterschriebenAm = project.auftragBestaetigtUnterschriebenAm
                abnahmeProtokollUnterschriftPath = project.abnahmeProtokollUnterschriftPath
                abnahmeProtokollDatum = project.abnahmeProtokollDatum
            }
            .sheet(isPresented: $showAddKolonne) {
                addKolonneSheet
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var addKolonneSheet: some View {
        NavigationStack {
            Form {
                TextField("Name der Kolonne", text: $newKolonneName)
                Button("Hinzufügen") {
                    let t = newKolonneName.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    if !kolonnenList.contains(t) {
                        kolonnenList.append(t)
                        StorageService().saveKolonnen(kolonnenList)
                    }
                    kolonne = t
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

    private func save() {
        let updated = Project(
            id: project.id,
            serverProjectId: project.serverProjectId,
            name: name.trimmingCharacters(in: .whitespaces),
            measurements: project.measurements,
            createdAt: project.createdAt,
            strasse: strasse.isEmpty ? nil : strasse.trimmingCharacters(in: .whitespaces),
            hausnummer: hausnummer.isEmpty ? nil : hausnummer.trimmingCharacters(in: .whitespaces),
            postleitzahl: postleitzahl.isEmpty ? nil : postleitzahl.trimmingCharacters(in: .whitespaces),
            ort: ort.isEmpty ? nil : ort.trimmingCharacters(in: .whitespaces),
            nvtNummer: nvtNummer.isEmpty ? nil : nvtNummer.trimmingCharacters(in: .whitespaces),
            kolonne: kolonne.isEmpty ? nil : kolonne,
            verbundGroesse: verbundGroesse.isEmpty ? nil : verbundGroesse,
            verbundFarbe: verbundFarbe.isEmpty ? nil : verbundFarbe,
            pipesFarbe1: pipesFarbe1.isEmpty ? nil : pipesFarbe1,
            pipesFarbe2: pipesFarbe2.isEmpty ? nil : pipesFarbe2,
            auftragAbgeschlossen: auftragAbgeschlossen,
            ampelStatus: auftragAbgeschlossen ? "gruen" : project.ampelStatus,
            termin: termin,
            googleDriveLink: googleDriveLink.isEmpty ? nil : googleDriveLink.trimmingCharacters(in: .whitespaces),
            notizen: notizen.isEmpty ? nil : notizen.trimmingCharacters(in: .whitespaces),
            telefonNotizen: telefonNotizen.isEmpty ? nil : telefonNotizen.trimmingCharacters(in: .whitespaces),
            kundenBeschwerden: kundenBeschwerden.isEmpty ? nil : kundenBeschwerden.trimmingCharacters(in: .whitespaces),
            kundenBeschwerdenUnterschriebenAm: kundenBeschwerden.isEmpty ? nil : kundenBeschwerdenUnterschriebenAm,
            auftragBestaetigtText: auftragBestaetigtText.isEmpty ? nil : auftragBestaetigtText.trimmingCharacters(in: .whitespaces),
            auftragBestaetigtUnterschriebenAm: auftragBestaetigtText.isEmpty ? nil : auftragBestaetigtUnterschriebenAm,
            abnahmeProtokollUnterschriftPath: abnahmeProtokollUnterschriftPath,
            abnahmeProtokollDatum: abnahmeProtokollDatum,
            abnahmeOhneMaengel: project.abnahmeOhneMaengel,
            abnahmeMaengelText: project.abnahmeMaengelText,
            kundeName: kundeName.isEmpty ? nil : kundeName.trimmingCharacters(in: .whitespaces),
            kundeTelefon: kundeTelefon.isEmpty ? nil : kundeTelefon.trimmingCharacters(in: .whitespaces),
            kundeEmail: kundeEmail.isEmpty ? nil : kundeEmail.trimmingCharacters(in: .whitespaces),
            bauhinderung: project.bauhinderung,
            threeDScans: project.threeDScans
        )
        onSave(updated)
    }
}

/// Damit das Share-Sheet nur mit gültiger URL erscheint (kein weißer Bildschirm).
struct ShareablePDFItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareableExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Neues Modul: Baugruben 3D Scan (polycam-ähnlicher Workflow)

private struct Baugrube3DScanModuleView: View {
    @EnvironmentObject var viewModel: MapViewModel
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID

    @State private var showScanner = false
    @State private var pendingScanId = UUID()

    private var project: Project? {
        viewModel.project(byId: projectId)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let p = project {
                    List {
                        Section("Baugruben 3D Scans") {
                            if p.threeDScans.isEmpty {
                                Text("Noch keine 3D-Scans gespeichert.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(p.threeDScans.sorted(by: { $0.createdAt > $1.createdAt })) { scan in
                                    NavigationLink {
                                        Scan3DViewerView(scan: scan)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(scan.name)
                                                .font(.headline)
                                            Text(scan.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .onDelete { offsets in
                                    let sorted = p.threeDScans.sorted(by: { $0.createdAt > $1.createdAt })
                                    for idx in offsets {
                                        guard sorted.indices.contains(idx) else { continue }
                                        viewModel.deleteThreeDScan(projectId: p.id, scanId: sorted[idx].id)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Projekt nicht gefunden", systemImage: "folder.badge.questionmark")
                }
            }
            .navigationTitle("Baugruben 3D")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        pendingScanId = UUID()
                        showScanner = true
                    } label: {
                        Label("Neuer Scan", systemImage: "plus.circle.fill")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            ARMeshScanView(
                scanId: pendingScanId,
                onSave: { path, lat, lon, ox, oy, oz, keyframes in
                    guard var p = viewModel.project(byId: projectId) else {
                        showScanner = false
                        return
                    }
                    if p.threeDScans.contains(where: { $0.id == pendingScanId }) {
                        showScanner = false
                        return
                    }
                    let n = p.threeDScans.count + 1
                    let scan = ThreeDScan(
                        id: pendingScanId,
                        name: "Baugrube \(n)",
                        createdAt: Date(),
                        filePath: path,
                        note: nil,
                        latitude: lat,
                        longitude: lon,
                        sceneOriginX: ox,
                        sceneOriginY: oy,
                        sceneOriginZ: oz,
                        keyframes: keyframes
                    )
                    p.threeDScans.append(scan)
                    viewModel.updateProject(p)
                    showScanner = false
                },
                onCancel: {
                    showScanner = false
                }
            )
        }
    }
}

/// Zeigt das 3D-Scan-Modell an seiner GPS-Position auf einer 2D-Luftbild-Karte als Boden-Layer.
private struct ScanOnMap3DView: View {
    let scan: ThreeDScan
    let storage: StorageService
    @State private var mapImage: UIImage?

    var body: some View {
        SceneView(
            scene: buildMapScene(groundImage: mapImage),
            pointOfView: nil,
            options: [.allowsCameraControl, .autoenablesDefaultLighting]
        )
        .onAppear { fetchLuftbildSnapshot() }
    }

    private func fetchLuftbildSnapshot() {
        guard let lat = scan.latitude, let lon = scan.longitude else { return }
        let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let span = MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
        let region = MKCoordinateRegion(center: center, span: span)
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 512, height: 512)
        options.mapType = .satellite
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, error in
            guard let snapshot = snapshot else { return }
            DispatchQueue.main.async { mapImage = snapshot.image }
        }
    }

    private func buildMapScene(groundImage: UIImage?) -> SCNScene {
        let scene = SCNScene()
        let groundSize: CGFloat = 80
        let ground = SCNPlane(width: groundSize, height: groundSize)
        ground.firstMaterial?.diffuse.contents = groundImage ?? UIColor.systemGray5
        ground.firstMaterial?.isDoubleSided = true
        let groundNode = SCNNode(geometry: ground)
        groundNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        groundNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(groundNode)
        if groundImage == nil {
            let grid = createGridNode(size: groundSize)
            scene.rootNode.addChildNode(grid)
        }
        if let modelNode = loadScanModel() {
            if let ox = scan.sceneOriginX, let oy = scan.sceneOriginY, let oz = scan.sceneOriginZ {
                modelNode.position = SCNVector3(-Float(ox), -Float(oy), -Float(oz))
            } else {
                modelNode.position = SCNVector3(0, 0, 0)
            }
            scene.rootNode.addChildNode(modelNode)
        }
        return scene
    }

    private func createGridNode(size: CGFloat) -> SCNNode {
        let container = SCNNode()
        let step: CGFloat = 10
        let half = size / 2
        let thin: CGFloat = 0.02
        let lineXGeo = SCNBox(width: size, height: thin, length: thin, chamferRadius: 0)
        lineXGeo.firstMaterial?.diffuse.contents = UIColor.systemGray3
        let lineZGeo = SCNBox(width: thin, height: thin, length: size, chamferRadius: 0)
        lineZGeo.firstMaterial?.diffuse.contents = UIColor.systemGray3
        for i in stride(from: -half, through: half, by: step) {
            let lineX = SCNNode(geometry: lineXGeo)
            lineX.position = SCNVector3(0, Float(thin), Float(i))
            container.addChildNode(lineX)
            let lineZ = SCNNode(geometry: lineZGeo)
            lineZ.position = SCNVector3(Float(i), Float(thin), 0)
            container.addChildNode(lineZ)
        }
        return container
    }

    private func loadScanModel() -> SCNNode? {
        let path = scan.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let fullPath = storage.fullPath(forStoredPath: path)
        let url = URL(fileURLWithPath: fullPath)
        guard let loadedScene = try? SCNScene(url: url) else { return nil }
        let node = SCNNode()
        for child in loadedScene.rootNode.childNodes {
            node.addChildNode(child.clone())
        }
        let scale: Float = 1.0
        node.scale = SCNVector3(scale, scale, scale)
        return node
    }
}


/// Lokale Unterschrifts-Ansicht für das Abnahmeprotokoll.
struct SignatureView: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (UIImage) -> Void

    @State private var lines: [[CGPoint]] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                signatureContent
            }
            .navigationTitle("Unterschrift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(lines.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Löschen") { lines.removeAll() }
                }
            }
        }
    }

    private var signatureContent: some View {
        GeometryReader { _ in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.gray.opacity(0.4), lineWidth: 1)
                    .background(Color.white)
                Path { path in
                    for line in lines {
                        guard let first = line.first else { continue }
                        path.move(to: first)
                        for pt in line.dropFirst() {
                            path.addLine(to: pt)
                        }
                    }
                }
                .stroke(Color.black, lineWidth: 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = value.location
                        if lines.isEmpty {
                            lines.append([point])
                        } else {
                            lines[lines.count - 1].append(point)
                        }
                    }
                    .onEnded { _ in
                        lines.append([])
                    }
            )
            .padding()
        }
    }

    private func save() {
        let renderer = ImageRenderer(content: signatureContent.frame(width: 600, height: 200))
        renderer.scale = 2
        if let img = renderer.uiImage {
            onSave(img)
            dismiss()
        }
    }
}


