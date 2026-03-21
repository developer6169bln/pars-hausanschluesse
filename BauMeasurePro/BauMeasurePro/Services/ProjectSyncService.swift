import Foundation

/// Synchronisiert ein Projekt (Messungen, Fotos, 3D-Scans, Abnahme, Bauhinderung) mit dem Admin-Server.
enum ProjectSyncService {

    /// Synchronisiert ein Projekt, das bereits eine `serverProjectId` hat.
    static func sync(project: Project, storage: StorageService, serverBaseURL: String) async throws {
        guard let serverId = project.serverProjectId, !serverId.isEmpty else {
            throw ProjectSyncError.noServerProjectId
        }
        let base = serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/")
            ? String(serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).dropLast())
            : serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: base) else { throw ProjectSyncError.invalidServerURL }

        var pathToURL: [String: String] = [:]

        // 1) Messungs-Bilder hochladen
        for m in project.measurements {
            let path = m.imagePath
            if path.isEmpty || path.hasPrefix("http") { continue }
            if let url = try? await uploadFile(
                localPath: storage.fullPath(forStoredPath: path),
                projectId: serverId,
                baseURL: baseURL
            ) {
                pathToURL[path] = url
            }
            // Zwischenfotos (punktbezogen) hochladen
            for pp in (m.polylinePointPhotos ?? []) {
                let p = pp.imagePath
                if p.isEmpty || p.hasPrefix("http") { continue }
                if let url = try? await uploadFile(
                    localPath: storage.fullPath(forStoredPath: p),
                    projectId: serverId,
                    baseURL: baseURL
                ) {
                    pathToURL[p] = url
                }
            }
        }

        // 2) 3D-Scans hochladen
        for scan in project.threeDScans {
            let path = scan.filePath
            if path.isEmpty || path.hasPrefix("http") { continue }
            if let url = try? await uploadFile(
                localPath: storage.fullPath(forStoredPath: path),
                projectId: serverId,
                baseURL: baseURL
            ) {
                pathToURL[path] = url
            }
        }

        // 3) Unterschriften hochladen
        if let p = project.abnahmeProtokollUnterschriftPath, !p.isEmpty, !p.hasPrefix("http") {
            if let url = try? await uploadFile(
                localPath: storage.fullPath(forStoredPath: p),
                projectId: serverId,
                baseURL: baseURL
            ) {
                pathToURL[p] = url
            }
        }
        if var bau = project.bauhinderung, let p = bau.unterschriftPath, !p.isEmpty, !p.hasPrefix("http") {
            if let url = try? await uploadFile(
                localPath: storage.fullPath(forStoredPath: p),
                projectId: serverId,
                baseURL: baseURL
            ) {
                pathToURL[p] = url
            }
        }

        func urlFor(path: String?) -> String? {
            guard let p = path, !p.isEmpty else { return nil }
            if p.hasPrefix("http") { return p }
            return pathToURL[p] ?? p
        }

        // 4) Payload bauen und PATCH
        let payload = buildPatchPayload(project: project, urlFor: urlFor)
        let status = try await patchProject(projectId: serverId, payload: payload, baseURL: baseURL)
        guard (200...299).contains(status) else {
            throw ProjectSyncError.patchFailed(status: status)
        }
    }

    /// Synchronisiert ein Projekt auch dann, wenn es lokal erstellt wurde (ohne `serverProjectId`).
    /// In diesem Fall wird das Projekt beim ersten Sync auf dem Server angelegt (POST /api/projects)
    /// und anschließend normal gepatcht (inkl. Uploads).
    static func syncOrCreate(project: Project, storage: StorageService, serverBaseURL: String) async throws -> Project {
        let base = serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/")
            ? String(serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).dropLast())
            : serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: base) else { throw ProjectSyncError.invalidServerURL }

        // Stabil: Wir verwenden die lokale UUID als Server-ID, damit keine Duplikate entstehen.
        var ensured = project
        if ensured.serverProjectId == nil || ensured.serverProjectId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            ensured.serverProjectId = ensured.id.uuidString
        }
        let serverId = ensured.serverProjectId ?? ensured.id.uuidString

        do {
            try await sync(project: ensured, storage: storage, serverBaseURL: base)
            return ensured
        } catch let ProjectSyncError.patchFailed(status) where status == 404 {
            // Projekt existiert noch nicht -> anlegen, dann erneut synchronisieren.
            let createPayload = buildCreatePayload(project: ensured)
            let createStatus = try await createProject(payload: createPayload, baseURL: baseURL)
            guard (200...299).contains(createStatus) else {
                throw ProjectSyncError.createFailed(status: createStatus)
            }
            try await sync(project: ensured, storage: storage, serverBaseURL: base)
            return ensured
        }
    }

    private static func uploadFile(localPath: String, projectId: String, baseURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: localPath) else {
            throw ProjectSyncError.fileNotFound(localPath)
        }
        let fileURL = URL(fileURLWithPath: localPath)
        let filename = fileURL.lastPathComponent
        let uploadURL = baseURL.appendingPathComponent("api/projects/\(projectId)/upload")

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        data.append(try Data(contentsOf: fileURL))
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = data

        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ProjectSyncError.uploadFailed
        }
        struct UploadResponse: Decodable { let url: String? }
        let decoded = try JSONDecoder().decode(UploadResponse.self, from: body)
        guard let url = decoded.url else { throw ProjectSyncError.uploadFailed }
        return url
    }

    private static func patchProject(projectId: String, payload: Data, baseURL: URL) async throws -> Int {
        let patchURL = baseURL.appendingPathComponent("api/projects/\(projectId)")
        var request = URLRequest(url: patchURL)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    private static func createProject(payload: Data, baseURL: URL) async throws -> Int {
        let url = baseURL.appendingPathComponent("api/projects")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    private static func buildCreatePayload(project: Project) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func iso(_ d: Date?) -> String? { d.map { formatter.string(from: $0) } }
        func opt<T>(_ x: T?) -> Any { x ?? NSNull() }
        // Wichtig: ID mitsenden, damit der Server dieses Projekt unter derselben UUID speichert.
        let payload: [String: Any] = [
            "id": project.serverProjectId ?? project.id.uuidString,
            "name": project.name,
            "createdAt": opt(iso(project.createdAt)),
            "measurements": [],
            "assignedToUserId": NSNull(),
            "strasse": opt(project.strasse),
            "hausnummer": opt(project.hausnummer),
            "postleitzahl": opt(project.postleitzahl),
            "ort": opt(project.ort),
            "nvtNummer": opt(project.nvtNummer),
            "kolonne": opt(project.kolonne),
            "verbundGroesse": opt(project.verbundGroesse),
            "verbundFarbe": opt(project.verbundFarbe),
            "pipesFarbe1": opt(project.pipesFarbe1),
            "pipesFarbe2": opt(project.pipesFarbe2),
            "auftragAbgeschlossen": opt(project.auftragAbgeschlossen),
            "ampelStatus": opt(project.ampelStatus),
            "termin": opt(iso(project.termin)),
            "googleDriveLink": opt(project.googleDriveLink),
            "notizen": opt(project.notizen),
            "kundeName": opt(project.kundeName),
            "kundeTelefon": opt(project.kundeTelefon),
            "kundeEmail": opt(project.kundeEmail),
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private static func buildPatchPayload(project: Project, urlFor: (String?) -> String?) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func iso(_ d: Date?) -> String? {
            guard let d = d else { return nil }
            return formatter.string(from: d)
        }
        func opt<T>(_ x: T?) -> Any { x ?? NSNull() }

        var measurementsArray: [[String: Any]] = []
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for m in project.measurements {
            if let encoded = try? encoder.encode(m),
               var dict = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
                dict["imagePath"] = urlFor(m.imagePath) ?? m.imagePath
                if dict["oberflaeche"] == nil { dict["oberflaeche"] = NSNull() }
                if dict["oberflaecheSonstige"] == nil { dict["oberflaecheSonstige"] = NSNull() }
                if dict["verlegeart"] == nil { dict["verlegeart"] = NSNull() }
                if dict["verlegeartSonstige"] == nil { dict["verlegeartSonstige"] = NSNull() }
                measurementsArray.append(dict)
            } else {
                let pointsArray = m.points.map { p in ["id": p.id.uuidString, "x": p.x, "y": p.y, "distance": p.distance] as [String: Any] }
                let polylinePointsArray = (m.polylinePoints ?? []).map { p in
                    [
                        "id": p.id.uuidString,
                        "latitude": p.latitude,
                        "longitude": p.longitude,
                        "horizontalAccuracy": opt(p.horizontalAccuracy),
                        "verticalAccuracy": opt(p.verticalAccuracy),
                        "altitude": opt(p.altitude),
                        "course": opt(p.course),
                        "courseAccuracy": opt(p.courseAccuracy),
                    ] as [String: Any]
                }
                measurementsArray.append([
                    "id": m.id.uuidString,
                    "imagePath": urlFor(m.imagePath) ?? m.imagePath,
                    "latitude": m.latitude,
                    "longitude": m.longitude,
                    "horizontalAccuracy": opt(m.horizontalAccuracy),
                    "verticalAccuracy": opt(m.verticalAccuracy),
                    "altitude": opt(m.altitude),
                    "course": opt(m.course),
                    "courseAccuracy": opt(m.courseAccuracy),
                    "address": m.address,
                    "points": pointsArray,
                    "totalDistance": m.totalDistance,
                    "referenceMeters": opt(m.referenceMeters),
                    "index": opt(m.index),
                    "startLatitude": opt(m.startLatitude),
                    "startLongitude": opt(m.startLongitude),
                    "endLatitude": opt(m.endLatitude),
                    "endLongitude": opt(m.endLongitude),
                    "isARMeasurement": m.isARMeasurement,
                    "oberflaeche": opt(m.oberflaeche),
                    "oberflaecheSonstige": opt(m.oberflaecheSonstige),
                    "verlegeart": opt(m.verlegeart),
                    "verlegeartSonstige": opt(m.verlegeartSonstige),
                    "date": opt(iso(m.date)),
                    "polylinePoints": polylinePointsArray,
                    "polylineSegmentMeters": m.polylineSegmentMeters ?? [],
                    "polylineSegmentOberflaeche": (m.polylineSegmentOberflaeche ?? []).map { opt($0) },
                    "polylineSegmentVerlegeart": (m.polylineSegmentVerlegeart ?? []).map { opt($0) },
                    "sketchOffsetLat": opt(m.sketchOffsetLat),
                    "sketchOffsetLon": opt(m.sketchOffsetLon),
                    "sketchRotationDegrees": opt(m.sketchRotationDegrees),
                    "sketchScale": opt(m.sketchScale),
                    "sketchMirrored": m.sketchMirrored ?? false,
                    "sketchUseARSegments": m.sketchUseARSegments ?? true,
                    "sketchOverridePolylinePoints": (m.sketchOverridePolylinePoints ?? []).map { p in
                        [
                            "id": p.id.uuidString,
                            "latitude": p.latitude,
                            "longitude": p.longitude,
                            "horizontalAccuracy": opt(p.horizontalAccuracy),
                            "verticalAccuracy": opt(p.verticalAccuracy),
                            "altitude": opt(p.altitude),
                            "course": opt(p.course),
                            "courseAccuracy": opt(p.courseAccuracy),
                        ] as [String: Any]
                    },
                ])
            }
        }

        var threeDScansArray: [[String: Any]] = []
        for s in project.threeDScans {
            threeDScansArray.append([
                "id": s.id.uuidString,
                "name": s.name,
                "createdAt": opt(iso(s.createdAt)),
                "filePath": s.filePath,
                "url": opt(urlFor(s.filePath)),
                "note": opt(s.note),
                "latitude": opt(s.latitude),
                "longitude": opt(s.longitude),
                "sceneOriginX": opt(s.sceneOriginX),
                "sceneOriginY": opt(s.sceneOriginY),
                "sceneOriginZ": opt(s.sceneOriginZ),
            ])
        }

        var bauhinderungDict: [String: Any]? = nil
        if let b = project.bauhinderung {
            bauhinderungDict = [
                "ticketNummer": opt(b.ticketNummer),
                "netzbetreiber": opt(b.netzbetreiber),
                "tiefbauunternehmen": opt(b.tiefbauunternehmen),
                "datumEinsatz": opt(iso(b.datumEinsatz)),
                "uhrzeitAnkunft": opt(iso(b.uhrzeitAnkunft)),
                "uhrzeitVerlassen": opt(iso(b.uhrzeitVerlassen)),
                "monteurKolonne": opt(b.monteurKolonne),
                "kundeNichtAnwesend": b.kundeNichtAnwesend,
                "keinZugangGrundstueck": b.keinZugangGrundstueck,
                "keinZugangGebaeude": b.keinZugangGebaeude,
                "beschreibungBauhindernis": opt(b.beschreibungBauhindernis),
                "hinweiseAuftraggeber": opt(b.hinweiseAuftraggeber),
                "arbeitenNichtBegonnen": b.arbeitenNichtBegonnen,
                "neuerTerminNoetig": b.neuerTerminNoetig,
                "ort": opt(b.ort),
                "datum": opt(iso(b.datum)),
                "nameMonteurBauleiter": opt(b.nameMonteurBauleiter),
                "unterschriftPath": opt(urlFor(b.unterschriftPath)),
            ]
        }

        var payload: [String: Any] = [
            "name": project.name,
            "createdAt": opt(iso(project.createdAt)),
            "measurements": measurementsArray,
            "threeDScans": threeDScansArray,
            "strasse": opt(project.strasse),
            "hausnummer": opt(project.hausnummer),
            "postleitzahl": opt(project.postleitzahl),
            "ort": opt(project.ort),
            "nvtNummer": opt(project.nvtNummer),
            "kolonne": opt(project.kolonne),
            "verbundGroesse": opt(project.verbundGroesse),
            "verbundFarbe": opt(project.verbundFarbe),
            "pipesFarbe1": opt(project.pipesFarbe1),
            "pipesFarbe2": opt(project.pipesFarbe2),
            "auftragAbgeschlossen": opt(project.auftragAbgeschlossen),
            "ampelStatus": opt(project.ampelStatus),
            "termin": opt(iso(project.termin)),
            "googleDriveLink": opt(project.googleDriveLink),
            "notizen": opt(project.notizen),
            "kundeName": opt(project.kundeName),
            "kundeTelefon": opt(project.kundeTelefon),
            "kundeEmail": opt(project.kundeEmail),
            "telefonNotizen": opt(project.telefonNotizen),
            "kundenBeschwerden": opt(project.kundenBeschwerden),
            "kundenBeschwerdenUnterschriebenAm": opt(iso(project.kundenBeschwerdenUnterschriebenAm)),
            "auftragBestaetigtText": opt(project.auftragBestaetigtText),
            "auftragBestaetigtUnterschriebenAm": opt(iso(project.auftragBestaetigtUnterschriebenAm)),
            "abnahmeProtokollUnterschriftPath": opt(urlFor(project.abnahmeProtokollUnterschriftPath)),
            "abnahmeProtokollDatum": opt(iso(project.abnahmeProtokollDatum)),
            "abnahmeOhneMaengel": opt(project.abnahmeOhneMaengel),
            "abnahmeMaengelText": opt(project.abnahmeMaengelText),
        ]
        if let b = bauhinderungDict {
            payload["bauhinderung"] = b
        }

        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}

enum ProjectSyncError: LocalizedError {
    case noServerProjectId
    case invalidServerURL
    case fileNotFound(String)
    case uploadFailed
    case patchFailed(status: Int)
    case createFailed(status: Int)

    var errorDescription: String? {
        switch self {
        case .noServerProjectId: return "Projekt wurde nicht vom Server zugewiesen – Sync nicht möglich."
        case .invalidServerURL: return "Ungültige Server-URL."
        case .fileNotFound(let p): return "Datei nicht gefunden: \(p)"
        case .uploadFailed: return "Hochladen fehlgeschlagen."
        case .patchFailed(let s): return "Aktualisieren auf dem Server fehlgeschlagen (Status \(s))."
        case .createFailed(let s): return "Projekt konnte auf dem Server nicht angelegt werden (Status \(s))."
        }
    }
}
