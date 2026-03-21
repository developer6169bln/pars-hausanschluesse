import Foundation
import CoreLocation

/// Ein Punkt einer Polylinien-Messung (AR) mit GPS-Koordinaten.
struct PolylinePoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
    /// Genauigkeit horizontal in Metern (z. B. aus CoreLocation horizontalAccuracy).
    var horizontalAccuracy: Double? = nil
    /// Genauigkeit vertikal in Metern (z. B. aus CoreLocation verticalAccuracy).
    var verticalAccuracy: Double? = nil
    /// Höhe in Metern über Meereshöhe (z. B. aus CoreLocation altitude).
    var altitude: Double? = nil
    /// Richtung (Course) in Grad, 0..360 (True Course bei GPS).
    var course: Double? = nil
    /// Genauigkeit der Richtung in Grad (z. B. aus CoreLocation courseAccuracy).
    var courseAccuracy: Double? = nil
}

/// Ein Zwischenfoto, das einem Messpunkt einer AR-Polylinie (A, B, C, …) zugeordnet ist.
struct PolylinePointPhoto: Identifiable, Codable, Equatable {
    var id = UUID()
    /// 0 = A, 1 = B, 2 = C, …
    var pointIndex: Int
    /// Lokaler Bildpfad (Dateiname) oder Server-URL nach Sync.
    var imagePath: String
    var date: Date
}

struct Measurement: Identifiable, Codable, Equatable {
    var id = UUID()
    var imagePath: String
    var latitude: Double
    var longitude: Double
    /// Genauigkeit horizontal in Metern.
    var horizontalAccuracy: Double? = nil
    /// Genauigkeit vertikal in Metern.
    var verticalAccuracy: Double? = nil
    /// Höhe in Metern.
    var altitude: Double? = nil
    /// Richtung (Course) in Grad, 0..360.
    var course: Double? = nil
    /// Genauigkeit der Richtung in Grad.
    var courseAccuracy: Double? = nil
    var address: String
    var points: [PhotoPoint]
    var totalDistance: Double  // Länge in Pixel
    var referenceMeters: Double?  // vom User eingegebene reale Länge in m (für Umrechnung px → m)
    /// Laufende Nummer innerhalb eines Projekts (für Sortierung / PDF).
    var index: Int? = nil
    /// GPS-Koordinaten der Messpunkte (Start A / Ende B), falls verfügbar.
    var startLatitude: Double? = nil
    var startLongitude: Double? = nil
    var endLatitude: Double? = nil
    var endLongitude: Double? = nil
    /// Kennzeichnung, ob es sich um eine AR-Messung (true) oder ein normales Foto/Kartenbild (false) handelt.
    var isARMeasurement: Bool = false
    /// AR-Zusatzinfos
    var oberflaeche: String? = nil
    var oberflaecheSonstige: String? = nil
    var verlegeart: String? = nil
    var verlegeartSonstige: String? = nil
    var date: Date
    /// Bei AR-Polylinien: alle Stützpunkte mit GPS. Leer/nil = Einzelstrecke (Start/Ende über startLatitude/endLatitude).
    var polylinePoints: [PolylinePoint]? = nil
    /// AR-gemessene Teilstrecken in m (A→B, B→C, …); Summe = referenceMeters. Leer/nil = aus GPS berechnen.
    var polylineSegmentMeters: [Double]? = nil
    /// Pro Segment (A→B, B→C, …) wählbare Oberfläche; Index i = Segment i. Nur bei Polylinien.
    var polylineSegmentOberflaeche: [String?]? = nil
    /// Pro Segment (A→B, B→C, …) wählbare Verlegeart; Index i = Segment i. Nur bei Polylinien.
    var polylineSegmentVerlegeart: [String?]? = nil
    /// Skizze: manuelle Korrektur der Position auf dem Luftbild (Versatz in °).
    var sketchOffsetLat: Double? = nil
    var sketchOffsetLon: Double? = nil
    /// Skizze: Drehung in Grad (0–360), um den Mittelpunkt der Messung.
    var sketchRotationDegrees: Double? = nil
    /// Skizze: Maßstab (1.0 = Original); > 1 vergrößert die Polylinie zum Anpassen ans Luftbild.
    var sketchScale: Double? = nil
    /// Skizze: true = Polylinie horizontal gespiegelt (spiegelverkehrt korrigieren).
    var sketchMirrored: Bool? = nil
    /// Skizze: optional manuell nachgezeichnete Polylinie (überschreibt die GPS-Polylinie für die Skizzenansicht).
    var sketchOverridePolylinePoints: [PolylinePoint]? = nil
    /// Skizze: Darstellung der Polylinie. true = aus AR-Metern als Gerade ab Startpunkt (Standard),
    /// false = GPS/RTK-Polyline verwenden.
    var sketchUseARSegments: Bool? = nil
    /// Zwischenfotos, die einzelnen Polylinien-Messpunkten zugeordnet sind.
    var polylinePointPhotos: [PolylinePointPhoto]? = nil

