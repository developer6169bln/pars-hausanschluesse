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

    /// Anzeige: Länge in Metern (wenn kalibriert), sonst nil.
    var lengthInMeters: Double? { referenceMeters }

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
        polylineSegmentMeters: [Double]? = nil
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
    }
}
