import SwiftUI
import MapKit

/// Kartenstil für die Skizzen-Ansicht. MapLibre GL = Open-Source-Vektorkarte; OSM/Apple als Alternative.
private enum SketchMapStyle: String, CaseIterable {
    case mapLibre = "MapLibre GL"
    case openStreetMap = "OpenStreetMap"
    case standard = "Straße (Apple)"
    case imagery = "Satellit (Apple)"
    case hybrid = "Hybrid (Apple)"
    var mapStyle: MapStyle {
        switch self {
        case .mapLibre: return .standard
        case .openStreetMap: return .standard
        case .standard: return .standard
        case .imagery: return .imagery
        case .hybrid: return .hybrid
        }
    }
}

/// Zeigt die Messung auf einer 2D-Luftbildkarte; Verschieben und Drehen zur Positionskorrektur, dann „Korrektur übernehmen“.
struct MeasurementSketchView: View {
    let projectId: UUID?
    @Binding var measurement: Measurement
    var onSave: (Measurement) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var offsetLat: Double = 0
    @State private var offsetLon: Double = 0
    @State private var rotationDegrees: Double = 0
    @State private var scale: Double = 1.0
    @State private var mirrored: Bool = false
    /// Luftbild-Zoom: > 1 = stärker heranzoomen (Luftbild größer), < 1 = weiter raus
    @State private var mapZoom: Double = 1.0
    @State private var mapPosition: MapCameraPosition = .automatic
    /// Kartenstil: MapLibre GL (Open-Source); sonst OpenStreetMap oder Apple.
    @State private var mapStyleOption: SketchMapStyle = .mapLibre

    private let metersPerDegreeLat = 111_320.0

    private var points: [CLLocationCoordinate2D] { measurement.orderedGPSPoints }

    private var center: CLLocationCoordinate2D {
        guard !points.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        let sumLat = points.reduce(0.0) { $0 + $1.latitude }
        let sumLon = points.reduce(0.0) { $0 + $1.longitude }
        return CLLocationCoordinate2D(latitude: sumLat / Double(points.count), longitude: sumLon / Double(points.count))
    }

    /// Punkte: Rotation um Mittelpunkt → Vergrößern/Verkleinern (Maßstab) → Versatz. Ergibt die zusammengesetzte Polylinie A→B→C→D…
    private func correctedPoints() -> [CLLocationCoordinate2D] {
        guard !points.isEmpty else { return [] }
        let c = center
        let rad = rotationDegrees * .pi / 180
        let cosA = cos(rad)
        let sinA = sin(rad)
        let scaleLon = metersPerDegreeLat * max(0.01, cos(c.latitude * .pi / 180))
        let s = max(0.2, min(5.0, scale))

        let midLon = c.longitude + offsetLon
        return points.map { p in
            let dx = (p.longitude - c.longitude) * scaleLon
            let dy = (p.latitude - c.latitude) * metersPerDegreeLat
            let dx2 = (cosA * dx - sinA * dy) * s
            let dy2 = (sinA * dx + cosA * dy) * s
            let lat = c.latitude + dy2 / metersPerDegreeLat + offsetLat
            var lon = c.longitude + dx2 / scaleLon + offsetLon
            if mirrored { lon = 2 * midLon - lon }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    private var mapRegion: MKCoordinateRegion {
        let pts = correctedPoints()
        let zoom = max(0.3, min(5.0, mapZoom))
        guard !pts.isEmpty else {
            return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.001 / zoom, longitudeDelta: 0.001 / zoom))
        }
        let lats = pts.map(\.latitude)
        let lons = pts.map(\.longitude)
        let minLat = lats.min() ?? center.latitude
        let maxLat = lats.max() ?? center.latitude
        let minLon = lons.min() ?? center.longitude
        let maxLon = lons.max() ?? center.longitude
        let baseLat = max((maxLat - minLat) * 1.5, 0.0003)
        let baseLon = max((maxLon - minLon) * 1.5, 0.0003)
        let span = MKCoordinateSpan(
            latitudeDelta: baseLat / zoom,
            longitudeDelta: baseLon / zoom
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        VStack(spacing: 0) {
            if points.count >= 2 {
                sketchContent
            } else {
                sketchEmptyState
            }
        }
        .navigationTitle("Skizze auf Luftbild")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            offsetLat = measurement.sketchOffsetLat ?? 0
            offsetLon = measurement.sketchOffsetLon ?? 0
            rotationDegrees = measurement.sketchRotationDegrees ?? 0
            scale = measurement.sketchScale ?? 1.0
            mirrored = measurement.sketchMirrored ?? false
        }
    }