    /// Anzeige: Länge in Metern (wenn kalibriert), sonst nil.
    var lengthInMeters: Double? { referenceMeters }

    /// Geordnete GPS-Punkte der Messung (Polylinie A→B→C… oder Einzelstrecke A, B).
    var orderedGPSPoints: [CLLocationCoordinate2D] {
        if let poly = polylinePoints, !poly.isEmpty {
            return poly.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
        var coords: [CLLocationCoordinate2D] = []
        if let slat = startLatitude, let slon = startLongitude { coords.append(CLLocationCoordinate2D(latitude: slat, longitude: slon)) }
        if let elat = endLatitude, let elon = endLongitude { coords.append(CLLocationCoordinate2D(latitude: elat, longitude: elon)) }
        if coords.isEmpty { coords.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) }
        return coords
    }

    init(
        id: UUID = UUID(),
        imagePath: String,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double? = nil,
        verticalAccuracy: Double? = nil,
        altitude: Double? = nil,
        course: Double? = nil,
        courseAccuracy: Double? = nil,
        address: String,
        points: [PhotoPoint],
        totalDistance: Double,
        referenceMeters: Double?,
        index: Int? = nil,
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        endLatitude: Double? = nil,
        endLongitude: Double? = nil,
        isARMeasurement: Bool = false,
        oberflaeche: String? = nil,
        oberflaecheSonstige: String? = nil,
        verlegeart: String? = nil,
        verlegeartSonstige: String? = nil,
        date: Date,
        polylinePoints: [PolylinePoint]? = nil,
        polylineSegmentMeters: [Double]? = nil,
        polylineSegmentOberflaeche: [String?]? = nil,
        polylineSegmentVerlegeart: [String?]? = nil,
        sketchOffsetLat: Double? = nil,
        sketchOffsetLon: Double? = nil,
        sketchRotationDegrees: Double? = nil,
        sketchScale: Double? = nil,
        sketchMirrored: Bool? = nil,
        sketchOverridePolylinePoints: [PolylinePoint]? = nil,
        sketchUseARSegments: Bool? = nil,
        polylinePointPhotos: [PolylinePointPhoto]? = nil
    ) {
        self.id = id
        self.imagePath = imagePath
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.altitude = altitude
        self.course = course
        self.courseAccuracy = courseAccuracy
        self.address = address
        self.points = points
        self.totalDistance = totalDistance
        self.referenceMeters = referenceMeters
        self.index = index
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
        self.isARMeasurement = isARMeasurement
        self.oberflaeche = oberflaeche
        self.oberflaecheSonstige = oberflaecheSonstige
        self.verlegeart = verlegeart
        self.verlegeartSonstige = verlegeartSonstige
        self.date = date
        self.polylinePoints = polylinePoints
        self.polylineSegmentMeters = polylineSegmentMeters
        self.polylineSegmentOberflaeche = polylineSegmentOberflaeche
        self.polylineSegmentVerlegeart = polylineSegmentVerlegeart
        self.sketchOffsetLat = sketchOffsetLat
        self.sketchOffsetLon = sketchOffsetLon
        self.sketchRotationDegrees = sketchRotationDegrees
        self.sketchScale = sketchScale
        self.sketchMirrored = sketchMirrored
        self.sketchOverridePolylinePoints = sketchOverridePolylinePoints
        self.sketchUseARSegments = sketchUseARSegments
        self.polylinePointPhotos = polylinePointPhotos
    }
}
