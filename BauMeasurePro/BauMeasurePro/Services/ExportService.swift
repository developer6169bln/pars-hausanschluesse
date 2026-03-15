import Foundation
import CoreLocation

/// Export von Projekt-Polylinien als GeoJSON (GIS) und DXF (CAD).
enum ExportService {

    /// Ermittelt die Route des Projekts (Reihenfolge wie auf der Karte): Polylinien-Punkte bzw. Start/Ende pro Messung.
    static func routeCoordinates(for project: Project) -> [CLLocationCoordinate2D] {
        let sorted = project.measurements.sorted { ($0.index ?? 0, $0.date) < ($1.index ?? 0, $1.date) }
        var coords: [CLLocationCoordinate2D] = []
        for (i, m) in sorted.enumerated() {
            if let poly = m.polylinePoints, !poly.isEmpty {
                for p in poly {
                    coords.append(CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude))
                }
            } else {
                if i == sorted.count - 1 {
                    if let lat = m.endLatitude, let lon = m.endLongitude {
                        coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    } else {
                        coords.append(CLLocationCoordinate2D(latitude: m.latitude, longitude: m.longitude))
                    }
                } else {
                    if let lat = m.startLatitude, let lon = m.startLongitude {
                        coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    } else {
                        coords.append(CLLocationCoordinate2D(latitude: m.latitude, longitude: m.longitude))
                    }
                }
            }
        }
        return coords
    }

    /// Exportiert die Projekt-Route als GeoJSON Feature (LineString). Für GIS-Tools.
    static func exportGeoJSON(project: Project) -> String {
        let coords = routeCoordinates(for: project)
        let coordinates = coords.map { "[\($0.longitude),\($0.latitude)]" }.joined(separator: ", ")
        let name = project.name.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {
          "type": "Feature",
          "properties": { "name": "\(name)" },
          "geometry": {
            "type": "LineString",
            "coordinates": [\(coordinates)]
          }
        }
        """
    }

    /// Exportiert die Projekt-Route als DXF (2D-Linien, Längen in m relativ zum ersten Punkt). Für CAD (z. B. AutoCAD).
    /// Verwendet eine einfache lokale Projektion: erster Punkt = Ursprung, Längen in Metern.
    static func exportDXF(project: Project) -> String {
        let coords = routeCoordinates(for: project)
        guard let first = coords.first, coords.count >= 2 else {
            return "0\nSECTION\n2\nHEADER\n0\nENDSEC\n0\nEOF\n"
        }
        func toMeters(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)
            let origin = CLLocation(latitude: first.latitude, longitude: first.longitude)
            let dy = (c.latitude - first.latitude) * 111_320
            let dx = (c.longitude - first.longitude) * 111_320 * cos(first.latitude * .pi / 180)
            return (dx, dy)
        }
        var dxf = "0\nSECTION\n2\nENTITIES\n"
        for i in 0..<(coords.count - 1) {
            let a = toMeters(coords[i])
            let b = toMeters(coords[i + 1])
            dxf += """
            0\nLINE\n8\n0\n
            10\n\(a.x)\n20\n\(a.y)\n30\n0.0\n
            11\n\(b.x)\n21\n\(b.y)\n31\n0.0\n
            """
        }
        dxf += "0\nENDSEC\n0\nEOF\n"
        return dxf
    }

    /// Schreibt GeoJSON in eine temporäre Datei und gibt die URL zurück (für Share Sheet).
    static func writeGeoJSONToTemp(project: Project) -> URL? {
        let content = exportGeoJSON(project: project)
        let name = (project.name + "_route").components(separatedBy: .illegalCharacters).joined() + ".geojson"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Schreibt DXF in eine temporäre Datei und gibt die URL zurück (für Share Sheet).
    static func writeDXFToTemp(project: Project) -> URL? {
        let content = exportDXF(project: project)
        let name = (project.name + "_route").components(separatedBy: .illegalCharacters).joined() + ".dxf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
