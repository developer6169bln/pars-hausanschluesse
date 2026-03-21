import Foundation

/// Ruft die vom Admin zugewiesenen Projekte für eine Geräte-ID vom Server ab.
enum AssignedProjectsService {

    static func fetchAssignedProjects(deviceId: String, serverBaseURL: String) async throws -> [Project] {
        let trimmedId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { throw AssignedProjectsError.missingDeviceId }
        guard !trimmedBase.isEmpty else { throw AssignedProjectsError.missingServerURL }
        let base = trimmedBase.hasSuffix("/") ? String(trimmedBase.dropLast()) : trimmedBase
        guard let url = URL(string: "\(base)/api/mobile/assigned-projects?deviceId=\(trimmedId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedId)") else {
            throw AssignedProjectsError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw AssignedProjectsError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw AssignedProjectsError.serverError(status: http.statusCode)
        }
        return try mapJSONToProjects(data)
    }

    private static func mapJSONToProjects(_ data: Data) throws -> [Project] {
        let decoded = try JSONDecoder().decode([ApiProject].self, from: data)
        return decoded.map { $0.toProject() }
    }
}

enum AssignedProjectsError: LocalizedError {
    case missingDeviceId
    case missingServerURL
    case invalidURL
    case invalidResponse
    case serverError(status: Int)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .missingDeviceId: return "Bitte Geräte-ID eintragen."
        case .missingServerURL: return "Bitte Server-URL eintragen."
        case .invalidURL: return "Ungültige Server-URL."
        case .invalidResponse: return "Ungültige Server-Antwort."
        case .serverError(let s): return "Server-Fehler (Status \(s))."
        case .decodeFailed: return "Daten konnten nicht gelesen werden."
        }
    }
}

/// Server-JSON: Projekt mit String-IDs und ISO-Datum.
private struct ApiProject: Decodable {
    let id: String?
    let name: String?
    let createdAt: String?
    let measurements: [ApiMeasurement]?
    let strasse: String?
    let hausnummer: String?
    let postleitzahl: String?
    let ort: String?
    let nvtNummer: String?
    let kolonne: String?
    let verbundGroesse: String?
    let verbundFarbe: String?
    let pipesFarbe: String?
    let pipesFarbe1: String?
    let pipesFarbe2: String?
    let auftragAbgeschlossen: Bool?
    let ampelStatus: String?
    let termin: String?
    let googleDriveLink: String?
    let notizen: String?
    let kundeName: String?
    let kundeTelefon: String?
    let kundeEmail: String?
    let threeDScans: [ApiThreeDScan]?

    func toProject() -> Project {
        let projId = (id.flatMap { UUID(uuidString: $0) }) ?? UUID()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let created = (createdAt.flatMap { formatter.date(from: $0) }) ?? (createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }) ?? Date()
        let measurementsList = (measurements ?? []).map { $0.toMeasurement() }
        let termDate = termin.flatMap { formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        let scans = (threeDScans ?? []).map { $0.toThreeDScan() }
        return Project(
            id: projId,
            serverProjectId: id,
            name: name ?? "Projekt",
            measurements: measurementsList,
            createdAt: created,
            strasse: strasse,
            hausnummer: hausnummer,
            postleitzahl: postleitzahl,
            ort: ort,
            nvtNummer: nvtNummer,
            kolonne: kolonne,
            verbundGroesse: verbundGroesse,
            verbundFarbe: verbundFarbe,
            pipesFarbe: pipesFarbe,
            pipesFarbe1: pipesFarbe1,
            pipesFarbe2: pipesFarbe2,
            auftragAbgeschlossen: auftragAbgeschlossen,
            ampelStatus: ampelStatus,
            termin: termDate,
            googleDriveLink: googleDriveLink,
            notizen: notizen,
            kundeName: kundeName,
            kundeTelefon: kundeTelefon,
            kundeEmail: kundeEmail,
            threeDScans: scans
        )
    }
}

private struct ApiPolylinePoint: Decodable {
    let id: String?
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracy: Double?
    let verticalAccuracy: Double?
    let altitude: Double?
    let course: Double?
    let courseAccuracy: Double?
}

private struct ApiMeasurement: Decodable {
    let id: String?
    let imagePath: String?
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracy: Double?
    let verticalAccuracy: Double?
    let altitude: Double?
    let course: Double?
    let courseAccuracy: Double?
    let address: String?
    let points: [ApiPhotoPoint]?
    let totalDistance: Double?
    let referenceMeters: Double?
    let index: Int?
    let startLatitude: Double?
    let startLongitude: Double?
    let endLatitude: Double?
    let endLongitude: Double?
    let isARMeasurement: Bool?
    let oberflaeche: String?
    let oberflaecheSonstige: String?
    let verlegeart: String?
    let verlegeartSonstige: String?
    let date: String?
    let polylinePoints: [ApiPolylinePoint]?
    let polylineSegmentMeters: [Double]?
    let polylineSegmentOberflaeche: [String?]?
    let polylineSegmentVerlegeart: [String?]?
    let sketchOffsetLat: Double?
    let sketchOffsetLon: Double?
    let sketchRotationDegrees: Double?
    let sketchScale: Double?
    let sketchMirrored: Bool?
    let sketchOverridePolylinePoints: [ApiPolylinePoint]?
    let sketchUseARSegments: Bool?
    let polylinePointPhotos: [ApiPolylinePointPhoto]?

