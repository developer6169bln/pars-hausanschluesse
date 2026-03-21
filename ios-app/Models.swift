import Foundation

struct Auftrag: Identifiable, Codable, Hashable {
    var id: Int
    var bezeichnung: String
    var adresse: String
    var plz: String
    var ort: String
    var nvt: String?

    var baugrubenLaengen: [Double]?
    var dokumentationFotos: [Attachment]?

    var termin: String?
    var kunde: String?
    var netzbetreiber: String?
    var status: String?
    var messungGraben: String?
    var notizen: String?
    var abgeschlossen: Bool?
}

struct Attachment: Codable, Hashable {
    var name: String?
    var url: String?
    var dataUrl: String?
    var size: Int?
    var type: String?
    var meta: FotoMeta?
}

struct FotoMeta: Codable, Hashable {
    var capturedAt: TimeInterval?
    var street: String?
    var house: String?
    var nvt: String?
    var lat: Double?
    var lng: Double?
    var accuracy: Double?
    var reverseGeocode: String?
}
