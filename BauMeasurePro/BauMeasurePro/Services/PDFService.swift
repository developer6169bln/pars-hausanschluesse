import UIKit
import CoreLocation
import ImageIO

class PDFService {
    // MARK: - Koordinaten / Genauigkeit Formatierung
    private struct UTMCoord {
        let zone: Int
        let hemisphereIsNorth: Bool
        let easting: Double
        let northing: Double
    }

    private static func formatLatLon(_ lat: Double, _ lon: Double, decimals: Int = 5) -> String {
        let latStr = String(format: "%.\(decimals)f", lat).replacingOccurrences(of: ".", with: ",")
        let lonStr = String(format: "%.\(decimals)f", lon).replacingOccurrences(of: ".", with: ",")
        return "\(latStr), \(lonStr)"
    }

    private static func compassLabel(courseDeg: Double) -> String {
        // 8er-Kompass in Deutsch: N, NO, O, SO, S, SW, W, NW
        let d = (courseDeg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        switch d {
        case 0..<22.5, 337.5..<360: return "N"
        case 22.5..<67.5: return "NO"
        case 67.5..<112.5: return "O"
        case 112.5..<157.5: return "SO"
        case 157.5..<202.5: return "S"
        case 202.5..<247.5: return "SW"
        case 247.5..<292.5: return "W"
        default: return "NW"
        }
    }

    /// UTM-Koordinaten (WGS84) aus Lat/Lon.
    /// Hinweis: Spezialfälle für Norwegen/Svalbard werden hier nicht behandelt (für DE typischerweise ausreichend).
    private static func utm(from lat: Double, lon: Double) -> UTMCoord? {
        guard lat >= -80.0 && lat <= 84.0 else { return nil }

        let a = 6378137.0 // WGS84 semi-major axis
        let f = 1.0 / 298.257223563
        let k0 = 0.9996
        let e2 = f * (2.0 - f)
        let ePrime2 = e2 / (1.0 - e2)

        let zone = Int(floor((lon + 180.0) / 6.0)) + 1
        let latRad = lat * Double.pi / 180.0
        let lonRad = lon * Double.pi / 180.0
        let lonOrigin = Double(zone - 1) * 6.0 - 180.0 + 3.0
        let lonOriginRad = lonOrigin * Double.pi / 180.0

        let sinLat = sin(latRad)
        let cosLat = cos(latRad)
        let tanLat = tan(latRad)

        let N = a / sqrt(1.0 - e2 * sinLat * sinLat)
        let T = tanLat * tanLat
        let C = ePrime2 * cosLat * cosLat
        let A = (lonRad - lonOriginRad) * cosLat

        let M = a * (
            (1 - e2/4 - 3*e2*e2/64 - 5*pow(e2, 3)/256) * latRad
            - (3*e2/8 + 3*e2*e2/32 + 45*pow(e2, 3)/1024) * sin(2*latRad)
            + (15*e2*e2/256 + 45*pow(e2, 3)/1024) * sin(4*latRad)
            - (35*pow(e2, 3)/3072) * sin(6*latRad)
        )

        let easting = k0 * N * (
            A
            + (1 - T + C) * pow(A, 3) / 6
            + (5 - 18*T + T*T + 72*C - 58*ePrime2) * pow(A, 5) / 120
        ) + 500000.0

        var northing = k0 * (
            M
            + N * tanLat * (
                pow(A, 2)/2
                + (5 - T + 9*C + 4*C*C) * pow(A, 4) / 24
                + (61 - 58*T + T*T + 600*C - 330*ePrime2) * pow(A, 6) / 720
            )
        )

        let hemisphereIsNorth = lat >= 0
        if !hemisphereIsNorth {
            northing += 10000000.0
        }

        return UTMCoord(zone: zone, hemisphereIsNorth: hemisphereIsNorth, easting: easting, northing: northing)
    }

    private static func utmString(from lat: Double, lon: Double) -> String? {
        guard let u = utm(from: lat, lon: lon) else { return nil }
        let hem = u.hemisphereIsNorth ? "n" : "s"
        let e = Int(u.easting.rounded())
        let n = Int(u.northing.rounded())
        return "UTM:\(u.zone)\(hem) \(e) \(n)"
    }

    /// MGRS mit Standard-100km-Gitter-Lettern (WGS84).
    private static func mgrsString(from lat: Double, lon: Double) -> String? {
        guard let u = utm(from: lat, lon: lon) else { return nil }

        // Latitude band letters C..X (X repeated for 80-84N)
        let latBands = Array("CDEFGHJKLMNPQRSTUVWXX")
        let bandIndex = Int(floor(lat / 8.0 + 10.0))
        let bandIndexClamped = max(0, min(latBands.count - 1, bandIndex))
        let band = String(latBands[bandIndexClamped])

        let e100kLetters = [ "ABCDEFGH", "JKLMNPQR", "STUVWXYZ" ]
        let n100kLetters = [ "ABCDEFGHJKLMNPQRSTUV", "FGHJKLMNPQRSTUVABCDE" ]

        let zone = u.zone

        // column / e100k
        let col = Int(floor(u.easting / 100000.0))
        let eLetterSet = e100kLetters[(zone - 1) % 3]
        let eIdx = max(0, min(eLetterSet.count - 1, col - 1))
        let e100k = String(eLetterSet[eLetterSet.index(eLetterSet.startIndex, offsetBy: eIdx)])

        // row / n100k
        let row = Int(floor(u.northing / 100000.0)) % 20
        let nLetterSet = n100kLetters[(zone - 1) % 2]
        let nIdx = max(0, min(nLetterSet.count - 1, row))
        let n100k = String(nLetterSet[nLetterSet.index(nLetterSet.startIndex, offsetBy: nIdx)])

        // e/n within 100km square (truncate)
        let eWithin = Int(floor(mod(u.easting, 100000.0)))
        let nWithin = Int(floor(mod(u.northing, 100000.0)))

        let zonePadded = String(format: "%02d", zone)
        let e5 = String(format: "%05d", eWithin)
        let n5 = String(format: "%05d", nWithin)
        return "\(zonePadded)\(band)\(e100k)\(n100k)\(e5)\(n5)"
    }

    private static func mod(_ x: Double, _ m: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: m)
        return r >= 0 ? r : r + m
    }

