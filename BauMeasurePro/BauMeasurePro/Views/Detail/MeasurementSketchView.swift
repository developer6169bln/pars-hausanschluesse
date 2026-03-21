import SwiftUI
import MapKit
import UIKit

private enum SketchLineColor: String, CaseIterable, Identifiable, Hashable {
    case rot = "Rot"
    case gruen = "Grün"
    case gelb = "Gelb"
    case weiss = "Weiß"
    case schwarz = "Schwarz"

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .rot: return .red
        case .gruen: return .green
        case .gelb: return .yellow
        case .weiss: return .white
        case .schwarz: return .black
        }
    }

    var uiColor: UIColor {
        switch self {
        case .rot: return .red
        case .gruen: return .systemGreen
        case .gelb: return .yellow
        case .weiss: return .white
        case .schwarz: return .black
        }
    }
}

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

enum PointMarkerStyle: String, CaseIterable, Identifiable {
    case standard = "Standard (Blau)"
    case dark = "Schwarz innen / Weißer Rand"
    case light = "Weiß innen / Schwarzer Rand"

    var id: String { rawValue }

    var fillColor: UIColor {
        switch self {
        case .standard: return .systemBlue
        case .dark: return .black
        case .light: return .white
        }
    }

    var borderColor: UIColor {
        switch self {
        case .light: return .black
        default: return .white
        }
    }

    var textColor: UIColor {
        switch self {
        case .dark: return .black
        default: return .white
        }
    }

    var textStrokeColor: UIColor {
        switch self {
        case .dark: return .white
        default: return .black
        }
    }
}

/// Zeigt die Messung auf einer 2D-Luftbildkarte; Verschieben und Drehen zur Positionskorrektur, dann „Korrektur übernehmen“.
struct MeasurementSketchView: View {
    let projectId: UUID?
    @Binding var measurement: Measurement
    var onSave: (Measurement) -> Void
    /// Speichert das aktuelle Luftbild (mit Route) als eigene Foto-Messung ins Projekt.
    /// Wird typischerweise von `MeasurementDetailView` bereitgestellt.
    var onSaveAerialPhoto: ((UIImage, [CLLocationCoordinate2D]) -> Void)?
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
    @State private var isRedrawMode: Bool = false
    @State private var draftPoints: [CLLocationCoordinate2D] = []
    @State private var showFullscreenEditor: Bool = false
    @State private var selectedDraftIndex: Int? = nil
    @State private var hideIntermediatePoints: Bool = false
    @State private var sketchLineColor: SketchLineColor = .rot
    @State private var showSettingsSheet: Bool = false
    @State private var useARSegmentsStraight: Bool = true
    @State private var showSegmentMeasures: Bool = false
    @State private var showPointLabelsOnly: Bool = false
    @State private var segmentMeasureFontSizePx: Double = 12
    @State private var pointMarkerStyle: PointMarkerStyle = .standard

    private let metersPerDegreeLat = 111_320.0

    private var basePoints: [CLLocationCoordinate2D] {
        if let ov = measurement.sketchOverridePolylinePoints, !ov.isEmpty {
            return ov.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
        if useARSegmentsStraight, let straight = straightPointsFromARSegmentsIfPossible(), straight.count >= 2 {
            return straight
        }
        return measurement.orderedGPSPoints
    }

    private var totalLengthMetersForDisplay: Double {
        if let ref = measurement.referenceMeters {
            return ref
        }
        if let seg = measurement.polylineSegmentMeters, !seg.isEmpty {
            return seg.reduce(0, +)
        }
        return polylineLengthMeters(basePoints)
    }

    private func straightPointsFromARSegmentsIfPossible() -> [CLLocationCoordinate2D]? {
        guard let seg = measurement.polylineSegmentMeters, !seg.isEmpty else { return nil }
        // Startpunkt: bevorzugt A (Start GPS), sonst erster Polyline-Punkt
        let start: CLLocationCoordinate2D?
        if let slat = measurement.startLatitude, let slon = measurement.startLongitude {
            start = CLLocationCoordinate2D(latitude: slat, longitude: slon)
        } else {
            start = measurement.orderedGPSPoints.first
        }
        guard let start else { return nil }

        // Bearing: aus Start→Ende (wenn vorhanden), sonst Osten (90°)
        let end: CLLocationCoordinate2D? = {
            if let elat = measurement.endLatitude, let elon = measurement.endLongitude {
                return CLLocationCoordinate2D(latitude: elat, longitude: elon)
            }
            let gps = measurement.orderedGPSPoints
            return gps.count >= 2 ? gps.last : nil
        }()
        let bearingDeg = end.map { initialBearingDegrees(from: start, to: $0) } ?? 90.0

        var pts: [CLLocationCoordinate2D] = [start]
        var cum: Double = 0
        for d in seg {
            cum += max(0, d)
            pts.append(offsetCoordinate(start: start, bearingDegrees: bearingDeg, meters: cum))
        }
        return pts
    }

    private func initialBearingDegrees(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let brng = atan2(y, x) * 180 / .pi
        return (brng + 360).truncatingRemainder(dividingBy: 360)
    }

    private func offsetCoordinate(start: CLLocationCoordinate2D, bearingDegrees: Double, meters: Double) -> CLLocationCoordinate2D {
        // Lokale ENU-Approximation reicht hier (Skizze auf Luftbild).
        let theta = bearingDegrees * .pi / 180
        let north = cos(theta) * meters
        let east = sin(theta) * meters
        let dLat = north / metersPerDegreeLat
        let scaleLon = metersPerDegreeLat * max(0.01, cos(start.latitude * .pi / 180))
        let dLon = east / scaleLon
        return CLLocationCoordinate2D(latitude: start.latitude + dLat, longitude: start.longitude + dLon)
    }

    private func polylineLengthMeters(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var sum: Double = 0
        for i in 1..<coords.count {
            sum += haversineMeters(from: coords[i - 1], to: coords[i])
        }
        return sum
    }

    private func segmentMetersForDisplay(points: [CLLocationCoordinate2D]) -> [Double] {
        if let seg = measurement.polylineSegmentMeters, !seg.isEmpty, seg.count == max(0, points.count - 1) {
            return seg
        }
        guard points.count >= 2 else { return [] }
        var out: [Double] = []
        out.reserveCapacity(points.count - 1)
        for i in 1..<points.count {
            out.append(haversineMeters(from: points[i - 1], to: points[i]))
        }
        return out
    }

    private func haversineMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let R = 6_371_000.0 // Earth radius (m)
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let sinDLat = sin(dLat / 2)
        let sinDLon = sin(dLon / 2)
        let h = sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLon * sinDLon
        let c = 2 * atan2(sqrt(h), sqrt(1 - h))
        return R * c
    }

    // polylineLabelAnchor ist file-weit definiert (s.u.), damit es auch in den Vollbild-Structs sichtbar ist.

    private var center: CLLocationCoordinate2D {
        let pts = isRedrawMode ? draftPoints : basePoints
        guard !pts.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        let sumLat = pts.reduce(0.0) { $0 + $1.latitude }
        let sumLon = pts.reduce(0.0) { $0 + $1.longitude }
        return CLLocationCoordinate2D(latitude: sumLat / Double(pts.count), longitude: sumLon / Double(pts.count))
    }