    func toMeasurement() -> Measurement {
        let poly: [PolylinePoint]? = (polylinePoints ?? []).isEmpty ? nil : (polylinePoints?.map { p in
            PolylinePoint(
                id: (p.id.flatMap { UUID(uuidString: $0) }) ?? UUID(),
                latitude: p.latitude ?? 0,
                longitude: p.longitude ?? 0,
                horizontalAccuracy: p.horizontalAccuracy,
                verticalAccuracy: p.verticalAccuracy,
                altitude: p.altitude,
                course: p.course,
                courseAccuracy: p.courseAccuracy
            )
        })
        let sketchOverride: [PolylinePoint]? = (sketchOverridePolylinePoints ?? []).isEmpty ? nil : (sketchOverridePolylinePoints?.map { p in
            PolylinePoint(
                id: (p.id.flatMap { UUID(uuidString: $0) }) ?? UUID(),
                latitude: p.latitude ?? 0,
                longitude: p.longitude ?? 0,
                horizontalAccuracy: p.horizontalAccuracy,
                verticalAccuracy: p.verticalAccuracy,
                altitude: p.altitude,
                course: p.course,
                courseAccuracy: p.courseAccuracy
            )
        })
        let segMeters: [Double]? = (polylineSegmentMeters ?? []).isEmpty ? nil : polylineSegmentMeters
        let pointPhotos: [PolylinePointPhoto]? = (polylinePointPhotos ?? []).isEmpty ? nil : (polylinePointPhotos?.map { x in
            PolylinePointPhoto(
                id: (x.id.flatMap { UUID(uuidString: $0) }) ?? UUID(),
                pointIndex: x.pointIndex ?? 0,
                imagePath: x.imagePath ?? "",
                date: (x.date.flatMap { ISO8601DateFormatter().date(from: $0) }) ?? Date()
            )
        })
        return Measurement(
            id: (id.flatMap { UUID(uuidString: $0) }) ?? UUID(),
            imagePath: imagePath ?? "",
            latitude: latitude ?? 0,
            longitude: longitude ?? 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            altitude: altitude,
            course: course,
            courseAccuracy: courseAccuracy,
            address: address ?? "",
            points: (points ?? []).map { $0.toPhotoPoint() },
            totalDistance: totalDistance ?? 0,
            referenceMeters: referenceMeters,
            index: index,
            startLatitude: startLatitude,
            startLongitude: startLongitude,
            endLatitude: endLatitude,
            endLongitude: endLongitude,
            isARMeasurement: isARMeasurement ?? false,
            oberflaeche: oberflaeche,
            oberflaecheSonstige: oberflaecheSonstige,
            verlegeart: verlegeart,
            verlegeartSonstige: verlegeartSonstige,
            date: (date.flatMap { ISO8601DateFormatter().date(from: $0) }) ?? Date(),
            polylinePoints: poly,
            polylineSegmentMeters: segMeters,
            polylineSegmentOberflaeche: polylineSegmentOberflaeche,
            polylineSegmentVerlegeart: polylineSegmentVerlegeart,
            sketchOffsetLat: sketchOffsetLat,
            sketchOffsetLon: sketchOffsetLon,
            sketchRotationDegrees: sketchRotationDegrees,
            sketchScale: sketchScale,
            sketchMirrored: sketchMirrored,
            sketchOverridePolylinePoints: sketchOverride,
            sketchUseARSegments: sketchUseARSegments,
            polylinePointPhotos: pointPhotos
        )
    }
}

private struct ApiPolylinePointPhoto: Decodable {
    let id: String?
    let pointIndex: Int?
    let imagePath: String?
    let date: String?
}

private struct ApiPhotoPoint: Decodable {
    let id: String?
    let x: Double?
    let y: Double?
    let distance: Double?

    func toPhotoPoint() -> PhotoPoint {
        PhotoPoint(
            id: (id.flatMap { UUID(uuidString: $0) }) ?? UUID(),
            x: x ?? 0,
            y: y ?? 0,
            distance: distance ?? 0
        )
    }
}

private struct ApiThreeDScan: Decodable {
    let id: String?
    let name: String?
    let createdAt: String?
    let filePath: String?
    let note: String?
    let latitude: Double?
    let longitude: Double?
    let sceneOriginX: Double?
    let sceneOriginY: Double?
    let sceneOriginZ: Double?

    func toThreeDScan() -> ThreeDScan {
        ThreeDScan(
            id: (id.flatMap { UUID(uuidString: $0) }) ?? UUID(),
            name: name ?? "3D-Scan",
            createdAt: (createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }) ?? Date(),
            filePath: filePath ?? "",
            note: note,
            latitude: latitude,
            longitude: longitude,
            sceneOriginX: sceneOriginX,
            sceneOriginY: sceneOriginY,
            sceneOriginZ: sceneOriginZ
        )
    }
}
