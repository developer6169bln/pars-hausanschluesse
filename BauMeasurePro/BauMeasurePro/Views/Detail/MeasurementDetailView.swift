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
                    let ob = measurement.oberflaeche ?? measurement.oberflaecheSonstige
                    let ver = measurement.verlegeart ?? measurement.verlegeartSonstige
                    if ob != nil || ver != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            if let o = ob, !o.isEmpty {
                                LabeledContent("Oberfläche", value: o)
                                    .font(.subheadline)
                            }
                            if let v = ver, !v.isEmpty {
                                LabeledContent("Verlegeart", value: v)
                                    .font(.subheadline)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
}
