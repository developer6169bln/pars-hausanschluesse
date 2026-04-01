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
    /// Optional wird das Bild in das iOS-Fotoalbum "HA Messung" exportiert.
    /// Wenn overlay gesetzt ist, wird unten ein transparenter Layer mit weißer Beschriftung gezeichnet.
    func saveImage(_ image: UIImage, projectName: String? = nil, overlay: PhotoOverlayInfo? = nil, exportToAlbum: Bool = true) -> String? {
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
            if exportToAlbum {
                PhotoLibraryService.saveToAlbum(image: imageToSave)
            }
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

    /// Speichert eine Punktwolke als PLY (ScanAce-ähnlich, RGB pro Punkt).
    /// Gibt den relativen Pfad zurück (z. B. „3dscans/<id>.ply“) oder nil bei Fehler.
    func savePointCloudPLY(_ data: Data, scanId: UUID) -> String? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let subdir = dir.appendingPathComponent("3dscans", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let fileName = "\(scanId.uuidString).ply"
        let url = subdir.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return "3dscans/\(fileName)"
        } catch {
            return nil
        }
    }

    // MARK: - Kabel-Leitungsweg (Polyline) für 3D-Scans

    struct CablePathPoint: Codable, Equatable {
        var x: Float
        var y: Float
        var z: Float
    }

    struct CablePath: Codable, Equatable {
        var points: [CablePathPoint]
        /// Automatisch aus Magenta-Punkten berechnete Mittellinie (Rohr im Viewer).
        var autoTracePoints: [CablePathPoint]?
        /// Radius des Auto-Rohres in Metern (Viewer-Darstellung).
        var autoTraceRadiusMeters: Double?
        var createdAt: Date
    }

    /// Speichert manuellen Leitungsweg und optional automatisch nachgezeichnete Mittellinie.
    /// Rückgabe ist relativer Pfad (z. B. "3dscans/<id>.cablepath.json") oder nil.
    func saveCablePath(manualPoints: [SIMD3<Float>], autoTracePoints: [SIMD3<Float>], autoTraceRadiusMeters: Double?, scanId: UUID) -> String? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let subdir = dir.appendingPathComponent("3dscans", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let fileName = "\(scanId.uuidString).cablepath.json"
        let url = subdir.appendingPathComponent(fileName)
        let autoEncoded: [CablePathPoint]? = autoTracePoints.isEmpty ? nil : autoTracePoints.map { CablePathPoint(x: $0.x, y: $0.y, z: $0.z) }
        let payload = CablePath(
            points: manualPoints.map { CablePathPoint(x: $0.x, y: $0.y, z: $0.z) },
            autoTracePoints: autoEncoded,
            autoTraceRadiusMeters: autoTraceRadiusMeters,
            createdAt: Date()
        )
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: [.atomic])
            return "3dscans/\(fileName)"
        } catch {
            return nil
        }
    }

    /// Lädt den manuell gezeichneten Leitungsweg (ansonsten leeres Array).
    func loadCablePathPoints(scanId: UUID) -> [SIMD3<Float>] {
        loadCablePath(scanId: scanId).manual
    }

    /// Automatisch nachgezeichnete Mittellinie (Magenta-Kabel), falls gespeichert.
    func loadCableAutoTracePoints(scanId: UUID) -> [SIMD3<Float>] {
        loadCablePath(scanId: scanId).autoTrace
    }

    func loadCableAutoTraceRadiusMeters(scanId: UUID) -> Double? {
        loadCablePath(scanId: scanId).autoRadiusMeters
    }

    private func loadCablePath(scanId: UUID) -> (manual: [SIMD3<Float>], autoTrace: [SIMD3<Float>], autoRadiusMeters: Double?) {
        let rel = "3dscans/\(scanId.uuidString).cablepath.json"
        let full = fullPath(forStoredPath: rel)
        guard FileManager.default.fileExists(atPath: full) else { return ([], [], nil) }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: full))
            let decoded = try JSONDecoder().decode(CablePath.self, from: data)
            let manual = decoded.points.map { SIMD3<Float>($0.x, $0.y, $0.z) }
            let auto = (decoded.autoTracePoints ?? []).map { SIMD3<Float>($0.x, $0.y, $0.z) }
            return (manual, auto, decoded.autoTraceRadiusMeters)
        } catch {
            return ([], [], nil)
        }
    }

    // MARK: - Orange Kugel (Detektion)

    struct OrangeSphereDetection: Codable, Equatable {
        var centerX: Float
        var centerY: Float
        var centerZ: Float
        var radiusMeters: Float
        var createdAt: Date
    }

    func saveOrangeSphereDetection(center: SIMD3<Float>, radiusMeters: Float, scanId: UUID) -> String? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let subdir = dir.appendingPathComponent("3dscans", isDirectory: true)
        do { try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true) } catch { return nil }
        let fileName = "\(scanId.uuidString).orangeSphere.json"
        let url = subdir.appendingPathComponent(fileName)
        let payload = OrangeSphereDetection(
            centerX: center.x, centerY: center.y, centerZ: center.z,
            radiusMeters: radiusMeters,
            createdAt: Date()
        )
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: [.atomic])
            return "3dscans/\(fileName)"
        } catch {
            return nil
        }
    }

    func loadOrangeSphereDetection(scanId: UUID) -> (center: SIMD3<Float>, radiusMeters: Float)? {
        let rel = "3dscans/\(scanId.uuidString).orangeSphere.json"
        let full = fullPath(forStoredPath: rel)
        guard FileManager.default.fileExists(atPath: full) else { return nil }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: full))
            let decoded = try JSONDecoder().decode(OrangeSphereDetection.self, from: data)
            return (SIMD3<Float>(decoded.centerX, decoded.centerY, decoded.centerZ), decoded.radiusMeters)
        } catch {
            return nil
        }
    }

    /// Speichert ein Zwischen-Segment für lange Mesh-Scans auf Disk.
    /// Rückgabe ist ein relativer Pfad (z. B. "3dscans/segments/<scanId>/segment-3.scn").
    func saveMeshSegmentScene(_ scene: SCNScene, scanId: UUID, segmentIndex: Int) -> String? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let subdir = dir
            .appendingPathComponent("3dscans", isDirectory: true)
            .appendingPathComponent("segments", isDirectory: true)
            .appendingPathComponent(scanId.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let fileName = "segment-\(segmentIndex).scn"
        let url = subdir.appendingPathComponent(fileName)
        do {
            try scene.write(to: url, options: nil, delegate: nil)
            return "3dscans/segments/\(scanId.uuidString)/\(fileName)"
        } catch {
            return nil
        }
    }

    /// Löscht alle temporären Mesh-Segmente eines Scans.
    func clearMeshSegments(scanId: UUID) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let subdir = dir
            .appendingPathComponent("3dscans", isDirectory: true)
            .appendingPathComponent("segments", isDirectory: true)
            .appendingPathComponent(scanId.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: subdir)
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
