import Foundation
import CoreLocation

/// Ein Punkt einer Polylinien-Messung (AR) mit GPS-Koordinaten.
struct PolylinePoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
}

struct Measurement: Identifiable, Codable, Equatable {
    var id = UUID()
    var imagePath: String
    var latitude: Double
    var longitude: Double
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
        sketchMirrored: Bool? = nil
    ) {
        self.id = id
        self.imagePath = imagePath
        self.latitude = latitude
        self.longitude = longitude
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
    }
}
