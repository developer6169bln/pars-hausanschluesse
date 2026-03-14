import Foundation

// Bauhindernis-Report direkt hier definiert, damit es immer im Target verfügbar ist.
struct BauhinderungReport: Codable, Equatable {
    enum TelefonErgebnis: String, CaseIterable, Codable {
        case none = "—"
        case nichtErreichbar = "Kunde nicht erreichbar"
        case terminVergessen = "Kunde hat Termin vergessen"
        case verweigertAnschluss = "Kunde verweigert Anschluss"
    }

    // Kopf
    var ticketNummer: String? = nil
    var netzbetreiber: String? = nil
    var tiefbauunternehmen: String? = nil
    var datumEinsatz: Date? = nil
    var uhrzeitAnkunft: Date? = nil
    var uhrzeitVerlassen: Date? = nil
    var monteurKolonne: String? = nil

    // Allgemeine Bauhindernisse
    var kundeNichtAnwesend: Bool = false
    var keinZugangGrundstueck: Bool = false
    var keinZugangGebaeude: Bool = false
    var zustimmungHauseinfuehrungNichtErteilt: Bool = false
    var arbeitsbereichBlockiert: Bool = false
    var oberflaecheNichtFreigegeben: Bool = false
    var versorgungsleitungenVerhindern: Bool = false
    var leerrohrNichtAuffindbarOderBeschaedigt: Bool = false
    var sicherheitsrisiko: Bool = false
    var witterung: Bool = false

    // Technische Bauhindernisse
    var anschlusspunktNichtAuffindbar: Bool = false
    var tiereFreilaufend: Bool = false
    var tiereNichtGesichert: Bool = false

    // Freitexte
    var beschreibungBauhindernis: String? = nil
    var hinweiseAuftraggeber: String? = nil

    // Dokumentation
    var fotoDokuErstellt: Bool = false
    var kundeVorOrtInformiert: Bool = false
    var kundeTelefonischKontaktiert: Bool = false
    var telefonErgebnis: TelefonErgebnis = .none
    var uhrzeitAnruf: Date? = nil

    // Ergebnis / Status
    var arbeitenNichtBegonnen: Bool = false
    var arbeitenUnterbrochen: Bool = false
    var hausanschlussTeilweise: Bool = false
    var weitereKlaerungNoetig: Bool = false
    var neuerTerminNoetig: Bool = false

    // Unterschrift
    var ort: String? = nil
    var datum: Date? = nil
    var nameMonteurBauleiter: String? = nil
    var unterschriftPath: String? = nil
}

// 3D-Scan-Metadaten für ein Projekt.
struct ThreeDScan: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var createdAt: Date
    /// Pfad zur 3D-Datei im Documents-Ordner (z. B. .usdz oder .scn); aktuell Platzhalter.
    var filePath: String
    var note: String?
    /// Standort des Scans (GPS), für Darstellung auf 3D-Karte.
    var latitude: Double?
    var longitude: Double?
}

struct Project: Identifiable, Codable, Equatable {
    var id = UUID()
    /// Server-ID (z. B. "proj-123") – nur bei vom Server zugewiesenen Projekten gesetzt. Für Sync erforderlich.
    var serverProjectId: String?
    var name: String
    var measurements: [Measurement]
    var createdAt: Date

    // Erweiterte Projektdaten
    var strasse: String?
    var hausnummer: String?
    var postleitzahl: String?
    var ort: String?
    var nvtNummer: String?
    var kolonne: String?
    var verbundGroesse: String?
    var verbundFarbe: String?
    var pipesFarbe: String?       // Legacy; Anzeige bevorzugt pipesFarbe1/2
    var pipesFarbe1: String?
    var pipesFarbe2: String?
    /// Optional für Abwärtskompatibilität; in der UI als false anzeigen wenn nil.
    var auftragAbgeschlossen: Bool?
    var termin: Date?
    var googleDriveLink: String?
    var notizen: String?
    // Kunden-Kommunikation
    var telefonNotizen: String?
    var kundenBeschwerden: String?
    var kundenBeschwerdenUnterschriebenAm: Date?
    var auftragBestaetigtText: String?
    var auftragBestaetigtUnterschriebenAm: Date?
    // Abnahmeprotokoll
    var abnahmeProtokollUnterschriftPath: String?
    var abnahmeProtokollDatum: Date?
    var abnahmeOhneMaengel: Bool?
    var abnahmeMaengelText: String?
    // Kundendaten
    var kundeName: String?
    var kundeTelefon: String?
    var kundeEmail: String?
    // Bauhindernis
    var bauhinderung: BauhinderungReport?
    // 3D-Scans
    var threeDScans: [ThreeDScan] = []

