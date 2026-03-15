import SwiftUI
import CoreLocation

struct MeasurementDetailView: View {
    @EnvironmentObject var viewModel: MapViewModel
    let projectId: UUID?
    @State var measurement: Measurement
    @State private var showShareSheet = false
    @State private var pdfURL: URL?
    @StateObject private var locationService = LocationService()
    private let storage = StorageService()
    @State private var editOberflaeche: String = ""
    @State private var editOberflaecheSonstige: String = ""
    @State private var editVerlegeart: String = ""
    @State private var editVerlegeartSonstige: String = ""
    @State private var editPolylineOberflaeche: [String] = []
    @State private var editPolylineVerlegeart: [String] = []

    private var polylineSegmentCount: Int {
        let poly = measurement.polylinePoints ?? []
        let segs = measurement.polylineSegmentMeters ?? []
        if !segs.isEmpty { return segs.count }
        return max(0, poly.count - 1)
    }

    private var loadedImage: UIImage? {
        let path = storage.fullPath(forStoredPath: measurement.imagePath)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return UIImage(contentsOfFile: path)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let img = loadedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.gray.opacity(0.3))
                        .frame(height: 200)
                        .overlay(Text("Bild nicht geladen").foregroundStyle(.secondary))
                }

                VStack(spacing: 4) {
                    if let idx = measurement.index {
                        let titlePrefix = measurement.isARMeasurement ? "Messung" : "Foto"
                        Text("\(titlePrefix) \(idx)")
                            .font(.title3.bold())
                    }
                    Text(measurement.address)
                        .font(.headline)
                }

                if let m = measurement.referenceMeters {
                    Text("Gesamtlänge: \(m, specifier: "%.2f") m")
                } else {
                    Text("Gesamtlänge: \(measurement.totalDistance, specifier: "%.0f") px")
                }

                let scale = (measurement.referenceMeters != nil && measurement.totalDistance > 0)
                    ? measurement.referenceMeters! / measurement.totalDistance
                    : nil
                ForEach(measurement.points) { p in
                    if let scale = scale, p.distance > 0 {
                        Text("Messpunkt: \(p.distance * scale, specifier: "%.2f") m")
                    } else {
                        Text("Messpunkt: \(p.distance, specifier: "%.0f") px")
                    }
                }

                if measurement.isARMeasurement {
                    if polylineSegmentCount > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Oberfläche & Verlegeart pro Segment")
                                .font(.subheadline.bold())
                            ForEach(0 ..< polylineSegmentCount, id: \.self) { i in
                                let from = Character(Unicode.Scalar(65 + i)!)
                                let to = Character(Unicode.Scalar(66 + i)!)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(from) → \(to)")
                                        .font(.subheadline.bold())
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Oberfläche").font(.caption).foregroundStyle(.secondary)
                                            Picker("Oberfläche", selection: bindingPolylineOberflaeche(i)) {
                                                Text("— Auswählen").tag("")
                                                ForEach(Self.oberflaechenOptions, id: \.self) { Text($0).tag($0) }
                                            }
                                            .pickerStyle(.menu)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Verlegeart").font(.caption).foregroundStyle(.secondary)
                                            Picker("Verlegeart", selection: bindingPolylineVerlegeart(i)) {
                                                Text("— Auswählen").tag("")
                                                ForEach(Self.verlegeartOptions, id: \.self) { Text($0).tag($0) }
                                            }
                                            .pickerStyle(.menu)
                                        }
                                    }
                                }
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .onAppear { syncPolylineSegmentEditArrays() }
                        .onChange(of: measurement.id) { _, _ in syncPolylineSegmentEditArrays() }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Oberfläche & Verlegeart")
                                .font(.subheadline.bold())
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Oberfläche").font(.caption).foregroundStyle(.secondary)
                                    Picker("Oberfläche", selection: $editOberflaeche) {
                                        Text("— Auswählen").tag("")
                                        ForEach(Self.oberflaechenOptions, id: \.self) { Text($0).tag($0) }
                                    }
                                    .pickerStyle(.menu)
                                    .onChange(of: editOberflaeche) { _, _ in applyOberflaecheVerlegeart() }
                                    if editOberflaeche == "Sonstige Oberfläche" {
                                        TextField("Sonstige Oberfläche", text: $editOberflaecheSonstige)
                                            .textFieldStyle(.roundedBorder)
                                            .onChange(of: editOberflaecheSonstige) { _, _ in applyOberflaecheVerlegeart() }
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Verlegeart").font(.caption).foregroundStyle(.secondary)
                                    Picker("Verlegeart", selection: $editVerlegeart) {
                                        Text("— Auswählen").tag("")
                                        ForEach(Self.verlegeartOptions, id: \.self) { Text($0).tag($0) }
                                    }
                                    .pickerStyle(.menu)
                                    .onChange(of: editVerlegeart) { _, _ in applyOberflaecheVerlegeart() }
                                    if editVerlegeart == "Sonstige Verlegeart" {
                                        TextField("Sonstige Verlegeart", text: $editVerlegeartSonstige)
                                            .textFieldStyle(.roundedBorder)
                                            .onChange(of: editVerlegeartSonstige) { _, _ in applyOberflaecheVerlegeart() }
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .onAppear {
                            editOberflaeche = measurement.oberflaeche ?? ""
                            editOberflaecheSonstige = measurement.oberflaecheSonstige ?? ""
                            editVerlegeart = measurement.verlegeart ?? ""
                            editVerlegeartSonstige = measurement.verlegeartSonstige ?? ""
                        }
                        .onChange(of: measurement.id) { _, _ in
                            editOberflaeche = measurement.oberflaeche ?? ""
                            editOberflaecheSonstige = measurement.oberflaecheSonstige ?? ""
                            editVerlegeart = measurement.verlegeart ?? ""
                            editVerlegeartSonstige = measurement.verlegeartSonstige ?? ""
                        }
                    }

                    if let poly = measurement.polylinePoints, !poly.isEmpty {
                        let segments: [Double] = measurement.polylineSegmentMeters.flatMap { $0.isEmpty ? nil : $0 } ?? polylineSegmentDistances(poly)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(segments.enumerated()), id: \.offset) { i, meters in
                                let from = Character(Unicode.Scalar(65 + i)!)
                                let to = Character(Unicode.Scalar(66 + i)!)
                                Text("\(from) → \(to): \(meters, specifier: "%.2f") m")
                                    .font(.subheadline)
                            }
                            if !segments.isEmpty {
                                let total = segments.reduce(0, +)
                                Text("Gesamt: \(total, specifier: "%.2f") m")
                                    .font(.subheadline.bold())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        ForEach(Array(poly.enumerated()), id: \.element.id) { i, p in
                            Text("Punkt \(i + 1): \(p.latitude, specifier: "%.6f"), \(p.longitude, specifier: "%.6f")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if let sLat = measurement.startLatitude,
                           let sLon = measurement.startLongitude {
                            Text("Startpunkt A: \(sLat, specifier: "%.6f"), \(sLon, specifier: "%.6f")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let eLat = measurement.endLatitude,
                           let eLon = measurement.endLongitude {
                            Text("Endpunkt B: \(eLat, specifier: "%.6f"), \(eLon, specifier: "%.6f")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if measurement.isARMeasurement, isLastMeasurement, let idx = measurement.index {
                    if let poly = measurement.polylinePoints, !poly.isEmpty {
                        Button("Letzten Punkt (Polylinie) Koordinaten aktualisieren") {
                            setLastPolylinePointGPS()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Endpunkt \(idx)B GPS neu setzen") {
                            setEndPointGPS()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if measurement.orderedGPSPoints.count >= 2 {
                    NavigationLink {
                        MeasurementSketchView(
                            projectId: projectId,
                            measurement: $measurement,
                            onSave: { updated in
                                guard let projectId else { return }
                                viewModel.updateMeasurement(projectId: projectId, updated)
                            }
                        )
                    } label: {
                        Label("Skizze erstellen (Luftbild, Verschieben & Drehen)", systemImage: "map")
                    }
                    .buttonStyle(.bordered)
                }

                Text(measurement.date.formatted())
            }
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        // PDF-Erstellung ist bewusst nur im Projekt möglich (ProjectDetailView).
    }

    /// Teilstrecken in Metern zwischen aufeinanderfolgenden Polylinien-Punkten (GPS).
    private func polylineSegmentDistances(_ points: [PolylinePoint]) -> [Double] {
        guard points.count >= 2 else { return [] }
        var distances: [Double] = []
        for i in 0 ..< (points.count - 1) {
            let a = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            let b = CLLocation(latitude: points[i + 1].latitude, longitude: points[i + 1].longitude)
            distances.append(a.distance(from: b))
        }
        return distances
    }

    private var isLastMeasurement: Bool {
        guard let projectId,
              let project = viewModel.project(byId: projectId),
              let last = project.measurements
                .filter({ $0.isARMeasurement })
                .sorted(by: { ($0.index ?? 0, $0.date) < ($1.index ?? 0, $1.date) }).last
        else { return false }
        return last.id == measurement.id
    }

    private func setEndPointGPS() {
        guard let loc = locationService.location,
              let projectId
        else { return }
        var updated = measurement
        updated.endLatitude = loc.coordinate.latitude
        updated.endLongitude = loc.coordinate.longitude
        measurement = updated
        viewModel.updateMeasurement(projectId: projectId, updated)
    }

    private func setLastPolylinePointGPS() {
        guard let loc = locationService.location,
              let projectId,
              var points = measurement.polylinePoints,
              !points.isEmpty
        else { return }
        points[points.count - 1].latitude = loc.coordinate.latitude
        points[points.count - 1].longitude = loc.coordinate.longitude
        var updated = measurement
        updated.polylinePoints = points
        updated.endLatitude = loc.coordinate.latitude
        updated.endLongitude = loc.coordinate.longitude
        measurement = updated
        viewModel.updateMeasurement(projectId: projectId, updated)
    }

    private func applyOberflaecheVerlegeart() {
        guard let projectId else { return }
        var updated = measurement
        updated.oberflaeche = editOberflaeche.isEmpty ? nil : editOberflaeche
        updated.oberflaecheSonstige = (editOberflaeche == "Sonstige Oberfläche" && !editOberflaecheSonstige.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? editOberflaecheSonstige.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        updated.verlegeart = editVerlegeart.isEmpty ? nil : editVerlegeart
        updated.verlegeartSonstige = (editVerlegeart == "Sonstige Verlegeart" && !editVerlegeartSonstige.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? editVerlegeartSonstige.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        measurement = updated
        viewModel.updateMeasurement(projectId: projectId, updated)
    }

    private func bindingPolylineOberflaeche(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < editPolylineOberflaeche.count ? editPolylineOberflaeche[i] : "" },
            set: { new in
                var copy = editPolylineOberflaeche
                while copy.count <= i { copy.append("") }
                copy[i] = new
                editPolylineOberflaeche = copy
                applyPolylineSegmentMeta()
            }
        )
    }

    private func bindingPolylineVerlegeart(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < editPolylineVerlegeart.count ? editPolylineVerlegeart[i] : "" },
            set: { new in
                var copy = editPolylineVerlegeart
                while copy.count <= i { copy.append("") }
                copy[i] = new
                editPolylineVerlegeart = copy
                applyPolylineSegmentMeta()
            }
        )
    }

    private func syncPolylineSegmentEditArrays() {
        let n = polylineSegmentCount
        let ob = measurement.polylineSegmentOberflaeche ?? []
        let ver = measurement.polylineSegmentVerlegeart ?? []
        editPolylineOberflaeche = (0 ..< n).map { i in i < ob.count ? (ob[i] ?? "") : "" }
        editPolylineVerlegeart = (0 ..< n).map { i in i < ver.count ? (ver[i] ?? "") : "" }
    }

    private func applyPolylineSegmentMeta() {
        guard let projectId else { return }
        var updated = measurement
        updated.polylineSegmentOberflaeche = editPolylineOberflaeche.map { $0.isEmpty ? nil : $0 }
        updated.polylineSegmentVerlegeart = editPolylineVerlegeart.map { $0.isEmpty ? nil : $0 }
        measurement = updated
        viewModel.updateMeasurement(projectId: projectId, updated)
    }
}

private extension MeasurementDetailView {
    static let oberflaechenOptions: [String] = [
        "Rasen / Grünfläche",
        "Mutterboden / Erde",
        "Kies / Schotter",
        "Sandfläche",
        "Beet / Gartenanlage",
        "Betonpflaster",
        "Natursteinpflaster",
        "Gehwegplatten / Betonplatten",
        "Rasengittersteine",
        "Asphalt / Bitumen",
        "Betonfläche",
        "Einfahrt / Hofpflaster",
        "Terrasse / Plattenbelag",
        "Holzboden / WPC-Terrasse",
        "Rollrasen / neu angelegte Grünfläche",
        "Sonstige Oberfläche"
    ]
    static let verlegeartOptions: [String] = [
        "Offener Graben (klassischer Tiefbau)",
        "Schmalgraben / Mini-Graben",
        "Einzug in vorhandenes Leerrohr",
        "Spülbohrverfahren (Horizontalbohrung)",
        "Erdrakete / Bodenverdrängungsverfahren",
        "Pressbohrung unter Oberfläche (z. B. unter Einfahrt / Gehweg)",
        "Einblasen / Einziehen der Pipe in vorhandene Trasse",
        "Verlegung im Schutzrohr",
        "Sonstige Verlegeart"
    ]
}