    /// Punkte: Rotation um Mittelpunkt → Vergrößern/Verkleinern (Maßstab) → Versatz. Ergibt die zusammengesetzte Polylinie A→B→C→D…
    private func correctedPoints() -> [CLLocationCoordinate2D] {
        let points = isRedrawMode ? draftPoints : basePoints
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
            if basePoints.count >= 2 {
                sketchContent
            } else {
                sketchEmptyState
            }
        }
        .navigationTitle("Skizze auf Luftbild")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettingsSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Einstellungen")
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 14) {
                        sketchZoomSlider
                        sketchControls
                    }
                    .padding(.bottom, 24)
                }
                .navigationTitle("Einstellungen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fertig") { showSettingsSheet = false }
                    }
                }
            }
        }
        .onAppear {
            offsetLat = measurement.sketchOffsetLat ?? 0
            offsetLon = measurement.sketchOffsetLon ?? 0
            rotationDegrees = measurement.sketchRotationDegrees ?? 0
            scale = measurement.sketchScale ?? 1.0
            mirrored = measurement.sketchMirrored ?? false
            // Konsistent: in normaler und Edit-Anzeige standardmäßig alle Messpunkte einblenden.
            hideIntermediatePoints = false
            useARSegmentsStraight = measurement.sketchUseARSegments
                ?? ((measurement.polylineSegmentMeters?.isEmpty == false) ? true : false)
            draftPoints = basePoints
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

        ZStack(alignment: .topLeading) {
            sketchMapView(corrected: corrected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Polylinie \(polylineLabel)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 12)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func sketchMapView(corrected: [CLLocationCoordinate2D]) -> some View {
        let onlyPointLabelsMode = showPointLabelsOnly && (mapStyleOption == .imagery || mapStyleOption == .hybrid)
        let effectiveShowSegmentMeasures = showSegmentMeasures && !onlyPointLabelsMode
        if mapStyleOption == .mapLibre {
            SketchMapLibreView(
                region: mapRegion,
                coordinates: corrected,
                isEditMode: isRedrawMode,
                hideIntermediatePoints: hideIntermediatePoints,
                lineColor: sketchLineColor.uiColor,
                showSegmentMeasures: effectiveShowSegmentMeasures,
                segmentMeters: segmentMetersForDisplay(points: corrected),
                segmentLabelFontSizePx: segmentMeasureFontSizePx,
                pointMarkerStyle: pointMarkerStyle,
                onTapAddPoint: { coord in
                    guard isRedrawMode else { return }
                    draftPoints.append(coord)
                },
                selectedIndex: selectedDraftIndex,
                onSelectPoint: { selectedDraftIndex = $0 },
                onMovePoint: { idx, coord in
                    guard idx >= 0, idx < draftPoints.count else { return }
                    draftPoints[idx] = coord
                }
            )
                .frame(maxHeight: .infinity)
        } else if mapStyleOption == .openStreetMap {
            SketchOSMMapView(
                region: mapRegion,
                coordinates: corrected,
                lineColor: sketchLineColor.uiColor,
                pointLabelFontSizePx: segmentMeasureFontSizePx,
                pointMarkerStyle: pointMarkerStyle
            )
                .frame(maxHeight: .infinity)
        } else {
            // Apple-Karten: im Edit-Modus eine MKMapView verwenden, damit Punkte wirklich verschiebbar sind.
            if isRedrawMode {
                SketchAppleMapEditView(
                    region: mapRegion,
                    mapType: appleMapType(for: mapStyleOption),
                    points: $draftPoints,
                    selectedIndex: $selectedDraftIndex,
                    lineColor: sketchLineColor.uiColor,
                    hideIntermediatePoints: hideIntermediatePoints,
                    showSegmentMeasures: effectiveShowSegmentMeasures,
                    segmentMeters: segmentMetersForDisplay(points: corrected),
                    segmentLabelFontSizePx: segmentMeasureFontSizePx,
                    pointLabelStyle: .letters,
                    pointMarkerStyle: pointMarkerStyle
                )
                .frame(maxHeight: .infinity)
            } else {
                Map(position: .constant(.region(mapRegion)), interactionModes: .all) {
                    MapPolyline(coordinates: corrected)
                        .stroke(sketchLineColor.swiftUIColor, lineWidth: 4)
                    if effectiveShowSegmentMeasures {
                        ForEach(Array(segmentMetersForDisplay(points: corrected).enumerated()), id: \.offset) { i, meters in
                            if i + 1 < corrected.count {
                                let a = corrected[i]
                                let b = corrected[i + 1]
                                let mid = CLLocationCoordinate2D(
                                    latitude: (a.latitude + b.latitude) / 2,
                                    longitude: (a.longitude + b.longitude) / 2
                                )
                                Annotation("", coordinate: mid) {
                                    Text("\(meters, specifier: "%.2f") m")
                                        .font(.system(size: segmentMeasureFontSizePx, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.black.opacity(0.55))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                    ForEach(annotationIndices(for: corrected), id: \.self) { i in
                        let coord = corrected[i]
                        Annotation("", coordinate: coord) {
                            sketchPointMarker(index: i)
                        }
                    }
                }
                .mapStyle(mapStyleOption.mapStyle)
                // SwiftUI-Map cached Annotation-Views teils aggressiv; erzwingt Rebuild bei Stilwechsel.
                .id("apple-map-\(mapStyleOption.rawValue)-\(pointMarkerStyle.rawValue)-\(Int(segmentMeasureFontSizePx))-\(corrected.count)")
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func annotationIndices(for corrected: [CLLocationCoordinate2D]) -> [Int] {
        guard corrected.count >= 2 else { return [] }
        return Array(0..<corrected.count)
    }

    private func sketchPointMarker(index: Int) -> some View {
        let markerSize: CGFloat = max(14, min(40, CGFloat(segmentMeasureFontSizePx) + 8))
        let requestedLabelSize = CGFloat(max(6, min(24, segmentMeasureFontSizePx)))
        let fittedLabelSize = min(requestedLabelSize, markerSize * 0.58) // immer innerhalb des Kreises
        let fillColor = Color(pointMarkerStyle.fillColor)
        let borderColor = Color(pointMarkerStyle.borderColor)
        let textColor = Color(pointMarkerStyle.textColor)
        let strokeColor = Color(pointMarkerStyle.textStrokeColor)
        return ZStack {
            Circle()
                .fill(fillColor)
                .frame(width: markerSize, height: markerSize)
                .overlay(Circle().stroke(borderColor, lineWidth: 1))
            ZStack {
                Text(index < 26 ? String(Unicode.Scalar(65 + index)!) : "\(index + 1)")
                    .font(.system(size: fittedLabelSize, weight: .bold))
                    .foregroundStyle(strokeColor)
                Text(index < 26 ? String(Unicode.Scalar(65 + index)!) : "\(index + 1)")
                    .font(.system(size: fittedLabelSize, weight: .bold))
                    .foregroundStyle(textColor)
            }
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
            if measurement.polylineSegmentMeters?.isEmpty == false {
                Picker("Darstellung", selection: $useARSegmentsStraight) {
                    Text("AR‑Meter (gerade)").tag(true)
                    Text("GPS/RTK").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: useARSegmentsStraight) { _, _ in
                    // Wenn nicht im Nachzeichnen: sofort die Basislinie wechseln
                    if !isRedrawMode {
                        draftPoints = basePoints
                    }
                }
            }
            Toggle("Zwischenpunkte ausblenden (Start/Ende + ausgewählter Punkt)", isOn: $hideIntermediatePoints)
            Toggle("Maße zwischen Punkten anzeigen", isOn: $showSegmentMeasures)
            Picker("Messpunkt-Stil", selection: $pointMarkerStyle) {
                ForEach(PointMarkerStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.menu)
            if mapStyleOption == .imagery || mapStyleOption == .hybrid {
                Toggle("Nur Bezeichnung der Messpunkte anzeigen", isOn: $showPointLabelsOnly)
                    .onChange(of: showPointLabelsOnly) { _, on in
                        if on { showSegmentMeasures = false }
                    }
            }
            HStack {
                Text("Bemaßung Schriftgröße")
                Spacer()
                Text("\(segmentMeasureFontSizePx, specifier: "%.0f") px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .opacity((showPointLabelsOnly && (mapStyleOption == .imagery || mapStyleOption == .hybrid)) ? 0.45 : 1.0)
            Slider(value: $segmentMeasureFontSizePx, in: 1...24, step: 1)
                .disabled(showPointLabelsOnly && (mapStyleOption == .imagery || mapStyleOption == .hybrid))
            Picker("Linienfarbe", selection: $sketchLineColor) {
                ForEach(SketchLineColor.allCases) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            .pickerStyle(.menu)
            Text(String(format: "Gesamtlänge: %.2f m", totalLengthMetersForDisplay))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Toggle("Neu nachzeichnen (Tippen auf Karte)", isOn: $isRedrawMode)
                .onChange(of: isRedrawMode) { _, on in
                    if on {
                        // Start mit vorhandenen Punkten als Basis
                        draftPoints = basePoints
                        // Tipp: beim Nachzeichnen sind wenige Punkte oft besser
                    }
                }
            if isRedrawMode {
                HStack(spacing: 12) {
                    Text("Punkte: \(draftPoints.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Vollbild") {
                        showFullscreenEditor = true
                    }
                    .buttonStyle(.bordered)
                    Button("Undo") {
                        if !draftPoints.isEmpty { draftPoints.removeLast() }
                    }
                    .buttonStyle(.bordered)
                    Button("Neu starten") {
                        draftPoints.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
                if let sel = selectedDraftIndex, sel >= 0, sel < draftPoints.count {
                    HStack(spacing: 12) {
                        Text("Ausgewählt: \(sel + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Löschen") {
                            draftPoints.remove(at: sel)
                            selectedDraftIndex = nil
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            } else {
                Button("Glätten (GPS-Jitter reduzieren)") {
                    // RDP-Simplify: reduziert Zacken, behält Form (Start/Ende fix)
                    let simplified = simplifyRDP(points: basePoints, epsilonMeters: 0.25)
                    draftPoints = simplified
                    isRedrawMode = true
                }
                .buttonStyle(.bordered)
            }
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
                    useARSegmentsStraight = measurement.sketchUseARSegments
                        ?? ((measurement.polylineSegmentMeters?.isEmpty == false) ? true : false)
                    draftPoints = basePoints
                    isRedrawMode = false
                    selectedDraftIndex = nil
                }
                .buttonStyle(.bordered)
                Button("Korrektur übernehmen") {
                    var m = measurement
                    m.sketchOffsetLat = offsetLat
                    m.sketchOffsetLon = offsetLon
                    m.sketchRotationDegrees = rotationDegrees
                    m.sketchScale = scale
                    m.sketchMirrored = mirrored
                    m.sketchUseARSegments = useARSegmentsStraight
                    // Override nur setzen, wenn wir tatsächlich eine editierte Linie haben (>=2 Punkte).
                    if draftPoints.count >= 2 {
                        m.sketchOverridePolylinePoints = draftPoints.map { PolylinePoint(latitude: $0.latitude, longitude: $0.longitude) }
                    }
                    measurement = m
                    onSave(m)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial)
        .fullScreenCover(isPresented: $showFullscreenEditor) {
            if mapStyleOption == .mapLibre {
                FullscreenSketchPolylineEditorView(
                    region: mapRegion,
                    points: $draftPoints,
                    selectedIndex: $selectedDraftIndex,
                    hideIntermediatePoints: $hideIntermediatePoints,
                    segmentLabelFontSizePx: segmentMeasureFontSizePx,
                    totalLengthMeters: totalLengthMetersForDisplay,
                    lineColor: sketchLineColor,
                    pointMarkerStyle: pointMarkerStyle,
                    onSaveAerialPhoto: onSaveAerialPhoto,
                    onDone: { showFullscreenEditor = false }
                )
            } else {
                FullscreenSketchPolylineEditorAppleView(
                    region: mapRegion,
                    mapType: appleMapType(for: mapStyleOption),
                    points: $draftPoints,
                    selectedIndex: $selectedDraftIndex,
                    hideIntermediatePoints: $hideIntermediatePoints,
                    showSegmentMeasures: $showSegmentMeasures,
                    showPointLabelsOnly: $showPointLabelsOnly,
                    segmentLabelFontSizePx: segmentMeasureFontSizePx,
                    totalLengthMeters: totalLengthMetersForDisplay,
                    lineColor: sketchLineColor,
                    pointMarkerStyle: pointMarkerStyle,
                    onSaveAerialPhoto: onSaveAerialPhoto,
                    onDone: { showFullscreenEditor = false }
                )
            }
        }
    }
}

// MARK: - Vollbild Editor (Punkte hinzufügen/verschieben/löschen)

private struct FullscreenSketchPolylineEditorView: View {
    var region: MKCoordinateRegion
    @Binding var points: [CLLocationCoordinate2D]
    @Binding var selectedIndex: Int?
    @Binding var hideIntermediatePoints: Bool
    var segmentLabelFontSizePx: Double
    var totalLengthMeters: Double
    var lineColor: SketchLineColor
    var pointMarkerStyle: PointMarkerStyle = .standard
    var onSaveAerialPhoto: ((UIImage, [CLLocationCoordinate2D]) -> Void)?
    var onDone: () -> Void

    @State private var tool: MapLibreEditTool = .select
    @State private var straightenMode: Bool = false
    @State private var straightenStartIndex: Int? = nil
    @State private var straightenEndIndex: Int? = nil
    @State private var isSavingAerialPhoto: Bool = false
    @State private var moveWholePolyline: Bool = false
    private var nudgeButtonScale: CGFloat {
        CGFloat(max(0.8, min(1.8, segmentLabelFontSizePx / 12.0)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Tipp: Gerät drehen → Querformat nutzt die Fläche besser (iOS kann das automatisch).
            SketchMapLibreView(
                region: region,
                coordinates: points,
                isEditMode: true,
                hideIntermediatePoints: hideIntermediatePoints,
                lineColor: lineColor.uiColor,
                segmentLabelFontSizePx: segmentLabelFontSizePx,
                pointMarkerStyle: pointMarkerStyle,
                onTapAddPoint: { points.append($0) },
                selectedIndex: selectedIndex,
                onSelectPoint: { idx in
                    selectedIndex = idx
                    guard straightenMode, let idx else { return }
                    if straightenStartIndex == nil || (straightenStartIndex != nil && straightenEndIndex != nil) {
                        straightenStartIndex = idx
                        straightenEndIndex = nil
                    } else if straightenStartIndex != nil && straightenEndIndex == nil {
                        straightenEndIndex = idx
                    }
                },
                onMovePoint: { idx, coord in
                    guard idx >= 0, idx < points.count else { return }
                    points[idx] = coord
                },
                tool: tool
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: "Gesamtlänge: %.2f m", totalLengthMeters))
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 12)
                Spacer()
            }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button { onDone() } label: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Picker("", selection: $tool) {
                        ForEach(MapLibreEditTool.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        hideIntermediatePoints.toggle()
                    } label: {
                        Image(systemName: hideIntermediatePoints ? "eye.slash.fill" : "eye.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(hideIntermediatePoints ? "Zwischenpunkte ausblenden" : "Zwischenpunkte einblenden")

                    Button {
                        straightenMode.toggle()
                        straightenStartIndex = nil
                        straightenEndIndex = nil
                    } label: {
                        Image(systemName: straightenMode ? "line.diagonal.circle.fill" : "line.diagonal")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        applyStraightenIfPossible()
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!(straightenMode && straightenStartIndex != nil && straightenEndIndex != nil))

                    Button {
                        if !points.isEmpty { points.removeLast() }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        points.removeAll()
                        selectedIndex = nil
                        straightenStartIndex = nil
                        straightenEndIndex = nil
                    } label: {
                        Image(systemName: "trash.slash")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if let sel = selectedIndex, sel >= 0, sel < points.count {
                            points.remove(at: sel)
                            selectedIndex = nil
                            if straightenStartIndex == sel { straightenStartIndex = nil }
                            if straightenEndIndex == sel { straightenEndIndex = nil }
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(selectedIndex == nil)

                    Button {
                        moveWholePolyline.toggle()
                    } label: {
                        Image(systemName: moveWholePolyline ? "rectangle.3.group.fill" : "scope")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(moveWholePolyline ? "Gesamte Polylinie verschieben" : "Einzelpunkt verschieben")

                    if moveWholePolyline || (selectedIndex != nil) {
                        HStack(spacing: 4) {
                            HoldRepeatNudgeButton(
                                systemImage: "arrowtriangle.up.fill",
                                uiScale: nudgeButtonScale,
                                onTap: { nudgeWithMode(dLat: +region.span.latitudeDelta / 625, dLon: 0) },
                                onFastRepeat: { nudgeWithMode(dLat: +region.span.latitudeDelta / 312, dLon: 0) }
                            )
                            HoldRepeatNudgeButton(
                                systemImage: "arrowtriangle.down.fill",
                                uiScale: nudgeButtonScale,
                                onTap: { nudgeWithMode(dLat: -region.span.latitudeDelta / 625, dLon: 0) },
                                onFastRepeat: { nudgeWithMode(dLat: -region.span.latitudeDelta / 312, dLon: 0) }
                            )
                            HoldRepeatNudgeButton(
                                systemImage: "arrowtriangle.left.fill",
                                uiScale: nudgeButtonScale,
                                onTap: { nudgeWithMode(dLat: 0, dLon: -region.span.longitudeDelta / 625) },
                                onFastRepeat: { nudgeWithMode(dLat: 0, dLon: -region.span.longitudeDelta / 312) }
                            )
                            HoldRepeatNudgeButton(
                                systemImage: "arrowtriangle.right.fill",
                                uiScale: nudgeButtonScale,
                                onTap: { nudgeWithMode(dLat: 0, dLon: +region.span.longitudeDelta / 625) },
                                onFastRepeat: { nudgeWithMode(dLat: 0, dLon: +region.span.longitudeDelta / 312) }
                            )
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55))
                .padding(.top, 12)
                Spacer()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 12) {
                if let _ = onSaveAerialPhoto {
                    Button {
                        saveAerialPhotoFromCurrentScreen()
                    } label: {
                        if isSavingAerialPhoto {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Label("Zwischenstand speichern", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSavingAerialPhoto || points.count < 2)
                }
            }
            .padding(.trailing, 14)
            .padding(.bottom, 18)
        }
    }

    private func nudgeWithMode(dLat: Double, dLon: Double) {
        if moveWholePolyline {
            nudgeAll(dLat: dLat, dLon: dLon)
        } else if let sel = selectedIndex, sel >= 0, sel < points.count {
            nudgeSelected(index: sel, dLat: dLat, dLon: dLon)
        }
    }

    private func saveAerialPhotoFromCurrentScreen() {
        guard let onSaveAerialPhoto else { return }
        guard points.count >= 2 else { return }

        isSavingAerialPhoto = true
        let pointsToSave = points
        let totalMetersToSave = totalLengthMeters

        if let screenshot = captureCurrentScreenImage() {
            isSavingAerialPhoto = false
            onSaveAerialPhoto(screenshot, pointsToSave)
            return
        }

        // Fallback: wenn System-Screenshot fehlschlägt, weiter lokal rendern.
        let fallback = renderFallbackPolylineImage(
            points: pointsToSave,
            totalMeters: totalMetersToSave,
            lineColor: lineColor.uiColor,
            pointMarkerStyle: pointMarkerStyle,
            size: CGSize(width: 1200, height: 800)
        )
        isSavingAerialPhoto = false
        onSaveAerialPhoto(fallback, pointsToSave)
    }

    private func captureCurrentScreenImage() -> UIImage? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        guard let window = scene.windows.first(where: { $0.isKeyWindow }) else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            // afterScreenUpdates = true nimmt den aktuellen dargestellten Zustand inkl. Overlays mit.
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func renderFallbackPolylineImage(
        points: [CLLocationCoordinate2D],
        totalMeters: Double,
        lineColor: UIColor,
        pointMarkerStyle: PointMarkerStyle,
        size: CGSize
    ) -> UIImage {
        let w = max(320, size.width)
        let h = max(240, size.height)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))

            guard points.count >= 2 else { return }
            let lats = points.map(\.latitude)
            let lons = points.map(\.longitude)
            guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return }
            let latSpan = max(0.00001, maxLat - minLat)
            let lonSpan = max(0.00001, maxLon - minLon)
            let pad: CGFloat = 24

            func p(_ c: CLLocationCoordinate2D) -> CGPoint {
                let u = (c.longitude - minLon) / lonSpan
                let v = (maxLat - c.latitude) / latSpan
                return CGPoint(x: pad + CGFloat(u) * (w - 2 * pad), y: pad + CGFloat(v) * (h - 2 * pad))
            }

            let pts = points.map(p)
            cg.setStrokeColor(lineColor.cgColor)
            cg.setLineWidth(3)
            cg.addLines(between: pts)
            cg.strokePath()

            if let first = pts.first {
                cg.setFillColor(UIColor.systemGreen.cgColor)
                cg.fillEllipse(in: CGRect(x: first.x - 5, y: first.y - 5, width: 10, height: 10))
            }
            if let last = pts.last {
                cg.setFillColor(UIColor.systemRed.cgColor)
                cg.fillEllipse(in: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10))
            }

            // Alle Messpunkte inkl. Buchstaben deutlich darstellen.
            for (i, p) in pts.enumerated() {
                let markerSize: CGFloat = 14
                let r = markerSize / 2
                let fill: UIColor = (i == 0) ? .systemGreen : (i == pts.count - 1 ? .systemRed : pointMarkerStyle.fillColor)
                cg.setFillColor(fill.cgColor)
                cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: markerSize, height: markerSize))
                cg.setStrokeColor(pointMarkerStyle.borderColor.cgColor)
                cg.setLineWidth(1)
                cg.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: markerSize, height: markerSize))

                let label = i < 26 ? String(Unicode.Scalar(65 + i)!) : "\(i + 1)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 9),
                    .foregroundColor: pointMarkerStyle.textColor,
                    .strokeColor: pointMarkerStyle.textStrokeColor,
                    .strokeWidth: -2
                ]
                let size = (label as NSString).size(withAttributes: attrs)
                (label as NSString).draw(
                    at: CGPoint(x: p.x - size.width / 2, y: p.y - size.height / 2),
                    withAttributes: attrs
                )
            }

            let text = String(format: "Gesamtlänge: %.2f m", totalMeters)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 20),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -3
            ]
            (text as NSString).draw(at: CGPoint(x: 16, y: 12), withAttributes: attrs)
        }
    }

    private func nudgeSelected(index: Int, dLat: Double, dLon: Double) {
        guard index >= 0, index < points.count else { return }
        let c = points[index]
        points[index] = CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
        selectedIndex = index
    }

    private func nudgeAll(dLat: Double, dLon: Double) {
        guard !points.isEmpty else { return }
        for i in points.indices {
            let c = points[i]
            points[i] = CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
        }
    }

    private func dpad(
        onUp: @escaping () -> Void,
        onDown: @escaping () -> Void,
        onLeft: @escaping () -> Void,
        onRight: @escaping () -> Void,
        onUpFast: @escaping () -> Void,
        onDownFast: @escaping () -> Void,
        onLeftFast: @escaping () -> Void,
        onRightFast: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            HoldRepeatNudgeButton(
                systemImage: "arrowtriangle.up.fill",
                onTap: onUp,
                onFastRepeat: onUpFast,
                holdDelay: 0.2,
                repeatInterval: 0.035
            )
            HStack(spacing: 8) {
                HoldRepeatNudgeButton(
                    systemImage: "arrowtriangle.left.fill",
                    onTap: onLeft,
                    onFastRepeat: onLeftFast,
                    holdDelay: 0.2,
                    repeatInterval: 0.035
                )
                HoldRepeatNudgeButton(
                    systemImage: "arrowtriangle.right.fill",
                    onTap: onRight,
                    onFastRepeat: onRightFast,
                    holdDelay: 0.2,
                    repeatInterval: 0.035
                )
            }
            HoldRepeatNudgeButton(
                systemImage: "arrowtriangle.down.fill",
                onTap: onDown,
                onFastRepeat: onDownFast,
                holdDelay: 0.2,
                repeatInterval: 0.035
            )
        }
        .padding(10)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func applyStraightenIfPossible() {
        guard let aIdx = straightenStartIndex, let bIdx = straightenEndIndex else { return }
        guard aIdx >= 0, bIdx >= 0, aIdx < points.count, bIdx < points.count else { return }
        if aIdx == bIdx { return }
        let lo = min(aIdx, bIdx)
        let hi = max(aIdx, bIdx)
        guard hi - lo >= 2 else { return }
        let a = points[lo]
        let b = points[hi]
        let n = Double(hi - lo)
        for i in (lo + 1)..<hi {
            let t = Double(i - lo) / n
            let lat = a.latitude + (b.latitude - a.latitude) * t
            let lon = a.longitude + (b.longitude - a.longitude) * t
            points[i] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        selectedIndex = hi
    }
}

// MARK: - Apple Map Editor (Satellit/Hybrid/Standard) mit Werkzeugleiste oben

private enum AppleEditTool: String, CaseIterable {
    case select = "Punkt auswählen"
    case add = "Neuen Punkt setzen"
}

/// Wählt eine sinnvolle Text-Position "nahe an der Polylinie": Mittelpunkt des längsten Segments
/// plus kleiner Versatz senkrecht zur Segmentrichtung (ober-/unterhalb).
private func polylineLabelAnchor(_ points: [CGPoint], offsetPixels: CGFloat, preferBelow: Bool) -> CGPoint? {
    guard points.count >= 2 else { return nil }
    var bestI = 0
    var bestLen: CGFloat = 0
    for i in 0..<(points.count - 1) {
        let a = points[i]
        let b = points[i + 1]
        let len = hypot(b.x - a.x, b.y - a.y)
        if len > bestLen {
            bestLen = len
            bestI = i
        }
    }
    let a = points[bestI]
    let b = points[bestI + 1]
    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)

    // Normalen-Vektor (perp) für "ober/unter"
    let dx = b.x - a.x
    let dy = b.y - a.y
    let segLen = max(0.001, hypot(dx, dy))
    // Normale nach "links" = (-dy, dx)
    var nx = -dy / segLen
    var ny = dx / segLen
    if preferBelow {
        // In iOS-Koordinaten zeigt +y nach unten → "below" = +y Richtung.
        if ny < 0 { nx *= -1; ny *= -1 }
    } else {
        if ny > 0 { nx *= -1; ny *= -1 }
    }
    let anchor = CGPoint(x: mid.x + nx * offsetPixels, y: mid.y + ny * offsetPixels)

    // Linksbündig zeichnen: etwas nach rechts schieben, damit es nicht "auf" dem Segment startet
    return CGPoint(x: anchor.x + 6, y: anchor.y - 10)
}

private struct FullscreenSketchPolylineEditorAppleView: View {
    var region: MKCoordinateRegion
    var mapType: MKMapType
    @Binding var points: [CLLocationCoordinate2D]
    @Binding var selectedIndex: Int?
    @Binding var hideIntermediatePoints: Bool
    @Binding var showSegmentMeasures: Bool
    @Binding var showPointLabelsOnly: Bool
    var segmentLabelFontSizePx: Double
    var totalLengthMeters: Double
    var lineColor: SketchLineColor
    var pointMarkerStyle: PointMarkerStyle = .standard
    var onSaveAerialPhoto: ((UIImage, [CLLocationCoordinate2D]) -> Void)?
    var onDone: () -> Void

    @State private var tool: AppleEditTool = .select
    @State private var snapshot: MKMapSnapshotter.Snapshot?
    @State private var isLoadingSnapshot: Bool = false
    @State private var snapshotError: String?
    @State private var isSavingAerialPhoto: Bool = false
    @State private var saveRequestId: Int = 0
    @State private var straightenMode: Bool = false
    @State private var straightenStartIndex: Int? = nil
    @State private var straightenEndIndex: Int? = nil

    var body: some View {
        ZStack(alignment: .top) {
            SnapshotSketchEditorView(
                snapshot: $snapshot,
                isLoading: $isLoadingSnapshot,
                errorMessage: $snapshotError,
                region: region,
                mapType: mapType,
                tool: tool,
                points: $points,
                selectedIndex: $selectedIndex,
                hideIntermediatePoints: hideIntermediatePoints,
                showSegmentMeasures: showSegmentMeasures && !showPointLabelsOnly,
                showPointLabelsOnly: showPointLabelsOnly,
                lineColor: lineColor.uiColor,
                totalLengthMeters: totalLengthMeters,
                segmentLabelFontSizePx: segmentLabelFontSizePx,
                pointMarkerStyle: pointMarkerStyle,
                saveRequestId: saveRequestId,
                onSaveAerialPhoto: onSaveAerialPhoto,
                onSavingStateChange: { isSavingAerialPhoto = $0 },
                onPointSelected: { idx in
                    guard straightenMode, let idx else { return }
                    if straightenStartIndex == nil || (straightenStartIndex != nil && straightenEndIndex != nil) {
                        straightenStartIndex = idx
                        straightenEndIndex = nil
                    } else if straightenStartIndex != nil && straightenEndIndex == nil {
                        straightenEndIndex = idx
                    }
                }
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: "Gesamtlänge: %.2f m", totalLengthMeters))
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 12)
                Spacer()
            }

            HStack(spacing: 10) {
                Button { onDone() } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Picker("", selection: $tool) {
                    ForEach(AppleEditTool.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    hideIntermediatePoints.toggle()
                } label: {
                    Image(systemName: hideIntermediatePoints ? "eye.slash.fill" : "eye.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Zwischenpunkte ausblenden an/aus")

                Button {
                    straightenMode.toggle()
                    straightenStartIndex = nil
                    straightenEndIndex = nil
                } label: {
                    Image(systemName: straightenMode ? "line.diagonal.circle.fill" : "line.diagonal")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Gerade verbinden (2 Punkte wählen)")

                Button {
                    applyStraightenIfPossible()
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .disabled(!(straightenMode && straightenStartIndex != nil && straightenEndIndex != nil))
                .accessibilityLabel("Zwischenpunkte auf Gerade setzen")

                Button {
                    snapshot = nil
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    if !points.isEmpty { points.removeLast() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)

                Button {
                    points.removeAll()
                    selectedIndex = nil
                    straightenStartIndex = nil
                    straightenEndIndex = nil
                } label: {
                    Image(systemName: "trash.slash")
                }
                .buttonStyle(.bordered)

                Button {
                    if let sel = selectedIndex, sel >= 0, sel < points.count {
                        points.remove(at: sel)
                        selectedIndex = nil
                        if straightenStartIndex == sel { straightenStartIndex = nil }
                        if straightenEndIndex == sel { straightenEndIndex = nil }
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(selectedIndex == nil)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55))
        }
        .overlay(alignment: .bottomTrailing) {
            if let _ = onSaveAerialPhoto {
                Button {
                    guard !isSavingAerialPhoto else { return }
                    isSavingAerialPhoto = true
                    saveRequestId += 1
                } label: {
                    if isSavingAerialPhoto {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Label("Zwischenstand speichern", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingAerialPhoto || points.count < 2 || snapshot == nil)
                .padding(.trailing, 14)
                .padding(.bottom, 18)
            }
        }
        .task(id: "\(region.center.latitude)-\(region.center.longitude)-\(region.span.latitudeDelta)-\(region.span.longitudeDelta)-\(mapType.rawValue)") {
            await loadSnapshotIfNeeded()
        }
    }

    private func applyStraightenIfPossible() {
        guard let aIdx = straightenStartIndex, let bIdx = straightenEndIndex else { return }
        guard aIdx >= 0, bIdx >= 0, aIdx < points.count, bIdx < points.count else { return }
        if aIdx == bIdx { return }
        let lo = min(aIdx, bIdx)
        let hi = max(aIdx, bIdx)
        guard hi - lo >= 2 else { return }
        let a = points[lo]
        let b = points[hi]
        let n = Double(hi - lo)
        for i in (lo + 1)..<hi {
            let t = Double(i - lo) / n
            let lat = a.latitude + (b.latitude - a.latitude) * t
            let lon = a.longitude + (b.longitude - a.longitude) * t
            points[i] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        selectedIndex = hi
    }

    private func loadSnapshotIfNeeded() async {
        if snapshot != nil || isLoadingSnapshot { return }
        isLoadingSnapshot = true
        snapshotError = nil
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.mapType = mapType
        options.showsBuildings = true
        options.pointOfInterestFilter = .excludingAll
        options.size = CGSize(width: 2048, height: 2048)
        let snapshotter = MKMapSnapshotter(options: options)
        if #available(iOS 16.0, *) {
            Task { @MainActor in
                do {
                    let snap = try await snapshotter.start()
                    isLoadingSnapshot = false
                    snapshot = snap
                } catch {
                    isLoadingSnapshot = false
                    snapshotError = error.localizedDescription
                }
            }
        } else {
            snapshotter.start { snap, error in
                DispatchQueue.main.async {
                    isLoadingSnapshot = false
                    if let snap {
                        snapshot = snap
                    } else {
                        snapshotError = error?.localizedDescription ?? "Snapshot fehlgeschlagen."
                    }
                }
            }
        }
    }
}

/// Editor über hochauflösendem MapSnapshot: Punkte als Overlay, beliebig reinzoomen/pannen, Punkte auswählen/verschieben/löschen/hinzufügen.
private struct SnapshotSketchEditorView: View {
    @Binding var snapshot: MKMapSnapshotter.Snapshot?
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    var region: MKCoordinateRegion
    var mapType: MKMapType
    var tool: AppleEditTool
    @Binding var points: [CLLocationCoordinate2D]
    @Binding var selectedIndex: Int?
    var hideIntermediatePoints: Bool
    var showSegmentMeasures: Bool
    var showPointLabelsOnly: Bool
    var lineColor: UIColor
    var totalLengthMeters: Double
    var segmentLabelFontSizePx: Double
    var pointMarkerStyle: PointMarkerStyle = .standard
    var saveRequestId: Int
    var onSaveAerialPhoto: ((UIImage, [CLLocationCoordinate2D]) -> Void)?
    var onSavingStateChange: ((Bool) -> Void)?
    var onPointSelected: ((Int?) -> Void)? = nil

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let globalOrigin = geo.frame(in: .global).origin
            ZStack {
                Color.black.ignoresSafeArea()

                if let snap = snapshot {
                    let img = snap.image
                    let imgSize = img.size
                    let container = geo.size
                    let fit = aspectFitSize(image: imgSize, in: container)
                    let baseOrigin = CGPoint(x: (container.width - fit.width) / 2, y: (container.height - fit.height) / 2)
                    let center = CGPoint(x: container.width / 2, y: container.height / 2)
                    let visibleIndices = visiblePointIndices(count: points.count, selectedIndex: selectedIndex, hideIntermediatePoints: hideIntermediatePoints)

                    // Bild + Overlay gemeinsam transformieren (Zoom/Pan), damit die Rückrechnung stabil ist.
                    ZStack {
                        // Hintergrundbild
                        Image(uiImage: img)
                            .resizable()
                            .frame(width: fit.width, height: fit.height)
                            .position(x: container.width / 2, y: container.height / 2)

                        // Polyline
                        Canvas { context, _ in
                            if points.count >= 2 {
                                var path = Path()
                                for (i, c) in points.enumerated() {
                                    let pImg = snap.point(for: c)
                                    let pScreen = imageToScreenPoint(pImg, imageSize: snap.image.size, baseOrigin: baseOrigin, fitSize: fit)
                                    if i == 0 { path.move(to: pScreen) } else { path.addLine(to: pScreen) }
                                }
                                // Linienbreite soll auch bei Zoom "dünn" bleiben → gegen Zoom kompensieren.
                                context.stroke(path, with: .color(Color(lineColor)), lineWidth: max(0.2, 0.5 / max(1, scale)))
                            }

                            if showSegmentMeasures, points.count >= 2 {
                                // Nutzerdefinierte Schriftgröße (px) – gegen Zoom kompensiert.
                                let invScale = 1 / max(1, scale)
                                let baseFont = CGFloat(max(1, segmentLabelFontSizePx))
                                let strokeW = max(0.2, 1.0 * invScale)
                                let fontSize = max(1, baseFont * invScale)
                                let seg = segmentMeters(points: points, fallbackTotalMeters: totalLengthMeters)
                                for i in 0..<(min(seg.count, points.count - 1)) {
                                    let a = points[i]
                                    let b = points[i + 1]
                                    let mid = CLLocationCoordinate2D(
                                        latitude: (a.latitude + b.latitude) / 2,
                                        longitude: (a.longitude + b.longitude) / 2
                                    )
                                    let pImg = snap.point(for: mid)
                                    let pScreen = imageToScreenPoint(pImg, imageSize: snap.image.size, baseOrigin: baseOrigin, fitSize: fit)
                                    let txt = Text("\(seg[i], specifier: "%.2f") m")
                                        .font(.system(size: fontSize, weight: .bold))
                                        .foregroundStyle(.white)
                                    let resolved = context.resolve(txt)
                                    let pad: CGFloat = max(0.5, max(2, baseFont * 0.35) * invScale)
                                    let size = resolved.measure(in: CGSize(width: 300, height: 100))
                                    let rect = CGRect(
                                        x: pScreen.x - size.width / 2 - pad,
                                        y: pScreen.y - size.height / 2 - pad,
                                        width: size.width + 2 * pad,
                                        height: size.height + 2 * pad
                                    )
                                    let cr = max(0.5, 2 * invScale)
                                    context.fill(Path(roundedRect: rect, cornerRadius: cr), with: .color(.black.opacity(0.45)))
                                    context.stroke(Path(roundedRect: rect, cornerRadius: cr), with: .color(.white.opacity(0.4)), lineWidth: strokeW)
                                    context.draw(resolved, at: CGPoint(x: pScreen.x, y: pScreen.y))
                                }
                            }
                        }
                        .allowsHitTesting(false)

                        // Punkte
                        ForEach(visibleIndices, id: \.self) { i in
                            let pImg = snap.point(for: points[i])
                            let pScreen = imageToScreenPoint(pImg, imageSize: snap.image.size, baseOrigin: baseOrigin, fitSize: fit)
                            // Marker sollen bei Zoom kleiner werden: in der transformierten Gruppe Größe gegen Zoom kompensieren.
                            let baseMarker = max(14, min(40, CGFloat(segmentLabelFontSizePx) + 8))
                            let markerSize = max(1, baseMarker / max(1, scale))
                            let requestedPointLabelSize = CGFloat(segmentLabelFontSizePx) / max(1, scale)
                            let fittedPointLabelSize = min(max(5, requestedPointLabelSize), markerSize * 0.58)
                            Circle()
                                .fill(i == selectedIndex ? Color.green : Color(pointMarkerStyle.fillColor))
                                .frame(width: markerSize, height: markerSize)
                                .overlay(Circle().stroke(Color(pointMarkerStyle.borderColor), lineWidth: max(0.2, 0.5 / max(1, scale))))
                                .overlay {
                                    ZStack {
                                        Text(i < 26 ? String(Unicode.Scalar(65 + i)!) : "\(i + 1)")
                                            .font(.system(size: fittedPointLabelSize, weight: .bold))
                                            .foregroundStyle(Color(pointMarkerStyle.textStrokeColor))
                                        Text(i < 26 ? String(Unicode.Scalar(65 + i)!) : "\(i + 1)")
                                            .font(.system(size: fittedPointLabelSize, weight: .bold))
                                            .foregroundStyle(Color(pointMarkerStyle.textColor))
                                    }
                                }
                                .position(pScreen)
                                .gesture(pointDragGesture(
                                    index: i,
                                    globalOrigin: globalOrigin,
                                    center: center,
                                    baseOrigin: baseOrigin,
                                    fitSize: fit,
                                    snap: snap
                                ))
                        }
                    }
                    .scaleEffect(scale, anchor: .center)
                    .offset(offset)

                    // Tap-Layer für Add/Select
                    Color.clear
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .global).onEnded { value in
                                let pt = CGPoint(x: value.location.x - globalOrigin.x, y: value.location.y - globalOrigin.y)
                                let basePt = screenToBasePoint(pt, center: center)
                                let imgPt01 = screenToImagePoint(basePt, baseOrigin: baseOrigin, fitSize: fit)
                                guard let imgPt01 else { return }

                                // nearest hit (bei starkem Zoom kleinerer Auswahlbereich, sonst trifft man nie den richtigen Punkt)
                                let hitRadius: CGFloat = max(6, 35 / max(1, scale))
                                if let (idx, d) = nearestPoint(to: basePt, baseOrigin: baseOrigin, fitSize: fit, snap: snap, allowedIndices: visibleIndices) {
                                    if d <= hitRadius {
                                        selectedIndex = idx
                                        onPointSelected?(idx)
                                        return
                                    }
                                }

                                guard tool == .add else { return }
                                let coord = coordinateFromSnapshotImagePoint(imgPt01, imageSize: snap.image.size)
                                points.append(coord)
                                selectedIndex = points.count - 1
                            }
                        )

                    // Pfeil-System zum exakten Bewegen des ausgewählten Punkts (1px Schritte).
                    if let sel = selectedIndex, sel >= 0, sel < points.count {
                        let nudgeButtonScale = CGFloat(max(0.8, min(1.8, segmentLabelFontSizePx / 12.0)))
                        VStack {
                            Spacer()
                            VStack(spacing: 8) {
                                HoldRepeatNudgeButton(
                                    systemImage: "arrowtriangle.up.fill",
                                    uiScale: nudgeButtonScale,
                                    onTap: { nudgeSelected(index: sel, dxPixels: 0, dyPixels: -4, fitSize: fit) },
                                    onFastRepeat: { nudgeSelected(index: sel, dxPixels: 0, dyPixels: -12, fitSize: fit) }
                                )
                                HStack(spacing: 8) {
                                    HoldRepeatNudgeButton(
                                        systemImage: "arrowtriangle.left.fill",
                                        uiScale: nudgeButtonScale,
                                        onTap: { nudgeSelected(index: sel, dxPixels: -4, dyPixels: 0, fitSize: fit) },
                                        onFastRepeat: { nudgeSelected(index: sel, dxPixels: -12, dyPixels: 0, fitSize: fit) }
                                    )
                                    HoldRepeatNudgeButton(
                                        systemImage: "arrowtriangle.right.fill",
                                        uiScale: nudgeButtonScale,
                                        onTap: { nudgeSelected(index: sel, dxPixels: 4, dyPixels: 0, fitSize: fit) },
                                        onFastRepeat: { nudgeSelected(index: sel, dxPixels: 12, dyPixels: 0, fitSize: fit) }
                                    )
                                }
                                HoldRepeatNudgeButton(
                                    systemImage: "arrowtriangle.down.fill",
                                    uiScale: nudgeButtonScale,
                                    onTap: { nudgeSelected(index: sel, dxPixels: 0, dyPixels: 4, fitSize: fit) },
                                    onFastRepeat: { nudgeSelected(index: sel, dxPixels: 0, dyPixels: 12, fitSize: fit) }
                                )
                            }
                            .padding(10)
                            .background(.black.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.leading, 14)
                            .padding(.bottom, 18)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                } else if isLoading {
                    ProgressView("Lade Luftbild…")
                        .foregroundStyle(.white)
                } else if let errorMessage {
                    VStack(spacing: 10) {
                        Text("Snapshot-Fehler")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ProgressView("Lade Luftbild…")
                        .foregroundStyle(.white)
                }
            }
            .onChange(of: saveRequestId) { newValue in
                guard newValue != 0 else { return }
                guard let snap = snapshot else { onSavingStateChange?(false); return }
                guard let onSaveAerialPhoto else { onSavingStateChange?(false); return }
                guard points.count >= 2 else {
                    onSavingStateChange?(false)
                    return
                }

                onSavingStateChange?(true)

                let pointsToSave = points
                let img = snap.image
                let imgSize = img.size
                let container = geo.size
                let fit = aspectFitSize(image: imgSize, in: container)
                let baseOrigin = CGPoint(x: (container.width - fit.width) / 2, y: (container.height - fit.height) / 2)
                let center = CGPoint(x: container.width / 2, y: container.height / 2)
                let visibleIndices = visiblePointIndices(
                    count: pointsToSave.count,
                    selectedIndex: selectedIndex,
                    hideIntermediatePoints: hideIntermediatePoints
                )

                let baseMarker = max(14, min(40, CGFloat(segmentLabelFontSizePx) + 8))
                let markerSize = max(1, baseMarker / max(1, scale))
                let strokeWidth = max(0.2, 0.5 / max(1, scale))
                let totalMetersToSave = totalLengthMeters

                let rendered = UIGraphicsImageRenderer(size: container).image { ctx in
                    let cg = ctx.cgContext
                    cg.setFillColor(UIColor.black.cgColor)
                    cg.fill(CGRect(origin: .zero, size: container))

                    cg.saveGState()
                    // Gleiche Transformationsreihenfolge wie in der View:
                    // scaleEffect(…, anchor: .center) um 'center' und dann offset(offset).
                    cg.translateBy(x: center.x + offset.width, y: center.y + offset.height)
                    cg.scaleBy(x: scale, y: scale)
                    cg.translateBy(x: -center.x, y: -center.y)

                    // Hintergrundbild
                    img.draw(in: CGRect(x: baseOrigin.x, y: baseOrigin.y, width: fit.width, height: fit.height))

                    // Polyline
                    if pointsToSave.count >= 2 {
                        let path = CGMutablePath()
                        for (i, c) in pointsToSave.enumerated() {
                            let pImg = snap.point(for: c)
                            let pScreen = imageToScreenPoint(pImg, imageSize: snap.image.size, baseOrigin: baseOrigin, fitSize: fit)
                            if i == 0 { path.move(to: pScreen) } else { path.addLine(to: pScreen) }
                        }
                        cg.addPath(path)
                        cg.setStrokeColor(lineColor.cgColor)
                        cg.setLineWidth(strokeWidth)
                        cg.strokePath()
                    }

                    // Punkte (Marker)
                    for i in visibleIndices {
                        let pImg = snap.point(for: pointsToSave[i])
                        let pScreen = imageToScreenPoint(pImg, imageSize: snap.image.size, baseOrigin: baseOrigin, fitSize: fit)

                        let fillColor: UIColor = (i == selectedIndex) ? .systemGreen : pointMarkerStyle.fillColor
                        cg.setFillColor(fillColor.cgColor)

                        let r = markerSize / 2
                        cg.fillEllipse(in: CGRect(x: pScreen.x - r, y: pScreen.y - r, width: markerSize, height: markerSize))

                        cg.setStrokeColor(pointMarkerStyle.borderColor.cgColor)
                        cg.setLineWidth(strokeWidth)
                        cg.strokeEllipse(in: CGRect(x: pScreen.x - r, y: pScreen.y - r, width: markerSize, height: markerSize))

                        // Messpunkt-Buchstabe deutlich in den Marker zeichnen.
                        let label = i < 26 ? String(Unicode.Scalar(65 + i)!) : "\(i + 1)"
                        // Gleiche Größenlogik wie im Live-Overlay: Reglergröße, gegen Zoom kompensiert, im Kreis begrenzt.
                        let requestedLabelSize = CGFloat(segmentLabelFontSizePx) / max(1, scale)
                        let labelSize = min(max(5, requestedLabelSize), markerSize * 0.58)
                        let labelAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.boldSystemFont(ofSize: labelSize),
                            .foregroundColor: pointMarkerStyle.textColor,
                            .strokeColor: pointMarkerStyle.textStrokeColor,
                            .strokeWidth: -2
                        ]
                        let txtSize = (label as NSString).size(withAttributes: labelAttrs)
                        let txtRect = CGRect(
                            x: pScreen.x - txtSize.width / 2,
                            y: pScreen.y - txtSize.height / 2,
                            width: txtSize.width,
                            height: txtSize.height
                        )
                        (label as NSString).draw(in: txtRect, withAttributes: labelAttrs)
                    }
                    cg.restoreGState()

                    // Gesamtlänge nahe an der Polylinie (Screen-Koordinaten, nicht mitzoomen)
                    let text = String(format: "Gesamtlänge: %.2f m", totalMetersToSave)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 18),
                        .foregroundColor: UIColor.white,
                        .strokeColor: UIColor.black,
                        .strokeWidth: -3
                    ]
                    // Punkte der Polylinie in Screen-Koordinaten (vor Transform!)
                    let screenPts = pointsToSave.map { c -> CGPoint in
                        let pImg = snap.point(for: c)
                        return imageToScreenPoint(pImg, imageSize: snap.image.size, baseOrigin: baseOrigin, fitSize: fit)
                    }
                    if let anchor = polylineLabelAnchor(screenPts, offsetPixels: 12, preferBelow: true) {
                        let size = (text as NSString).size(withAttributes: attrs)
                        let rect = CGRect(x: anchor.x, y: anchor.y, width: size.width, height: size.height)
                        (text as NSString).draw(in: rect, withAttributes: attrs)
                    }
                }

                DispatchQueue.main.async {
                    onSaveAerialPhoto(rendered, pointsToSave)
                    onSavingStateChange?(false)
                }
            }
            // Zoom/Pan sollen überall funktionieren, aber Taps fürs Setzen/Auswählen nicht blockieren.
            .simultaneousGesture(panGesture())
            .simultaneousGesture(zoomGesture())
        }
    }

    private func screenToBasePoint(_ screenPoint: CGPoint, center: CGPoint) -> CGPoint {
        // Inverse der Transformation: p_base = (p_screen - center - offset) / scale + center
        let x = (screenPoint.x - center.x - offset.width) / max(0.0001, scale) + center.x
        let y = (screenPoint.y - center.y - offset.height) / max(0.0001, scale) + center.y
        return CGPoint(x: x, y: y)
    }

    private func nudgeSelected(index: Int, dxPixels: CGFloat, dyPixels: CGFloat, fitSize: CGSize) {
        guard index >= 0, index < points.count else { return }
        // 1px in Screen => 1/scale in Base; dann über Fit-Größe in normierte UV umrechnen.
        let du = (dxPixels / max(1, scale)) / max(1, fitSize.width)
        let dv = (dyPixels / max(1, scale)) / max(1, fitSize.height)
        let c = points[index]
        let lon = c.longitude + Double(du) * region.span.longitudeDelta
        let lat = c.latitude - Double(dv) * region.span.latitudeDelta
        points[index] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        selectedIndex = index
    }

    private func segmentMeters(points: [CLLocationCoordinate2D], fallbackTotalMeters: Double) -> [Double] {
        guard points.count >= 2 else { return [] }
        let n = points.count - 1
        // Wenn wir keine Segmentmeter haben: gleichmäßig aus Gesamt verteilen (besser als nichts).
        let fallbackPer = (n > 0) ? (fallbackTotalMeters / Double(n)) : 0
        var out: [Double] = []
        out.reserveCapacity(n)
        for _ in 0..<n { out.append(fallbackPer) }
        return out
    }

    private func panGesture() -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { s in
                let next = lastScale * s
                scale = max(1.0, min(20.0, next))
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private func pointDragGesture(index: Int, globalOrigin: CGPoint, center: CGPoint, baseOrigin: CGPoint, fitSize: CGSize, snap: MKMapSnapshotter.Snapshot) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                guard index >= 0, index < points.count else { return }
                let pt = CGPoint(x: v.location.x - globalOrigin.x, y: v.location.y - globalOrigin.y)
                let basePt = screenToBasePoint(pt, center: center)
                if let imgPt01 = screenToImagePoint(basePt, baseOrigin: baseOrigin, fitSize: fitSize) {
                    points[index] = coordinateFromSnapshotImagePoint(imgPt01, imageSize: snap.image.size)
                    selectedIndex = index
                }
            }
    }

    private func aspectFitSize(image: CGSize, in container: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return container }
        let r = min(container.width / image.width, container.height / image.height)
        return CGSize(width: image.width * r, height: image.height * r)
    }

    private func imageToScreenPoint(_ imagePoint: CGPoint, imageSize: CGSize, baseOrigin: CGPoint, fitSize: CGSize) -> CGPoint {
        let imgW = fitSize.width
        let imgH = fitSize.height
        let iw = max(1, imageSize.width)
        let ih = max(1, imageSize.height)
        let u = imagePoint.x / iw
        let v = imagePoint.y / ih
        return CGPoint(x: baseOrigin.x + u * imgW, y: baseOrigin.y + v * imgH)
    }

    private func screenToImagePoint(_ screenPoint: CGPoint, baseOrigin: CGPoint, fitSize: CGSize) -> CGPoint? {
        let x = (screenPoint.x - baseOrigin.x)
        let y = (screenPoint.y - baseOrigin.y)
        guard x >= 0, y >= 0, x <= fitSize.width, y <= fitSize.height else { return nil }
        let u = x / fitSize.width
        let v = y / fitSize.height
        // Diese Koordinaten sind in der Snapshot-Bildkoordinate (Pixel/Points) – Umrechnung auf Bildgröße erfolgt beim Koordinatenmapping.
        return CGPoint(x: u, y: v)
    }

    private func nearestPoint(
        to screenPoint: CGPoint,
        baseOrigin: CGPoint,
        fitSize: CGSize,
        snap: MKMapSnapshotter.Snapshot,
        allowedIndices: [Int]? = nil
    ) -> (Int, CGFloat)? {
        guard !points.isEmpty else { return nil }
        var bestIdx = 0
        var bestD: CGFloat = .greatestFiniteMagnitude
        let indicesToCheck = allowedIndices ?? points.indices.map { $0 }
        for i in indicesToCheck {
            let pImg = snap.point(for: points[i])
            let pScreen = imageToScreenPoint(pImg, imageSize: snap.image.size, baseOrigin: baseOrigin, fitSize: fitSize)
            let d = hypot(pScreen.x - screenPoint.x, pScreen.y - screenPoint.y)
            if d < bestD {
                bestD = d
                bestIdx = i
            }
        }
        return (bestIdx, bestD)
    }

    private func visiblePointIndices(count: Int, selectedIndex: Int?, hideIntermediatePoints: Bool) -> [Int] {
        guard count > 0 else { return [] }
        if !hideIntermediatePoints || count <= 2 { return Array(0..<count) }
        let last = count - 1
        var set = Set<Int>([0, last])
        if let sel = selectedIndex, sel >= 0, sel < count {
            set.insert(sel)
        }
        return set.sorted()
    }

    /// Fallback-Mapping von Snapshot-Bildpunkt → Koordinate, ohne `snapshot.coordinate(for:)` (SDK-inkompatibel).
    /// `imgPoint01` ist hier normiert (0..1) aus `screenToImagePoint`.
    private func coordinateFromSnapshotImagePoint(_ imgPoint01: CGPoint, imageSize: CGSize) -> CLLocationCoordinate2D {
        // imgPoint01 ist normiert (0..1)
        let u = max(0, min(1, imgPoint01.x))
        let v = max(0, min(1, imgPoint01.y))
        let lon = region.center.longitude + (u - 0.5) * region.span.longitudeDelta
        let lat = region.center.latitude - (v - 0.5) * region.span.latitudeDelta
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

private func appleMapType(for style: SketchMapStyle) -> MKMapType {
    switch style {
    case .imagery: return .satellite
    case .hybrid: return .hybrid
    default: return .standard
    }
}

private enum PointLabelStyle {
    case numbers
    case letters
}

/// MKMapView Editor: Punkte auswählen (grün) + verschieben (Drag) + hinzufügen (je nach Tool).
private struct SketchAppleMapEditView: UIViewRepresentable {
    var region: MKCoordinateRegion
    var mapType: MKMapType
    @Binding var points: [CLLocationCoordinate2D]
    @Binding var selectedIndex: Int?
    var tool: AppleEditTool = .select
    var extraZoom: Double = 1.0
    var lineColor: UIColor = .systemBlue
    var hideIntermediatePoints: Bool = false
    var showSegmentMeasures: Bool = false
    var segmentMeters: [Double] = []
    var segmentLabelFontSizePx: Double = 12
    var pointLabelStyle: PointLabelStyle = .numbers
    var pointMarkerStyle: PointMarkerStyle = .standard

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = mapType
        map.isRotateEnabled = true
        map.isPitchEnabled = false
        map.setRegion(region, animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)

        context.coordinator.mapView = map
        context.coordinator.parent = self
        context.coordinator.reloadAll()
        context.coordinator.captureBaseAltitudeIfNeeded()
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        map.mapType = mapType
        // Im Edit-Modus NICHT ständig Region resetten (sonst springt Zoom/Pan).
        context.coordinator.captureBaseAltitudeIfNeeded()
        context.coordinator.applyExtraZoomIfNeeded(extraZoom: extraZoom)
        context.coordinator.reloadAll()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        var parent: SketchAppleMapEditView?
        private var baseAltitude: CLLocationDistance?
        private var lastAppliedZoom: Double = 1.0

        private final class IndexedAnnotation: MKPointAnnotation {
            var index: Int = 0
        }

        func captureBaseAltitudeIfNeeded() {
            guard baseAltitude == nil, let mapView else { return }
            // Nach setRegion ist eine sinnvolle Ausgangs-Höhe gesetzt.
            baseAltitude = max(50, mapView.camera.altitude)
            lastAppliedZoom = 1.0
        }

        func applyExtraZoomIfNeeded(extraZoom: Double) {
            guard let mapView, let baseAltitude else { return }
            let z = max(1.0, min(8.0, extraZoom))
            guard abs(z - lastAppliedZoom) >= 0.01 else { return }
            lastAppliedZoom = z

            // Größerer Zoom => kleinere altitude.
            var cam = mapView.camera
            cam.altitude = max(25, baseAltitude / z)
            mapView.setCamera(cam, animated: false)
        }

        func reloadAll() {
            guard let mapView, let parent else { return }
            mapView.removeOverlays(mapView.overlays)
            mapView.removeAnnotations(mapView.annotations)

            if parent.points.count >= 2 {
                let poly = MKPolyline(coordinates: parent.points, count: parent.points.count)
                mapView.addOverlay(poly)
            }

            let count = parent.points.count
            let last = max(0, count - 1)
            for i in 0..<count {
                if parent.hideIntermediatePoints, count > 2 {
                    let sel = parent.selectedIndex
                    if i != 0 && i != last && i != sel { continue }
                }
                let ann = IndexedAnnotation()
                ann.index = i
                ann.coordinate = parent.points[i]
                mapView.addAnnotation(ann)
            }

            if parent.showSegmentMeasures, parent.points.count >= 2 {
                for i in 0..<(parent.points.count - 1) {
                    guard i < parent.segmentMeters.count else { break }
                    let a = parent.points[i]
                    let b = parent.points[i + 1]
                    let mid = CLLocationCoordinate2D(
                        latitude: (a.latitude + b.latitude) / 2,
                        longitude: (a.longitude + b.longitude) / 2
                    )
                    let ann = MKPointAnnotation()
                    ann.coordinate = mid
                    ann.title = String(format: "%.2f m", parent.segmentMeters[i])
                    mapView.addAnnotation(ann)
                }
            }
        }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let mapView, let parent else { return }
            let pt = gr.location(in: mapView)

            // Hit-Test: wenn nahe an Annotation, selektieren (im Select-Tool)
            let hitRadius: CGFloat = 22
            if let nearest = mapView.annotations.compactMap({ $0 as? IndexedAnnotation }).min(by: { a, b in
                let pa = mapView.convert(a.coordinate, toPointTo: mapView)
                let pb = mapView.convert(b.coordinate, toPointTo: mapView)
                let da = hypot(pa.x - pt.x, pa.y - pt.y)
                let db = hypot(pb.x - pt.x, pb.y - pt.y)
                return da < db
            }) {
                let pHit = mapView.convert(nearest.coordinate, toPointTo: mapView)
                if hypot(pHit.x - pt.x, pHit.y - pt.y) <= hitRadius {
                    parent.selectedIndex = nearest.index
                    reloadAll()
                    return
                }
            }

            // Im Select-Tool: nichts hinzufügen
            guard parent.tool == .add else { return }

            let coord = mapView.convert(pt, toCoordinateFrom: mapView)
            parent.points.append(coord)
            parent.selectedIndex = parent.points.count - 1
            reloadAll()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: poly)
                r.strokeColor = parent?.lineColor ?? .systemBlue
                r.lineWidth = 4
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let ann = annotation as? IndexedAnnotation {
                let id = "pt"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: ann, reuseIdentifier: id)
                view.annotation = ann
                view.canShowCallout = false
                view.isDraggable = true
                view.backgroundColor = .clear

                let markerSize = max(14, min(40, CGFloat(parent?.segmentLabelFontSizePx ?? 12) + 8))
                let requestedFontSize = max(6, CGFloat(parent?.segmentLabelFontSizePx ?? 12))
                let fontSize = min(requestedFontSize, markerSize * 0.58) // Schrift immer im Kreis
                view.frame = CGRect(x: 0, y: 0, width: markerSize, height: markerSize)

                let circleTag = 101
                let labelTag = 102
                let circle: UIView
                let label: UILabel
                if let existing = view.viewWithTag(circleTag) {
                    circle = existing
                } else {
                    let v = UIView(frame: view.bounds)
                    v.tag = circleTag
                    v.layer.cornerRadius = markerSize / 2
                    v.layer.borderColor = UIColor.white.cgColor
                    v.layer.borderWidth = 1
                    v.clipsToBounds = true
                    view.addSubview(v)
                    circle = v
                }
                circle.frame = view.bounds
                circle.layer.cornerRadius = markerSize / 2
                circle.backgroundColor = (ann.index == parent?.selectedIndex) ? .systemGreen : (parent?.pointMarkerStyle.fillColor ?? .systemBlue)
                circle.layer.borderColor = (parent?.pointMarkerStyle.borderColor ?? UIColor.white).cgColor

                if let existing = view.viewWithTag(labelTag) as? UILabel {
                    label = existing
                } else {
                    let l = UILabel(frame: view.bounds)
                    l.tag = labelTag
                    l.textAlignment = .center
                    view.addSubview(l)
                    label = l
                }
                label.frame = view.bounds
                label.font = .systemFont(ofSize: fontSize, weight: .bold)
                let labelText: String
                if parent?.pointLabelStyle == .letters, ann.index < 26 {
                    labelText = String(Unicode.Scalar(65 + ann.index)!)
                } else {
                    labelText = String(ann.index + 1)
                }
                let style = parent?.pointMarkerStyle ?? .standard
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: fontSize),
                    .foregroundColor: style.textColor,
                    .strokeColor: style.textStrokeColor,
                    .strokeWidth: -2
                ]
                label.attributedText = NSAttributedString(string: labelText, attributes: attrs)
                return view
            }
            // Segment-Label (nicht draggable)
            if annotation is MKPointAnnotation, let title = annotation.title ?? nil, title.contains("m") {
                let id = "seg"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = false
                view.isDraggable = false
                view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
                view.layer.cornerRadius = 8
                view.frame = CGRect(x: 0, y: 0, width: 74, height: 26)

                let label: UILabel
                if let existing = view.subviews.compactMap({ $0 as? UILabel }).first {
                    label = existing
                } else {
                    label = UILabel(frame: view.bounds)
                    label.textAlignment = .center
                    label.textColor = .white
                    view.addSubview(label)
                }
                label.frame = view.bounds
                label.font = .systemFont(ofSize: max(6, CGFloat(parent?.segmentLabelFontSizePx ?? 12)), weight: .bold)
                label.text = title
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard let parent else { return }
            guard let ann = view.annotation as? IndexedAnnotation else { return }
            if newState == .ending || newState == .canceling {
                view.dragState = .none
                if ann.index >= 0, ann.index < parent.points.count {
                    parent.points[ann.index] = ann.coordinate
                    parent.selectedIndex = ann.index
                    reloadAll()
                }
            }
        }
    }
}

// MARK: - Hold repeat button (für exakte Punkt-Nudges)

private struct HoldRepeatNudgeButton: View {
    let systemImage: String
    var uiScale: CGFloat = 1.0
    let onTap: () -> Void
    let onFastRepeat: () -> Void
    var holdDelay: Double = 0.25
    var repeatInterval: Double = 0.05

    @State private var didStart = false
    @State private var startTask: Task<Void, Never>?
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        let scale = max(0.75, min(2.0, uiScale))
        let iconSize = 30 * scale
        let buttonW = 56 * scale
        let buttonH = 48 * scale
        let corner = 14 * scale
        ZStack {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: buttonW, height: buttonH)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !didStart else { return }
                    didStart = true
                    onTap()

                    startTask?.cancel()
                    startTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(holdDelay * 1_000_000_000))
                        if Task.isCancelled { return }
                        repeatTask?.cancel()
                        repeatTask = Task { @MainActor in
                            while !Task.isCancelled {
                                onFastRepeat()
                                try? await Task.sleep(nanoseconds: UInt64(repeatInterval * 1_000_000_000))
                            }
                        }
                    }
                }
                .onEnded { _ in
                    didStart = false
                    startTask?.cancel()
                    repeatTask?.cancel()
                    startTask = nil
                    repeatTask = nil
                }
        )
    }
}

// MARK: - RDP Simplify (für GPS-Jitter)

private func simplifyRDP(points: [CLLocationCoordinate2D], epsilonMeters: Double) -> [CLLocationCoordinate2D] {
    guard points.count >= 3 else { return points }
    let eps = max(0.05, epsilonMeters)

    // Umrechnung grob in Meter (lokal) für stabile Distanzberechnung.
    let refLat = points.map(\.latitude).reduce(0.0, +) / Double(points.count)
    let metersPerDegLat = 111_320.0
    let metersPerDegLon = metersPerDegLat * max(0.01, cos(refLat * .pi / 180))
    func toXY(_ c: CLLocationCoordinate2D) -> (Double, Double) {
        ((c.longitude - points[0].longitude) * metersPerDegLon,
         (c.latitude - points[0].latitude) * metersPerDegLat)
    }

    let xy = points.map(toXY)
    var keep = Array(repeating: false, count: points.count)
    keep[0] = true
    keep[points.count - 1] = true

    func perpendicularDistance(_ p: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let (px, py) = p
        let (ax, ay) = a
        let (bx, by) = b
        let dx = bx - ax
        let dy = by - ay
        let len2 = dx*dx + dy*dy
        if len2 < 1e-9 { return ((px-ax)*(px-ax) + (py-ay)*(py-ay)).squareRoot() }
        let t = max(0.0, min(1.0, ((px-ax)*dx + (py-ay)*dy) / len2))
        let projx = ax + t*dx
        let projy = ay + t*dy
        return ((px-projx)*(px-projx) + (py-projy)*(py-projy)).squareRoot()
    }

    func rdp(_ start: Int, _ end: Int) {
        guard end > start + 1 else { return }
        let a = xy[start]
        let b = xy[end]
        var maxD = 0.0
        var idx = -1
        for i in (start+1)..<end {
            let d = perpendicularDistance(xy[i], a, b)
            if d > maxD {
                maxD = d
                idx = i
            }
        }
        if maxD > eps, idx != -1 {
            keep[idx] = true
            rdp(start, idx)
            rdp(idx, end)
        }
    }

    rdp(0, points.count - 1)
    return points.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
}