    private static func directionString(course: Double?, courseAccuracy: Double?) -> String? {
        guard let c = course else { return nil }
        let label = compassLabel(courseDeg: c)
        let deg = Int(c.rounded())
        if let acc = courseAccuracy {
            let a = Int(acc.rounded())
            return "Richtung: \(label)\(deg)° (±\(a)°)"
        }
        return "Richtung: \(label)\(deg)°"
    }

    private static func heightString(altitude: Double?, verticalAccuracy: Double?) -> String? {
        guard let a = altitude else { return nil }
        let altInt = Int(a.rounded())
        if let va = verticalAccuracy {
            let vInt = Int(va.rounded())
            return "Höhe: \(altInt) m (±\(vInt)m)"
        }
        return "Höhe: \(altInt) m"
    }
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

    /// Projektbericht: Projektdaten → AR-Messungen → nur Kartenfoto (Route) → zugewiesene Punktfotos → optional Abnahme & Bauhinderung.
    static func createProjectReport(project: Project, completion: @escaping (URL) -> Void) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("project_\(project.id.uuidString).pdf")
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try? renderer.writePDF(to: path) { ctx in
            drawProjectPages(ctx: ctx, project: project, pageRect: pageRect)
            if projectHasAbnahmeAnhang(project) {
                drawAbnahmeReportPages(ctx: ctx, project: project, pageRect: pageRect)
            }
            if projectHasBauhinderungAnhang(project) {
                drawBauhinderungReportPages(ctx: ctx, project: project, pageRect: pageRect)
            }
        }
        DispatchQueue.main.async { completion(path) }
    }

    /// Abnahme-Daten vorhanden (für PDF-Anhang).
    private static func projectHasAbnahmeAnhang(_ project: Project) -> Bool {
        if project.abnahmeProtokollUnterschriftPath != nil { return true }
        if project.abnahmeOhneMaengel != nil { return true }
        if project.abnahmeProtokollDatum != nil { return true }
        if let t = project.abnahmeMaengelText, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    private static func bauhinderungReportHasContent(_ r: BauhinderungReport) -> Bool {
        if let t = r.ticketNummer, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let t = r.netzbetreiber, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let t = r.tiefbauunternehmen, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if r.datumEinsatz != nil { return true }
        if r.uhrzeitAnkunft != nil { return true }
        if r.uhrzeitVerlassen != nil { return true }
        if let m = r.monteurKolonne, !m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let anyAllgemein = r.kundeNichtAnwesend || r.keinZugangGrundstueck || r.keinZugangGebaeude
            || r.zustimmungHauseinfuehrungNichtErteilt || r.arbeitsbereichBlockiert
            || r.oberflaecheNichtFreigegeben || r.versorgungsleitungenVerhindern
            || r.leerrohrNichtAuffindbarOderBeschaedigt || r.sicherheitsrisiko || r.witterung
        if anyAllgemein { return true }
        let anyTech = r.anschlusspunktNichtAuffindbar || r.tiereFreilaufend || r.tiereNichtGesichert
        if anyTech { return true }
        if let b = r.beschreibungBauhindernis, !b.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let h = r.hinweiseAuftraggeber, !h.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if r.fotoDokuErstellt || r.kundeVorOrtInformiert || r.kundeTelefonischKontaktiert { return true }
        if r.telefonErgebnis != .none { return true }
        if r.uhrzeitAnruf != nil { return true }
        let anyStatus = r.arbeitenNichtBegonnen || r.arbeitenUnterbrochen || r.hausanschlussTeilweise
            || r.weitereKlaerungNoetig || r.neuerTerminNoetig
        if anyStatus { return true }
        if let o = r.ort, !o.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if r.datum != nil { return true }
        if let n = r.nameMonteurBauleiter, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if r.unterschriftPath != nil { return true }
        return false
    }

    private static func projectHasBauhinderungAnhang(_ project: Project) -> Bool {
        guard let r = project.bauhinderung else { return false }
        return bauhinderungReportHasContent(r)
    }

    private static func arMeterProtocolString(_ segments: [Double]) -> String {
        var parts: [String] = []
        parts.append("A=0.00")
        for (i, m) in segments.enumerated() {
            let idx = i + 1 // B = 1
            let label: String
            if idx < 26 {
                label = String(Unicode.Scalar(65 + idx)!)
            } else {
                label = "\(idx + 1)"
            }
            parts.append("\(label)=+\(String(format: "%.2f", m))")
        }
        return parts.joined(separator: "  ")
    }

    // MARK: - PDF Bericht (modernes Layout)
    private static let pdfAccent = UIColor(red: 0.11, green: 0.32, blue: 0.55, alpha: 1.0)
    private static let pdfAccentSoft = UIColor(red: 0.93, green: 0.96, blue: 1.0, alpha: 1.0)
    private static let pdfTextMuted = UIColor(white: 0.38, alpha: 1.0)

    /// Deckblatt: nur allgemeine Projektdaten (Abschnitt 1).
    private static func drawProjectCoverPage(ctx: UIGraphicsPDFRendererContext, project: Project, pageRect: CGRect) {
        let cg = ctx.cgContext
        let w = pageRect.width
        let bandH: CGFloat = 140
        cg.setFillColor(pdfAccent.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: w, height: bandH))
        ("BauMeasurePro" as NSString).draw(
            at: CGPoint(x: 44, y: 22),
            withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: UIColor.white.withAlphaComponent(0.85)]
        )
        ("Projektbericht" as NSString).draw(
            at: CGPoint(x: 44, y: 48),
            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 26), .foregroundColor: UIColor.white]
        )
        (project.name as NSString).draw(
            at: CGPoint(x: 44, y: 88),
            withAttributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.white.withAlphaComponent(0.95)]
        )

        var y: CGFloat = bandH + 28
        let mx: CGFloat = 44
        let contentW = pageRect.width - 2 * mx

        func row(_ label: String, _ value: String) {
            let labelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: pdfTextMuted]
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ]
            (label as NSString).draw(at: CGPoint(x: mx, y: y), withAttributes: labelAttrs)
            y += 14
            let vh = value as NSString
            let h = ceil(vh.boundingRect(with: CGSize(width: contentW, height: 4000), options: .usesLineFragmentOrigin, attributes: valAttrs, context: nil).height)
            vh.draw(in: CGRect(x: mx, y: y, width: contentW, height: max(h, 16)), withAttributes: valAttrs)
            y += max(22, h + 10)
        }

        func cardTitle(_ t: String) {
            y += 8
            cg.setFillColor(pdfAccentSoft.cgColor)
            let titleH: CGFloat = 28
            cg.fill(CGRect(x: mx - 6, y: y, width: contentW + 12, height: titleH))
            (t as NSString).draw(
                at: CGPoint(x: mx, y: y + 6),
                withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: pdfAccent]
            )
            y += titleH + 12
        }

        cardTitle("ÜBERSICHT")
        row("Angelegt", project.createdAt.formatted(date: .abbreviated, time: .shortened))
        row("Gesamtlänge (Projekt)", String(format: "%.2f m · %.0f px", project.totalMeters, project.totalLength))
        row("Auftrag abgeschlossen", (project.auftragAbgeschlossen ?? false) ? "Ja" : "Nein")
        if let t = project.termin {
            row("Termin", t.formatted(date: .abbreviated, time: .shortened))
        }

        cardTitle("ADRESSE & KUNDE")
        if let s = project.strasse, !s.isEmpty { row("Straße / Hausnr.", "\(s) \(project.hausnummer ?? "")") }
        if let plz = project.postleitzahl, !plz.isEmpty { row("PLZ / Ort", "\(plz) \(project.ort ?? "")") }
        if let name = project.kundeName, !name.isEmpty { row("Name Kunde", name) }
        if let tel = project.kundeTelefon, !tel.isEmpty { row("Telefon", tel) }
        if let mail = project.kundeEmail, !mail.isEmpty { row("E-Mail", mail) }

        cardTitle("TECHNISCH")
        if let nvt = project.nvtNummer, !nvt.isEmpty { row("NVT-Nummer", nvt) }
        if let k = project.kolonne, !k.isEmpty { row("Kolonne", k) }
        if let vg = project.verbundGroesse, !vg.isEmpty { row("Verbund Größe", vg) }
        if let vf = project.verbundFarbe, !vf.isEmpty { row("Verbund Farbe", vf) }
        let pf1 = project.pipesFarbe1 ?? project.pipesFarbe
        let pf2 = project.pipesFarbe2
        if let p1 = pf1, !p1.isEmpty {
            let pipesText = pf2 != nil && !pf2!.isEmpty ? "\(p1) / \(pf2!)" : p1
            row("Pipes Farbe", pipesText)
        }

        if let gd = project.googleDriveLink, !gd.isEmpty { row("Google Drive", gd) }
        if let n = project.notizen, !n.isEmpty { row("Notizen", n) }
        if let t = project.telefonNotizen, !t.isEmpty { row("Telefon-Notizen", t) }
        if let b = project.kundenBeschwerden, !b.isEmpty {
            row("Beschwerden", b)
            if let d = project.kundenBeschwerdenUnterschriebenAm {
                y += 4
                ("Unterschrieben: \(d.formatted(date: .abbreviated, time: .shortened))" as NSString).draw(
                    at: CGPoint(x: mx, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: pdfTextMuted]
                )
                y += 18
            }
        }
        if let t = project.auftragBestaetigtText, !t.isEmpty {
            row("Auftragsbestätigung", t)
            if let d = project.auftragBestaetigtUnterschriebenAm {
                y += 4
                ("Unterschrieben: \(d.formatted(date: .abbreviated, time: .shortened))" as NSString).draw(
                    at: CGPoint(x: mx, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: pdfTextMuted]
                )
                y += 18
            }
        }

        let footer = "Erstellt mit BauMeasurePro"
        (footer as NSString).draw(
            at: CGPoint(x: mx, y: pageRect.height - 36),
            withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: pdfTextMuted]
        )
    }

    /// Kopfzeile für Innenseiten (Messungen, Karte, Punktfotos).
    private static func drawInnerPageHeader(cg: CGContext, pageRect: CGRect, title: String, badge: String) -> CGFloat {
        let h: CGFloat = 56
        cg.setFillColor(pdfAccent.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: pageRect.width, height: h))
        (title as NSString).draw(
            at: CGPoint(x: 44, y: 18),
            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 17), .foregroundColor: UIColor.white]
        )
        let badgeAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: UIColor.white]
        let bs = (badge as NSString).size(withAttributes: badgeAttrs)
        let bx = pageRect.width - bs.width - 48
        cg.setFillColor(UIColor.white.withAlphaComponent(0.22).cgColor)
        cg.fill(CGRect(x: bx - 10, y: 14, width: bs.width + 20, height: 28))
        (badge as NSString).draw(at: CGPoint(x: bx, y: 20), withAttributes: badgeAttrs)
        return h + 20
    }

    private static func drawProjectPages(ctx: UIGraphicsPDFRendererContext, project: Project, pageRect: CGRect) {
        ctx.beginPage()
        drawProjectCoverPage(ctx: ctx, project: project, pageRect: pageRect)

        let storage = StorageService()
        let sorted = project.measurements.sorted { ($0.index ?? 0, $0.date) < ($1.index ?? 0, $1.date) }
        let margin: CGFloat = 40
        let maxImageWidth = pageRect.width - 2 * margin
        let maxImageHeight: CGFloat = 420
        var arCount = 0
        var kartenfotoCount = 0

        /// Nur gespeicherte Kartenfotos aus der App (Skizze / Mini-Karte), keine normalen Fotos.
        func isKartenfotoRoute(_ m: Measurement) -> Bool {
            !m.isARMeasurement && m.address == "Kartenfoto (Route)"
        }

        func drawMeasurementPage(m: Measurement, isAR: Bool, idxText: String, sectionTitle: String) {
            ctx.beginPage()
            let cg = ctx.cgContext
            var pageY = drawInnerPageHeader(cg: cg, pageRect: pageRect, title: sectionTitle, badge: idxText)
            ("Adresse / Notiz" as NSString).draw(
                at: CGPoint(x: margin, y: pageY),
                withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: pdfTextMuted]
            )
            pageY += 14
            (m.address as NSString).draw(
                in: CGRect(x: margin, y: pageY, width: pageRect.width - 2 * margin, height: 44),
                withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.label]
            )
            pageY += 22

            // Neue GPS/Genauigkeitswerte direkt auf jeder Messungs-/Foto-Seite.
            // Bei AR-Messungen halten wir es kompakt (Seite ist ohnehin voll).
            if m.latitude != 0 || m.longitude != 0 {
                let geoFont = UIFont.systemFont(ofSize: isAR ? 9 : 10)
                let lineStep: CGFloat = isAR ? 10 : 12
                ("GPS: \(formatLatLon(m.latitude, m.longitude))" as NSString).draw(
                    at: CGPoint(x: margin, y: pageY),
                    withAttributes: [.font: geoFont]
                )
                pageY += lineStep

                let haInt: Int? = m.horizontalAccuracy.map { Int($0.rounded()) }
                if let haInt {
                    ("Genauigkeit (horizontal): ±\(haInt) m" as NSString).draw(
                        at: CGPoint(x: margin, y: pageY),
                        withAttributes: [.font: geoFont]
                    )
                    pageY += lineStep
                }

                var utmLineParts: [String] = []
                if let utm = utmString(from: m.latitude, lon: m.longitude) { utmLineParts.append(utm) }
                if let mgrs = mgrsString(from: m.latitude, lon: m.longitude) {
                    if let haInt {
                        utmLineParts.append("MGRS: \(mgrs) (±\(haInt)m)")
                    } else {
                        utmLineParts.append("MGRS: \(mgrs)")
                    }
                }
                if !utmLineParts.isEmpty {
                    let line = utmLineParts.joined(separator: " | ")
                    (line as NSString).draw(
                        at: CGPoint(x: margin, y: pageY),
                        withAttributes: [.font: geoFont]
                    )
                    pageY += lineStep
                }

                if !isAR, let h = heightString(altitude: m.altitude, verticalAccuracy: m.verticalAccuracy) {
                    (h as NSString).draw(
                        at: CGPoint(x: margin, y: pageY),
                        withAttributes: [.font: geoFont]
                    )
                    pageY += lineStep
                }

                if !isAR, let d = directionString(course: m.course, courseAccuracy: m.courseAccuracy) {
                    (d as NSString).draw(
                        at: CGPoint(x: margin, y: pageY),
                        withAttributes: [.font: geoFont]
                    )
                    pageY += lineStep
                }
            }

            if isAR {
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
            if isAR {
                // Abschlussbericht: nur Startpunkt-GPS als Orientierung (keine komplette GPS-Polyline).
                ("Startpunkt A (GPS): \(m.startLatitude ?? m.latitude), \(m.startLongitude ?? m.longitude)" as NSString)
                    .draw(at: CGPoint(x: margin, y: pageY), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                pageY += 16

                // AR-Messwerte (Segmentmeter + Gesamt)
                if let seg = m.polylineSegmentMeters, !seg.isEmpty {
                    let proto = arMeterProtocolString(seg)
                    let total = seg.reduce(0, +)
                    ("AR‑Messwerte:" as NSString).draw(
                        at: CGPoint(x: margin, y: pageY),
                        withAttributes: [.font: UIFont.boldSystemFont(ofSize: 11)]
                    )
                    pageY += 14
                    (proto as NSString).draw(
                        in: CGRect(x: margin, y: pageY, width: pageRect.width - 2 * margin, height: 44),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 11)]
                    )
                    pageY += 34
                    (String(format: "Gesamt = %.2f m", total) as NSString).draw(
                        at: CGPoint(x: margin, y: pageY),
                        withAttributes: [.font: UIFont.boldSystemFont(ofSize: 11)]
                    )
                    pageY += 18
                } else {
                    pageY += 8
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
                if pageY + drawH > pageRect.height - 40 {
                    ctx.beginPage()
                    pageY = drawInnerPageHeader(cg: ctx.cgContext, pageRect: pageRect, title: sectionTitle, badge: idxText + " · Forts.")
                }
                img.draw(in: CGRect(x: margin, y: pageY, width: drawW, height: drawH))
            }
        }

        // 1) Alle AR-Messungen, 2) nur Kartenfoto (Route) — gleiche Sortierung wie in der App.
        for m in sorted where m.isARMeasurement {
            arCount += 1
            drawMeasurementPage(m: m, isAR: true, idxText: "Messung \(arCount)", sectionTitle: "AR-Messung")
        }
        for m in sorted where isKartenfotoRoute(m) {
            kartenfotoCount += 1
            drawMeasurementPage(m: m, isAR: false, idxText: "Karte \(kartenfotoCount)", sectionTitle: "Foto-Messung · Kartenfoto (Route)")
        }

        // 3) Zugewiesene Punktfotos (eine Seite pro Foto).
        func letter(for pointIndex: Int) -> String {
            if pointIndex >= 0 && pointIndex < 26 { return String(Unicode.Scalar(65 + pointIndex)!) }
            return "\(pointIndex + 1)"
        }

        func loadThumbnail(from storedPath: String, maxPixel: Int) -> UIImage? {
            let full = storage.fullPath(forStoredPath: storedPath)
            guard FileManager.default.fileExists(atPath: full),
                  let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: full) as CFURL, nil) else {
                return nil
            }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }

        func cumulativeMeters(for measurement: Measurement, pointIndex: Int) -> Double {
            guard pointIndex > 0 else { return 0 }
            if let seg = measurement.polylineSegmentMeters, !seg.isEmpty {
                let n = min(pointIndex, seg.count)
                return seg.prefix(n).reduce(0, +)
            }
            guard let poly = measurement.polylinePoints, poly.count >= 2 else { return 0 }
            let n = min(pointIndex, poly.count - 1)
            var sum: Double = 0
            for i in 0..<n {
                let a = CLLocation(latitude: poly[i].latitude, longitude: poly[i].longitude)
                let b = CLLocation(latitude: poly[i + 1].latitude, longitude: poly[i + 1].longitude)
                sum += a.distance(from: b)
            }
            return sum
        }

        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "de_DE")
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2

        var pointPhotoCounter = 0
        for m in sorted where m.isARMeasurement {
            guard let poly = m.polylinePoints, !poly.isEmpty,
                  let pointPhotos = m.polylinePointPhotos,
                  !pointPhotos.isEmpty
            else { continue }
            let photosSorted: [PolylinePointPhoto]
            // Wenn neue Zuordnungen mit sourceMeasurementId vorhanden sind,
            // ignorieren wir Legacy-Einträge ohne diese ID und behalten pro Quelle nur die neueste.
            if pointPhotos.contains(where: { $0.sourceMeasurementId != nil }) {
                var bySource: [UUID: PolylinePointPhoto] = [:]
                for pp in pointPhotos where pp.sourceMeasurementId != nil {
                    let sid = pp.sourceMeasurementId!
                    if let existing = bySource[sid] {
                        if pp.date > existing.date { bySource[sid] = pp }
                    } else {
                        bySource[sid] = pp
                    }
                }
                photosSorted = Array(bySource.values).sorted { $0.date < $1.date }
            } else {
                photosSorted = pointPhotos.sorted { $0.date < $1.date }
            }
            for pp in photosSorted {
                guard pp.pointIndex >= 0, pp.pointIndex < poly.count else { continue }
                pointPhotoCounter += 1
                let point = poly[pp.pointIndex]
                let dist = cumulativeMeters(for: m, pointIndex: pp.pointIndex)
                let distText = nf.string(from: NSNumber(value: dist)) ?? String(format: "%.2f", dist).replacingOccurrences(of: ".", with: ",")

                ctx.beginPage()
                let cgP = ctx.cgContext
                let ptBadge = "Punkt \(letter(for: pp.pointIndex))"
                var y = drawInnerPageHeader(cg: cgP, pageRect: pageRect, title: "Zugewiesenes Punktfoto", badge: ptBadge)
                let sub = "Strecke ab Start: \(distText) m · Datum \(pp.date.formatted(date: .abbreviated, time: .shortened))"
                (sub as NSString).draw(
                    at: CGPoint(x: 44, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: pdfTextMuted]
                )
                y += 18
                ("Messung: \(m.address)" as NSString).draw(
                    in: CGRect(x: 44, y: y, width: pageRect.width - 88, height: 36),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.label]
                )
                y += 40

                // Thumbnail
                if let img = loadThumbnail(from: pp.imagePath, maxPixel: 1200) {
                    let maxW: CGFloat = pageRect.width - 80
                    let maxH: CGFloat = 320
                    let scale = min(maxW / img.size.width, maxH / img.size.height, 1.0)
                    let drawW = img.size.width * scale
                    let drawH = img.size.height * scale
                    // Wenn zu wenig Platz: Bild nach unten ziehen, damit Titel/Geo-Block erhalten bleiben.
                    if y + drawH > pageRect.height - 40 {
                        y = max(40, pageRect.height - 40 - drawH)
                    }
                    img.draw(in: CGRect(x: 40, y: y, width: drawW, height: drawH))
                    y += drawH + 10
                }

                // Geo Block
                let haInt = point.horizontalAccuracy.map { Int($0.rounded()) }
                ("⌖ \(formatLatLon(point.latitude, point.longitude))" as NSString).draw(
                    at: CGPoint(x: 40, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 10)]
                )
                y += 12
                if let haInt {
                    ("Genauigkeit (horizontal): ±\(haInt) m" as NSString).draw(
                        at: CGPoint(x: 40, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 10)]
                    )
                    y += 12
                }
                var geoLineParts: [String] = []
                if let utm = utmString(from: point.latitude, lon: point.longitude) { geoLineParts.append(utm) }
                if let mgrs = mgrsString(from: point.latitude, lon: point.longitude) {
                    if let haInt { geoLineParts.append("MGRS: \(mgrs) (±\(haInt)m)") }
                    else { geoLineParts.append("MGRS: \(mgrs)") }
                }
                if !geoLineParts.isEmpty {
                    (geoLineParts.joined(separator: " | ") as NSString).draw(
                        at: CGPoint(x: 40, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 10)]
                    )
                    y += 12
                }
                if let h = heightString(altitude: point.altitude, verticalAccuracy: point.verticalAccuracy) {
                    (h as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
                    y += 12
                }
                if let d = directionString(course: point.course, courseAccuracy: point.courseAccuracy) {
                    (d as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
                    y += 12
                }
            }
        }

    }

    // MARK: - Abnahmeprotokoll & Bauhinderung (einzeln oder als Anhang im Projekt-PDF)

    private static func drawAbnahmeReportPages(ctx: UIGraphicsPDFRendererContext, project: Project, pageRect: CGRect) {
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

        let ohne = project.abnahmeOhneMaengel
        let checkFont = UIFont.systemFont(ofSize: 16)
        let line1 = (ohne == true ? "☒" : "☐") + " Bei der Abnahme wurden keine sichtbaren Mängel festgestellt."
        let line2 = (ohne == false ? "☒" : "☐") + " Folgende Mängel wurden festgestellt und werden noch beseitigt:"
        (line1 as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: checkFont])
        y += 30
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

    private static func drawBauhinderungReportPages(ctx: UIGraphicsPDFRendererContext, project: Project, pageRect: CGRect) {
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

    /// Separater Abnahmeprotokoll-Bericht (nur Abnahme, mit Auswahl, Mängeltext und Unterschrift).
    static func createAbnahmeReport(project: Project, completion: @escaping (URL) -> Void) {
        let format = UIGraphicsPDFRendererFormat()
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Abnahme-\(UUID().uuidString).pdf")
        DispatchQueue.global(qos: .userInitiated).async {
            try? renderer.writePDF(to: url) { ctx in
                drawAbnahmeReportPages(ctx: ctx, project: project, pageRect: pageRect)
            }
            DispatchQueue.main.async { completion(url) }
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
                drawBauhinderungReportPages(ctx: ctx, project: project, pageRect: pageRect)
            }
            DispatchQueue.main.async { completion(url) }
        }
    }

}