    private var sketchEmptyState: some View {
        VStack(spacing: 0) {
            Text("Für die Skizze werden mindestens 2 GPS-Punkte benötigt (Einzelstrecke A–B oder Polylinie).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
    }

    @ViewBuilder
    private var sketchContent: some View {
        let corrected = correctedPoints()
        let polylineLabel = (0 ..< corrected.count).map { i in i < 26 ? String(Unicode.Scalar(65 + i)!) : "\(i + 1)" }.joined(separator: " → ")

        VStack(alignment: .leading, spacing: 4) {
            Text("Polylinie \(polylineLabel)")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)

        sketchMapView(corrected: corrected)
        sketchZoomSlider
        sketchControls
    }

    @ViewBuilder
    private func sketchMapView(corrected: [CLLocationCoordinate2D]) -> some View {
        if mapStyleOption == .mapLibre {
            SketchMapLibreView(region: mapRegion, coordinates: corrected)
                .frame(maxHeight: .infinity)
        } else if mapStyleOption == .openStreetMap {
            SketchOSMMapView(region: mapRegion, coordinates: corrected)
                .frame(maxHeight: .infinity)
        } else {
            Map(position: .constant(.region(mapRegion)), interactionModes: .all) {
                MapPolyline(coordinates: corrected)
                    .stroke(.blue, lineWidth: 4)
                ForEach(annotationIndices(for: corrected), id: \.self) { i in
                    let coord = corrected[i]
                    Annotation("", coordinate: coord) {
                        sketchPointMarker(index: i)
                    }
                }
            }
            .mapStyle(mapStyleOption.mapStyle)
            .frame(maxHeight: .infinity)
        }
    }

    private func annotationIndices(for corrected: [CLLocationCoordinate2D]) -> [Int] {
        guard corrected.count >= 2 else { return [] }
        return [0, corrected.count - 1]
    }

    private func sketchPointMarker(index: Int) -> some View {
        ZStack {
            Circle()
                .fill(.blue)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.white, lineWidth: 1))
            Text(index < 26 ? String(Unicode.Scalar(65 + index)!) : "\(index + 1)")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var sketchZoomSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Kartenstil", selection: $mapStyleOption) {
                ForEach(SketchMapStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.menu)
            Text("MapLibre GL = Open-Source-Vektorkarte. OpenStreetMap & Apple als weitere Optionen.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Luftbild vergrößern: \(mapZoom, specifier: "%.1f")×")
                .font(.caption)
            Slider(value: $mapZoom, in: 0.5 ... 5.0, step: 0.25)
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .background(.ultraThinMaterial)
    }

    private var sketchControls: some View {
        VStack(spacing: 12) {
            Text("Position korrigieren")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("Vergrößern / an Bild anpassen: \(scale, specifier: "%.2f")×")
                    .font(.caption)
                Slider(value: $scale, in: 0.2 ... 5.0, step: 0.05)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Versatz N-S (°): \(offsetLat, specifier: "%.5f")")
                        .font(.caption)
                    Slider(value: $offsetLat, in: -0.001 ... 0.001, step: 0.00001)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Versatz O-W (°): \(offsetLon, specifier: "%.5f")")
                        .font(.caption)
                    Slider(value: $offsetLon, in: -0.001 ... 0.001, step: 0.00001)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Drehung (°): \(rotationDegrees, specifier: "%.1f")")
                    .font(.caption)
                Slider(value: $rotationDegrees, in: -180 ... 180, step: 1)
            }
            Toggle("Spiegelverkehrt (Polylinie horizontal spiegeln)", isOn: $mirrored)
            HStack(spacing: 12) {
                Button("Zurücksetzen") {
                    offsetLat = measurement.sketchOffsetLat ?? 0
                    offsetLon = measurement.sketchOffsetLon ?? 0
                    rotationDegrees = measurement.sketchRotationDegrees ?? 0
                    scale = measurement.sketchScale ?? 1.0
                    mirrored = measurement.sketchMirrored ?? false
                }
                .buttonStyle(.bordered)
                Button("Korrektur übernehmen") {
                    var m = measurement
                    m.sketchOffsetLat = offsetLat
                    m.sketchOffsetLon = offsetLon
                    m.sketchRotationDegrees = rotationDegrees
                    m.sketchScale = scale
                    m.sketchMirrored = mirrored
                    measurement = m
                    onSave(m)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial)
    }
}