    init(
        id: UUID? = nil,
        serverProjectId: String? = nil,
        name: String,
        measurements: [Measurement],
        createdAt: Date,
        strasse: String? = nil,
        hausnummer: String? = nil,
        postleitzahl: String? = nil,
        ort: String? = nil,
        nvtNummer: String? = nil,
        kolonne: String? = nil,
        verbundGroesse: String? = nil,
        verbundFarbe: String? = nil,
        pipesFarbe: String? = nil,
        pipesFarbe1: String? = nil,
        pipesFarbe2: String? = nil,
        auftragAbgeschlossen: Bool? = false,
        termin: Date? = nil,
        googleDriveLink: String? = nil,
        notizen: String? = nil,
        telefonNotizen: String? = nil,
        kundenBeschwerden: String? = nil,
        kundenBeschwerdenUnterschriebenAm: Date? = nil,
        auftragBestaetigtText: String? = nil,
        auftragBestaetigtUnterschriebenAm: Date? = nil,
        abnahmeProtokollUnterschriftPath: String? = nil,
        abnahmeProtokollDatum: Date? = nil,
        abnahmeOhneMaengel: Bool? = nil,
        abnahmeMaengelText: String? = nil,
        kundeName: String? = nil,
        kundeTelefon: String? = nil,
        kundeEmail: String? = nil,
        bauhinderung: BauhinderungReport? = nil,
        threeDScans: [ThreeDScan] = []
    ) {
        self.id = id ?? UUID()
        self.serverProjectId = serverProjectId
        self.name = name
        self.measurements = measurements
        self.createdAt = createdAt
        self.strasse = strasse
        self.hausnummer = hausnummer
        self.postleitzahl = postleitzahl
        self.ort = ort
        self.nvtNummer = nvtNummer
        self.kolonne = kolonne
        self.verbundGroesse = verbundGroesse
        self.verbundFarbe = verbundFarbe
        self.pipesFarbe = pipesFarbe
        self.pipesFarbe1 = pipesFarbe1
        self.pipesFarbe2 = pipesFarbe2
        self.auftragAbgeschlossen = auftragAbgeschlossen
        self.termin = termin
        self.googleDriveLink = googleDriveLink
        self.notizen = notizen
        self.telefonNotizen = telefonNotizen
        self.kundenBeschwerden = kundenBeschwerden
        self.kundenBeschwerdenUnterschriebenAm = kundenBeschwerdenUnterschriebenAm
        self.auftragBestaetigtText = auftragBestaetigtText
        self.auftragBestaetigtUnterschriebenAm = auftragBestaetigtUnterschriebenAm
        self.abnahmeProtokollUnterschriftPath = abnahmeProtokollUnterschriftPath
        self.abnahmeProtokollDatum = abnahmeProtokollDatum
        self.abnahmeOhneMaengel = abnahmeOhneMaengel
        self.abnahmeMaengelText = abnahmeMaengelText
        self.kundeName = kundeName
        self.kundeTelefon = kundeTelefon
        self.kundeEmail = kundeEmail
        self.bauhinderung = bauhinderung
        self.threeDScans = threeDScans
    }

    /// Summe aller Messungen (Gesamtlänge des Projekts) in px.
    var totalLength: Double {
        measurements.map(\.totalDistance).reduce(0, +)
    }

    /// Summe der in Metern angegebenen Längen (nur kalibrierte Messungen).
    var totalMeters: Double {
        measurements.compactMap(\.referenceMeters).reduce(0, +)
    }
}
