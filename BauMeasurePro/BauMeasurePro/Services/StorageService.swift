import Foundation
import UIKit
import SceneKit

/// Speichert alle Daten ausschließlich lokal auf dem Gerät (kein Server, keine Cloud).
/// Projekte & Messungen: UserDefaults. Fotos: App-Documents-Ordner.
class StorageService {
    private let projectsKey = "BauMeasurePro.projects"
    private let measurementsKey = "BauMeasurePro.measurements" // Migration von alter App
    private let kolonnenKey = "BauMeasurePro.kolonnen"
    private let deviceIdKey = "BauMeasurePro.deviceId"
    private let serverBaseURLKey = "BauMeasurePro.serverBaseURL"

    /// Geräte-ID des Monteurs (für Abruf zugewiesener Projekte vom Server).
    var deviceId: String {
        get { UserDefaults.standard.string(forKey: deviceIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: deviceIdKey) }
    }

    /// Basis-URL des Admin-Servers (z. B. https://mein-server.de oder http://192.168.1.100:3010).
    var serverBaseURL: String {
        get { UserDefaults.standard.string(forKey: serverBaseURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: serverBaseURLKey) }
    }

    func saveProjects(_ projects: [Project]) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: projectsKey)
    }

    func loadProjects() -> [Project] {
        if let data = UserDefaults.standard.data(forKey: projectsKey),
           let list = try? JSONDecoder().decode([Project].self, from: data) {
            return list
        }
        // Migration: alte Einzelmessungen als ein Projekt übernehmen
        if let data = UserDefaults.standard.data(forKey: measurementsKey),
           let old = try? JSONDecoder().decode([Measurement].self, from: data), !old.isEmpty {
            let project = Project(name: "Projekt 1", measurements: old, createdAt: Date())
            let projects = [project]
            saveProjects(projects)
            return projects
        }
        return []
    }

    func loadKolonnen() -> [String] {
        (UserDefaults.standard.array(forKey: kolonnenKey) as? [String]) ?? []
    }

    func saveKolonnen(_ list: [String]) {
        UserDefaults.standard.set(list, forKey: kolonnenKey)
    }

    /// Infos für den transparenten Beschriftungs-Layer unten auf dem Foto (Straße, Hausnummer, NVT, Datum/Uhrzeit).
    struct PhotoOverlayInfo {
        var strasse: String?
        var hausnummer: String?
        var nvtNummer: String?
        var date: Date?
        var oberflaecheText: String?
        var verlegeartText: String?
    }

    /// Speichert ein Bild lokal im App-Documents-Verzeichnis. Gibt nur den Dateinamen zurück (relativer Pfad),
    /// damit die Referenz nach App-Updates (Build & Run) weiterhin gültig bleibt.
    /// Zusätzlich wird das Bild in das iOS-Fotoalbum "HA Messung" exportiert.
    /// Wenn overlay gesetzt ist, wird unten ein transparenter Layer mit weißer Beschriftung gezeichnet.
    func saveImage(_ image: UIImage, projectName: String? = nil, overlay: PhotoOverlayInfo? = nil) -> String? {
        let imageToSave: UIImage
        if let ov = overlay {
            imageToSave = Self.drawPhotoOverlay(ov, on: image) ?? image
        } else if let name = projectName, !name.isEmpty {
            imageToSave = Self.drawPhotoOverlay(PhotoOverlayInfo(strasse: nil, hausnummer: nil, nvtNummer: nil, date: Date()), on: image, fallbackTitle: name) ?? image
        } else {
            imageToSave = image
        }
        guard let data = imageToSave.jpegData(compressionQuality: 0.8) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url)
            PhotoLibraryService.saveToAlbum(image: imageToSave)
            return name
        } catch {
            return nil
        }
    }

    /// Zeichnet unten einen transparenten Layer und darauf weiße Beschriftung.
    /// Für AR können zusätzlich Oberfläche + Verlegeart angezeigt werden.
    private static func drawPhotoOverlay(_ overlay: PhotoOverlayInfo, on image: UIImage, fallbackTitle: String? = nil) -> UIImage? {
        let w = image.size.width
        let h = image.size.height
        let padding: CGFloat = 12
        let lineSpacing: CGFloat = 4
        let numLines: CGFloat = 6
        let sizeScale: CGFloat = 1.5
        let barHeightRatio: CGFloat = 0.30 * sizeScale
        let barHeight = max(200, min(h * barHeightRatio, 360))
        let contentHeight = barHeight - padding * 2
        let totalSpacing = lineSpacing * (numLines - 1)
        let lineHeight = (contentHeight - totalSpacing) / numLines
        var fontSize = min(28, max(14, lineHeight * 0.82))
        fontSize *= sizeScale
        fontSize = min(42, max(18, fontSize))

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")

        let dateText = overlay.date.map { formatter.string(from: $0) } ?? "–"
        let hasProjectData = (overlay.strasse?.isEmpty == false) || (overlay.hausnummer?.isEmpty == false) || (overlay.nvtNummer?.isEmpty == false)
        let hasArData = (overlay.oberflaecheText?.isEmpty == false) || (overlay.verlegeartText?.isEmpty == false)
        let finalLines: [String]
        if hasProjectData {
            finalLines = [
                "Straße: \(overlay.strasse ?? "–")",
                "Hausnummer: \(overlay.hausnummer ?? "–")",
                "NVT: \(overlay.nvtNummer ?? "–")",
                "Datum: \(dateText)",
                "Oberfläche: \(overlay.oberflaecheText ?? "–")",
                "Verlegeart: \(overlay.verlegeartText ?? "–")"
            ]
        } else if let title = fallbackTitle {
            finalLines = [
                "Projekt: \(title)",
                "Datum: \(dateText)",
                "Oberfläche: \(overlay.oberflaecheText ?? (hasArData ? (overlay.oberflaecheText ?? "–") : "–"))",
                "Verlegeart: \(overlay.verlegeartText ?? (hasArData ? (overlay.verlegeartText ?? "–") : "–"))",
                " ",
                " "
            ]
        } else {
            finalLines = [
                "Straße: –",
                "Hausnummer: –",
                "NVT: –",
                "Datum: \(dateText)",
                "Oberfläche: \(overlay.oberflaecheText ?? "–")",
                "Verlegeart: \(overlay.verlegeartText ?? "–")"
            ]
        }

        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .natural
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let renderer = UIGraphicsImageRenderer(size: image.size)
        let result = renderer.image { _ in
            image.draw(at: .zero)

            let barRect = CGRect(x: 0, y: h - barHeight, width: w, height: barHeight)
            UIColor.black.withAlphaComponent(0.38).setFill()
            UIRectFill(barRect)

            var y = barRect.minY + padding
            for line in finalLines {
                let text = (line as NSString)
                let size = text.size(withAttributes: attrs)
                let rect = CGRect(x: padding, y: y, width: w - padding * 2, height: size.height + 2)
                text.draw(in: rect, withAttributes: attrs)
                y += size.height + lineSpacing
            }
        }
        return result
    }

    /// Speichert eine Unterschrift als PNG im Documents-Ordner (ohne Export ins Fotoalbum).
    func saveSignature(_ image: UIImage) -> String? {
        guard let data = image.pngData() else { return nil }
        let name = "signature-\(UUID().uuidString).png"
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return name
        } catch {
            return nil
        }
    }

    /// Speichert eine 3D-Szene (z. B. aus AR-Mesh) im Documents-Ordner.
    /// Legt bei Bedarf das Unterverzeichnis „3dscans“ an.
    /// Gibt den relativen Pfad zurück (z. B. „3dscans/<id>.scn“) oder nil bei Fehler.
    func save3DScene(_ scene: SCNScene, scanId: UUID) -> String? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let subdir = dir.appendingPathComponent("3dscans", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let fileName = "\(scanId.uuidString).scn"
        let url = subdir.appendingPathComponent(fileName)
        do {
            try scene.write(to: url, options: nil, delegate: nil)
            return "3dscans/\(fileName)"
        } catch {
            return nil
        }
    }

    /// Liefert den vollen Dateipfad für einen gespeicherten Bildnamen (oder Legacy-Vollpfad).
    /// Beim Laden immer diese Methode verwenden, damit sowohl neue (nur Dateiname) als auch
    /// alte (Vollpfad) Einträge funktionieren.
    func fullPath(forStoredPath path: String) -> String {
        // Nur absolute Pfade (z. B. Legacy) unverändert lassen; relative immer unter Documents auflösen.
        if path.hasPrefix("/") {
            return path
        }
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return path
        }
        return dir.appendingPathComponent(path).path
    }
}
