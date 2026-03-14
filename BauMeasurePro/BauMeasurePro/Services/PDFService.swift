import UIKit
import CoreLocation
import MapKit

class PDFService {
    /// Alter, einfacher Bericht für Einzelmessungen (wird noch von MeasurementDetailView genutzt).
    static func createReport(
        address: String,
        lat: Double,
        lon: Double,
        lengthMeters: Double? = nil,
        date: Date? = nil
    ) -> URL {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("report_\(UUID().uuidString).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))

        try? renderer.writePDF(to: path) { ctx in
            ctx.beginPage()
            var y: CGFloat = 50
            let title = "Baumessbericht" as NSString
            title.draw(
                at: CGPoint(x: 50, y: y),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24)]
            )
            y += 50
            ("Adresse: \(address)" as NSString).draw(
                at: CGPoint(x: 50, y: y),
                withAttributes: [.font: UIFont.systemFont(ofSize: 16)]
            )
            y += 30
            ("GPS: \(lat), \(lon)" as NSString).draw(
                at: CGPoint(x: 50, y: y),
                withAttributes: [.font: UIFont.systemFont(ofSize: 16)]
            )
            if let m = lengthMeters {
                y += 30
                (String(format: "Länge: %.2f m", m) as NSString).draw(
                    at: CGPoint(x: 50, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 16)]
                )
            }
            if let d = date {
                y += 30
                ("Datum: \(d.formatted())" as NSString).draw(
                    at: CGPoint(x: 50, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 16)]
                )
            }
        }
        return path
    }

    /// Projektbezogener Bericht: große Fotos unter den Messungen, Kartenseite = Screenshot wie in der App.
    /// Asynchron, weil die Karte per MKMapSnapshotter erzeugt wird; completion wird auf dem Main-Thread aufgerufen.
    static func createProjectReport(project: Project, completion: @escaping (URL) -> Void) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("project_\(project.id.uuidString).pdf")
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let coords = projectRoute(for: project)

        func writePDF(mapSnapshotImage: UIImage?) {
            let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
            try? renderer.writePDF(to: path) { ctx in
                drawProjectPages(ctx: ctx, project: project, pageRect: pageRect, mapSnapshotImage: mapSnapshotImage)
            }
            DispatchQueue.main.async { completion(path) }
        }

        if coords.count >= 2, let region = region(for: coords) {
            let options = MKMapSnapshotter.Options()
            options.region = region
            options.size = CGSize(width: 600, height: 400)
            options.showsBuildings = true
            let snapshotter = MKMapSnapshotter(options: options)
            snapshotter.start { result, _ in
                guard let snap = result else {
                    writePDF(mapSnapshotImage: nil)
                    return
                }
                let mapImage = renderMapOverlay(snapshot: snap, project: project, coords: coords)
                writePDF(mapSnapshotImage: mapImage)
            }
        } else {
            writePDF(mapSnapshotImage: nil)
        }
    }

    /// Region aus Koordinaten (Mittelpunkt + Span mit Puffer).
    private static func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard coords.count >= 2,
              let minLat = coords.map(\.latitude).min(),
              let maxLat = coords.map(\.latitude).max(),
              let minLon = coords.map(\.longitude).min(),
              let maxLon = coords.map(\.longitude).max() else { return nil }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.0015),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.0015)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Karten-Snapshot wie in der Projektübersicht: Karte + Polyline + Start/Ende + Gesamtlänge.
    private static func renderMapOverlay(snapshot: MKMapSnapshotter.Snapshot, project: Project, coords: [CLLocationCoordinate2D]) -> UIImage {
        let baseImage = snapshot.image
        let renderer = UIGraphicsImageRenderer(size: baseImage.size)
        return renderer.image { ctx in
            baseImage.draw(at: .zero)
            let cg = ctx.cgContext
            if coords.count >= 2 {
                let points = coords.map { snapshot.point(for: $0) }
                cg.setStrokeColor(UIColor.systemBlue.cgColor)
                cg.setLineWidth(4)
                cg.addLines(between: points)
                cg.strokePath()
            }
            if let first = coords.first {
                let p = snapshot.point(for: first)
                cg.setFillColor(UIColor.systemGreen.cgColor)
                cg.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
            }
            if let last = coords.last {
                let p = snapshot.point(for: last)
                cg.setFillColor(UIColor.systemRed.cgColor)
                cg.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
            }
            let text = String(format: "Gesamtlänge: %.2f m (%.0f px)", project.totalMeters, project.totalLength)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -2
            ]
            let margin: CGFloat = 12
            (project.name as NSString).draw(in: CGRect(x: margin, y: margin, width: baseImage.size.width - 2 * margin, height: 28), withAttributes: attrs)
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(in: CGRect(x: margin, y: baseImage.size.height - size.height - margin, width: size.width, height: size.height), withAttributes: attrs)
        }
    }

    private static func drawProjectPages(ctx: UIGraphicsPDFRendererContext, project: Project, pageRect: CGRect, mapSnapshotImage: UIImage?) {
        var y: CGFloat = 40
        ctx.beginPage()
        ("Projektbericht" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24)])
        y += 40
        ("Projekt: \(project.name)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
        y += 24
        ("Angelegt: \(project.createdAt.formatted())" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        y += 24
        let totalText = String(format: "Gesamtlänge: %.2f m (%.0f px)", project.totalMeters, project.totalLength) as NSString
        totalText.draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        y += 20
        if let name = project.kundeName, !name.isEmpty { ("Name Kunde: \(name)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        if let tel = project.kundeTelefon, !tel.isEmpty { ("Telefon Kunde: \(tel)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        if let mail = project.kundeEmail, !mail.isEmpty { ("E-Mail Kunde: \(mail)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        if let s = project.strasse, !s.isEmpty { ("Straße: \(s)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        if let h = project.hausnummer, !h.isEmpty { ("Hausnummer: \(h)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        if let plz = project.postleitzahl, !plz.isEmpty { ("Postleitzahl: \(plz)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        if let ort = project.ort, !ort.isEmpty { ("Ort: \(ort)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        if let nvt = project.nvtNummer, !nvt.isEmpty { ("NVT-Nummer: \(nvt)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        if let k = project.kolonne, !k.isEmpty { ("Kolonne: \(k)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        if let vg = project.verbundGroesse, !vg.isEmpty { ("Verbund Größe: \(vg)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        if let vf = project.verbundFarbe, !vf.isEmpty { ("Verbund Farbe: \(vf)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        let pf1 = project.pipesFarbe1 ?? project.pipesFarbe
        let pf2 = project.pipesFarbe2
        if let p1 = pf1, !p1.isEmpty {
            let pipesText = pf2 != nil && !pf2!.isEmpty ? "Pipes Farbe 1: \(p1), Farbe 2: \(pf2!)" : "Pipes Farbe: \(p1)"
            (pipesText as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            y += 16
        }
        ("Auftrag abgeschlossen: \((project.auftragAbgeschlossen ?? false) ? "Ja" : "Nein")" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
        y += 16
        if let t = project.termin { ("Termin: \(t.formatted(date: .abbreviated, time: .shortened))" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        if let gd = project.googleDriveLink, !gd.isEmpty { ("Google Drive: \(gd)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 11)]); y += 14 }
        if let n = project.notizen, !n.isEmpty { ("Notizen: \(n)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)]); y += 16 }
        if let t = project.telefonNotizen, !t.isEmpty {
            ("Telefon-Notizen: \(t)" as NSString).draw(
                in: CGRect(x: 40, y: y, width: pageRect.width - 80, height: 60),
                withAttributes: [.font: UIFont.systemFont(ofSize: 12)]
            )
            y += 64
        }
        if let b = project.kundenBeschwerden, !b.isEmpty {
            ("Beschwerden: \(b)" as NSString).draw(
                in: CGRect(x: 40, y: y, width: pageRect.width - 80, height: 80),
                withAttributes: [.font: UIFont.systemFont(ofSize: 12)]
            )
            y += 84
            if let d = project.kundenBeschwerdenUnterschriebenAm {
                ("Beschwerden unterschrieben am: \(d.formatted(date: .abbreviated, time: .shortened))" as NSString)
                    .draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                y += 16
            }
        }
        if let t = project.auftragBestaetigtText, !t.isEmpty {
            ("Auftragsbestätigung: \(t)" as NSString).draw(
                in: CGRect(x: 40, y: y, width: pageRect.width - 80, height: 80),
                withAttributes: [.font: UIFont.systemFont(ofSize: 12)]
            )
            y += 84
            if let d = project.auftragBestaetigtUnterschriebenAm {
                ("Bestätigung unterschrieben am: \(d.formatted(date: .abbreviated, time: .shortened))" as NSString)
                    .draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                y += 16
            }
        }

        let storage = StorageService()
        let sorted = project.measurements.sorted { ($0.index ?? 0, $0.date) < ($1.index ?? 0, $1.date) }
        let margin: CGFloat = 40
        let maxImageWidth = pageRect.width - 2 * margin
        let maxImageHeight: CGFloat = 420
        var fotoCount = 0
        var arCount = 0

        for m in sorted {
            ctx.beginPage()
            var pageY: CGFloat = 40
            if m.isARMeasurement {
                arCount += 1
            } else {
                fotoCount += 1
            }
            let idxText: String
            if m.isARMeasurement {
                idxText = "Messung \(arCount)"
            } else {
                idxText = "Foto \(fotoCount)"
            }
            (idxText as NSString).draw(at: CGPoint(x: margin, y: pageY), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16)])
            pageY += 20
            ("Adresse: \(m.address)" as NSString).draw(at: CGPoint(x: margin, y: pageY), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            pageY += 16
            if m.isARMeasurement {
                let surface = (m.oberflaeche == "Sonstige Oberfläche") ? (m.oberflaecheSonstige ?? "") : (m.oberflaeche ?? "")
                let laying = (m.verlegeart == "Sonstige Verlegeart") ? (m.verlegeartSonstige ?? "") : (m.verlegeart ?? "")
                if !surface.isEmpty {
                    ("Oberfläche: \(surface)" as NSString).draw(at: CGPoint(x: margin, y: pageY), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                    pageY += 14
                }
                if !laying.isEmpty {
                    ("Verlegeart: \(laying)" as NSString).draw(at: CGPoint(x: margin, y: pageY), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                    pageY += 14
                }
            }
            if let ref = m.referenceMeters {
                (String(format: "Länge: %.2f m (%.0f px)", ref, m.totalDistance) as NSString).draw(at: CGPoint(x: margin, y: pageY), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            } else {
                (String(format: "Länge: %.0f px", m.totalDistance) as NSString).draw(at: CGPoint(x: margin, y: pageY), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            }
            pageY += 16
            if m.isARMeasurement {
                if let poly = m.polylinePoints, !poly.isEmpty {
                    for (idx, p) in poly.enumerated() {
                        ("Punkt \(idx + 1) GPS: \(p.latitude), \(p.longitude)" as NSString).draw(at: CGPoint(x: margin, y: pageY), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                        pageY += 14
                    }
                    pageY += 10
                } else {
                    ("1A GPS: \(m.startLatitude ?? m.latitude), \(m.startLongitude ?? m.longitude)" as NSString).draw(at: CGPoint(x: margin, y: pageY), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                    pageY += 14
                    ("1B GPS: \(m.endLatitude ?? m.latitude), \(m.endLongitude ?? m.longitude)" as NSString).draw(at: CGPoint(x: margin, y: pageY), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                    pageY += 24
                }
            } else {
                pageY += 8
            }

            let fullPath = storage.fullPath(forStoredPath: m.imagePath)
            if let img = UIImage(contentsOfFile: fullPath) {
                let imgSize = img.size
                let scale = min(maxImageWidth / imgSize.width, maxImageHeight / imgSize.height, 1.0)
                let drawW = imgSize.width * scale
                let drawH = imgSize.height * scale
                if pageY + drawH > pageRect.height - 40 { ctx.beginPage(); pageY = 40 }
                img.draw(in: CGRect(x: margin, y: pageY, width: drawW, height: drawH))
            }
        }

        if let mapImage = mapSnapshotImage {
            ctx.beginPage()
            ("Kartenübersicht" as NSString).draw(at: CGPoint(x: 40, y: 24), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 18)])
            let mapRect = CGRect(x: 40, y: 50, width: pageRect.width - 80, height: pageRect.height - 90)
            mapImage.draw(in: mapRect)
        }
    }

    /// Separater Abnahmeprotokoll-Bericht (nur Abnahme, mit Auswahl, Mängeltext und Unterschrift).
    static func createAbnahmeReport(project: Project, completion: @escaping (URL) -> Void) {
        let format = UIGraphicsPDFRendererFormat()
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Abnahme-\(UUID().uuidString).pdf")
        DispatchQueue.global(qos: .userInitiated).async {
            try? renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                let margin: CGFloat = 40
                var y: CGFloat = 40
                ("Abnahmeprotokoll – Glasfaser-Hausanschluss / Wiederherstellung des Grundstücks" as NSString)
                    .draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16)])
                y += 28

                let addressLine = "Adresse des Grundstücks: \(project.strasse ?? "") \(project.hausnummer ?? ""), \(project.postleitzahl ?? "") \(project.ort ?? "")"
                (addressLine as NSString).draw(in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                y += 44

                let para1 = """
Projekt: Herstellung Glasfaser-Hausanschluss

Herstellung eines Glasfaser-Hausanschlusses einschließlich Tiefbauarbeiten auf dem Grundstück des Auftraggebers sowie anschließender Wiederherstellung der betroffenen Flächen (z. B. Rasen, Pflaster, Einfahrt, Wege). Zusätzlich wurde die Hauseinführung für die Glasfaserleitung hergestellt.
"""
                (para1 as NSString).draw(in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: 140), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                y += 148

                let para2 = """
Die Bohrung zur Einführung der Glasfaserleitung in das Gebäude wurde fachgerecht hergestellt und abgedichtet. Verwendet wurde eine Elektrokabel-, Gas- und wasserdichte Durchführung Ø 7–15 mm für Gebäude mit oder ohne Keller. Zur dauerhaften Abdichtung und Befestigung der Hauseinführung wurde zusätzlich EH Resinator eingespritzt.
"""
                (para2 as NSString).draw(in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: 120), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                y += 128

                // Checkboxen je nach Auswahl – größere Kästchen + mehr Abstand
                let ohne = project.abnahmeOhneMaengel
                let checkFont = UIFont.systemFont(ofSize: 16)
                let line1 = (ohne == true ? "☒" : "☐") + " Bei der Abnahme wurden keine sichtbaren Mängel festgestellt."
                let line2 = (ohne == false ? "☒" : "☐") + " Folgende Mängel wurden festgestellt und werden noch beseitigt:"
                (line1 as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: checkFont])
                y += 30   // ca. zwei Textzeilen Abstand
                (line2 as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: checkFont])
                y += 30
                if ohne == false, let text = project.abnahmeMaengelText, !text.isEmpty {
                    (text as NSString).draw(
                        in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: 80),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 12)]
                    )
                    y += 84
                } else {
                    y += 40
                }

                let ortText = project.ort ?? ""
                let abnahmeDatum = project.abnahmeProtokollDatum ?? Date()
                let ortDatumLine = "Ort, Datum: \(ortText), \(abnahmeDatum.formatted(date: .abbreviated, time: .shortened))"
                (ortDatumLine as NSString).draw(at: CGPoint(x: margin, y: pageRect.height - 180), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])

                // Unterschrift
                if let sigPath = project.abnahmeProtokollUnterschriftPath {
                    let storage = StorageService()
                    let full = storage.fullPath(forStoredPath: sigPath)
                    if FileManager.default.fileExists(atPath: full),
                       let sigImage = UIImage(contentsOfFile: full) {
                        let sigLabelY = pageRect.height - 150
                        ("Unterschrift Auftraggeber / Grundstückseigentümer:" as NSString)
                            .draw(at: CGPoint(x: margin, y: sigLabelY), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                        let sigWidth: CGFloat = pageRect.width - 2 * margin
                        let sigHeight: CGFloat = 60
                        sigImage.draw(in: CGRect(x: margin, y: sigLabelY + 18, width: sigWidth, height: sigHeight))
                    }
                }
            }
            DispatchQueue.main.async {
                completion(url)
            }
        }
    }

    /// Separater Bauhindernis-Bericht (Bauhindernisanzeige / Baustellenbericht).
    static func createBauhinderungReport(project: Project, completion: @escaping (URL) -> Void) {
        let format = UIGraphicsPDFRendererFormat()
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Bauhinderung-\(UUID().uuidString).pdf")
        DispatchQueue.global(qos: .userInitiated).async {
            try? renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                let margin: CGFloat = 40
                var y: CGFloat = 40

                let r = project.bauhinderung ?? BauhinderungReport()

                ("Bauhindernisanzeige / Baustellenbericht – Glasfaser Hausanschluss" as NSString)
                    .draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16)])
                y += 28

                ("Projekt: Glasfaser-Hausanschluss" as NSString)
                    .draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                y += 16

                let ticket = r.ticketNummer ?? ""
                ("Projekt- / Ticketnummer: \(ticket)" as NSString)
                    .draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                y += 16

                let addressLine = "Adresse des Bauvorhabens: \(project.strasse ?? "") \(project.hausnummer ?? ""), \(project.postleitzahl ?? "") \(project.ort ?? "")"
                (addressLine as NSString).draw(
                    in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: 32),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12)]
                )
                y += 36

                func drawLine(_ label: String, _ value: String?) {
                    ( "\(label): \(value ?? "")" as NSString)
                        .draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                    y += 16
                }

                drawLine("Netzbetreiber / Auftraggeber", r.netzbetreiber)
                drawLine("Ausführendes Tiefbauunternehmen", r.tiefbauunternehmen)

                let df = DateFormatter()
                df.locale = Locale(identifier: "de_DE")
                df.dateStyle = .short
                df.timeStyle = .none
                let tf = DateFormatter()
                tf.locale = Locale(identifier: "de_DE")
                tf.dateStyle = .none
                tf.timeStyle = .short

                drawLine("Datum des Einsatzes", r.datumEinsatz.map { df.string(from: $0) })
                drawLine("Uhrzeit Ankunft Baustelle", r.uhrzeitAnkunft.map { tf.string(from: $0) })
                drawLine("Uhrzeit Verlassen Baustelle", r.uhrzeitVerlassen.map { tf.string(from: $0) })
                drawLine("Monteur / Kolonne", r.monteurKolonne)
                y += 8

                ("1. Feststellung vor Ort" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 13)])
                y += 18
                let feststellung = "Bei Ankunft auf der Baustelle wurde festgestellt, dass die geplanten Arbeiten zur Herstellung des Glasfaser-Hausanschlusses nicht oder nur teilweise durchgeführt werden konnten."
                (feststellung as NSString).draw(in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                y += 52

                ("2. Allgemeine Bauhindernisse (bitte ankreuzen)" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 13)])
                y += 18

                let checkFont = UIFont.systemFont(ofSize: 12)
                func box(_ on: Bool) -> String { on ? "☒" : "☐" }
                let items2: [(Bool, String)] = [
                    (r.kundeNichtAnwesend, "Kunde / Eigentümer nicht anwesend"),
                    (r.keinZugangGrundstueck, "Kein Zugang zum Grundstück möglich"),
                    (r.keinZugangGebaeude, "Kein Zugang zum Gebäude / Keller / Hausanschlussraum"),
                    (r.zustimmungHauseinfuehrungNichtErteilt, "Zustimmung zur Hauseinführung nicht erteilt"),
                    (r.arbeitsbereichBlockiert, "Grundstück oder Arbeitsbereich blockiert (z. B. Fahrzeuge, Baumaterial)"),
                    (r.oberflaecheNichtFreigegeben, "Oberfläche (Pflaster / Beton / Gartenanlage) nicht zur Öffnung freigegeben"),
                    (r.versorgungsleitungenVerhindern, "Vorhandene Versorgungsleitungen verhindern Arbeiten"),
                    (r.leerrohrNichtAuffindbarOderBeschaedigt, "Leerrohr / Anschlusspunkt nicht auffindbar oder beschädigt"),
                    (r.sicherheitsrisiko, "Sicherheitsrisiko auf der Baustelle"),
                    (r.witterung, "Witterungsbedingte Bauhindernisse")
                ]
                for (on, text) in items2 {
                    ( "\(box(on)) \(text)" as NSString).draw(in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: 22), withAttributes: [.font: checkFont])
                    y += 16
                }
                y += 6

                ("3. Technische Bauhindernisse" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 13)])
                y += 18

                let items3: [(Bool, String)] = [
                    (r.anschlusspunktNichtAuffindbar, "Hausanschluss im Grundstücksbereich sowie im Gebäude hergestellt. Der Verbund im öffentlichen Bereich konnte jedoch nicht hergestellt werden, da der vorgesehene Anschlusspunkt nicht im gekennzeichneten Bereich gemäß Plan auffindbar war. Die Pipe wurde vor dem Grundstück aufgerollt und provisorisch im Boden vergraben."),
                    (r.tiereFreilaufend, "Freilaufende Tiere auf dem Grundstück verhinderten die Durchführung der Arbeiten. Der Kunde wurde aufgefordert, die Tiere zu sichern bzw. aus dem Arbeitsbereich zu entfernen."),
                    (r.tiereNichtGesichert, "Der Kunde verweigerte das Wegbringen bzw. Sichern der Tiere.")
                ]
                for (on, text) in items3 {
                    ( "\(box(on)) \(text)" as NSString).draw(in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: 70), withAttributes: [.font: checkFont])
                    y += 56
                }

                ("4. Beschreibung des Bauhindernisses" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 13)])
                y += 18
                let desc = (r.beschreibungBauhindernis ?? "").isEmpty ? "—" : (r.beschreibungBauhindernis ?? "")
                (desc as NSString).draw(in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: 70), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                y += 76

                ("5. Dokumentation" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 13)])
                y += 18
                let items5: [(Bool, String)] = [
                    (r.fotoDokuErstellt, "Fotodokumentation erstellt"),
                    (r.kundeVorOrtInformiert, "Kunde / Eigentümer vor Ort informiert"),
                    (r.kundeTelefonischKontaktiert, "Kunde telefonisch kontaktiert")
                ]
                for (on, text) in items5 {
                    ( "\(box(on)) \(text)" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: checkFont])
                    y += 16
                }
                ("Ergebnis des Telefonats: \(r.telefonErgebnis.rawValue)" as NSString).draw(in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: 22), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                y += 18
                drawLine("Uhrzeit des Anrufes", r.uhrzeitAnruf.map { tf.string(from: $0) })
                y += 4

                ("6. Ergebnis / Status der Baustelle" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 13)])
                y += 18
                let items6: [(Bool, String)] = [
                    (r.arbeitenNichtBegonnen, "Arbeiten konnten nicht begonnen werden"),
                    (r.arbeitenUnterbrochen, "Arbeiten mussten unterbrochen werden"),
                    (r.hausanschlussTeilweise, "Hausanschluss teilweise hergestellt"),
                    (r.weitereKlaerungNoetig, "Weitere Klärung durch Netzbetreiber / Bauleitung erforderlich"),
                    (r.neuerTerminNoetig, "Neuer Termin erforderlich")
                ]
                for (on, text) in items6 {
                    ( "\(box(on)) \(text)" as NSString).draw(in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: 22), withAttributes: [.font: checkFont])
                    y += 16
                }
                y += 6

                ("7. Hinweise für Auftraggeber / Bauleitung" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 13)])
                y += 18
                let hinweise = (r.hinweiseAuftraggeber ?? "").isEmpty ? "—" : (r.hinweiseAuftraggeber ?? "")
                (hinweise as NSString).draw(in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])

                // Unterschrift unten
                let ortText = r.ort ?? project.ort ?? ""
                let datum = r.datum ?? Date()
                let ortDatum = "Ort, Datum: \(ortText), \(datum.formatted(date: .abbreviated, time: .shortened))"
                (ortDatum as NSString).draw(at: CGPoint(x: margin, y: pageRect.height - 180), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                let nameMonteur = r.nameMonteurBauleiter ?? ""
                ("Name Monteur / Bauleiter: \(nameMonteur)" as NSString).draw(at: CGPoint(x: margin, y: pageRect.height - 160), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])

                ("Unterschrift ausführendes Unternehmen" as NSString).draw(at: CGPoint(x: margin, y: pageRect.height - 140), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                if let sigPath = r.unterschriftPath {
                    let storage = StorageService()
                    let full = storage.fullPath(forStoredPath: sigPath)
                    if FileManager.default.fileExists(atPath: full),
                       let sigImage = UIImage(contentsOfFile: full) {
                        sigImage.draw(in: CGRect(x: margin, y: pageRect.height - 118, width: pageRect.width - 2 * margin, height: 60))
                    }
                }
            }
            DispatchQueue.main.async { completion(url) }
        }
    }

    /// Berechnet die Route für das Projekt; bei Polylinien alle Stützpunkte, sonst 1A -> 2A -> ... -> N B.
    private static func projectRoute(for project: Project) -> [CLLocationCoordinate2D] {
        let sorted = project.measurements.sorted { ($0.index ?? 0, $0.date) < ($1.index ?? 0, $1.date) }
        var coords: [CLLocationCoordinate2D] = []
        for (i, m) in sorted.enumerated() {
            if let poly = m.polylinePoints, !poly.isEmpty {
                for p in poly {
                    coords.append(CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude))
                }
            } else {
                if i == sorted.count - 1 {
                    let lat = m.endLatitude ?? m.latitude
                    let lon = m.endLongitude ?? m.longitude
                    coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                } else {
                    let lat = m.startLatitude ?? m.latitude
                    let lon = m.startLongitude ?? m.longitude
                    coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                }
            }
        }
        return coords
    }

}
