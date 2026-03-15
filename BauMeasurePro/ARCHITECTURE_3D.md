# Architektur: AR + LiDAR 3D-Messung & Export

Ziel der App: **AR + LiDAR 3D-Messung**, **fotorealistischer Scan**, **3D-Gebäude**, **cm-genaue Messung**, **Export CAD/GIS/3D**.

**Technologien:** ARKit, RealityKit, OpenStreetMap, MapLibre GL, Object Capture (RealityKit).  
**Zielgeräte:** z. B. iPhone 16 Pro Max (LiDAR).

---

## Gesamt-Workflow

```
LiDAR-Scan
    ↓
3D-Mesh (+ Klassifikation + Texturen)
    ↓
Texture Baking (optional)
    ↓
fotorealistisches Modell
    ↓
AR-Messpunkte (Raycast + Mesh-Snapping)
    ↓
Kalman-Filter (cm-Genauigkeit)
    ↓
Georeferenzierung (AR → GPS)
    ↓
3D-Karte (OpenStreetMap / MapLibre)
    ↓
Export CAD / GIS / 3D (DXF, GeoJSON, USDZ/OBJ)
```

---

## 1️⃣ AR + LiDAR Session (Mesh + Texturen)

Session mit Mesh-Reconstruction und automatischer Texturierung.

```swift
import ARKit
import RealityKit

func startARSession(arView: ARView) {
    let config = ARWorldTrackingConfiguration()
    config.sceneReconstruction = .meshWithClassification
    config.environmentTexturing = .automatic
    config.planeDetection = [.horizontal, .vertical]
    arView.session.run(config)
}
```

**Ergebnis:** LiDAR-Mesh, RGB-Texturen, klassifizierte Oberflächen.

**BauMeasurePro heute:** ARKit mit optionalem `.mesh`, Raycasting, Anchors.  
**Erweiterung:** `meshWithClassification` + `environmentTexturing = .automatic` wo unterstützt.

---

## 2️⃣ Mesh sammeln für fotorealistischen Scan

Alle `ARMeshAnchor` aus dem aktuellen Frame sammeln (für spätere Texturierung/Export).

```swift
func collectMeshAnchors(frame: ARFrame) -> [ARMeshAnchor] {
    frame.anchors.compactMap { $0 as? ARMeshAnchor }
}
```

**Hinweis:** Bei Verwendung von **RealityKit ARView** kommen Mesh-Anchors über `session.currentFrame?.anchors` bzw. über Delegates/Callbacks.

---

## 3️⃣ Texture Baking (Photogrammetry)

LiDAR-Mesh mit Kamerabildern kombinieren → texturiertes 3D-Modell.

**iOS:** RealityKit **Object Capture** (`PhotogrammetrySession`) – ab iOS 17, auf dem Gerät.

```swift
import RealityKit

// Input: Ordner mit Bildern oder PhotogrammetrySample-Sequenz
// Output: USDZ (oder anderes konfiguriertes Format)
func bakeTextures(input: URL, output: URL) async throws {
    let config = PhotogrammetrySession.Configuration()
    let session = try PhotogrammetrySession(input: input, configuration: config)
    let request = PhotogrammetrySession.Request.modelFile(url: output)
    try await session.process(requests: [request])
}
```

**Ergebnis:** texturiertes 3D-Modell (USDZ/OBJ), realistische Oberflächen.

**Hinweis:** `PhotogrammetrySession` erwartet Fotos/Scans als Input; LiDAR-Mesh kann über AR-Session gesammelt und mit Bildern fusioniert werden (App-spezifischer Pipeline-Schritt).

---

## 4️⃣ OpenStreetMap 3D / MapLibre

3D-Gebäude und Gelände über Tiles (z. B. MapLibre GL).

```swift
import MapLibre  // oder WKWebView mit MapLibre JS

func setup3DMap(view: UIView) -> MLNMapView {
    let map = MLNMapView(frame: view.bounds)
    map.styleURL = URL(string: "https://demotiles.maplibre.org/style.json")
    map.isPitchEnabled = true
    return map
}
```

Gebäude werden geladen, wenn das Style 3D-Buildings enthält.

**BauMeasurePro heute:** MapKit 2D, Polylinie, Screenshot.  
**Erweiterung:** MapLibre (native oder WebView) für 3D-Gebäude, gleiche Geo-Polylinie.

---

## 5️⃣ AR-Messpunkte (Raycast + Mesh-Snapping)

Punkte per Raycast setzen, bevorzugt auf Mesh (`.existingPlaneGeometry`).

```swift
func addMeasurementPoint(arView: ARView, location: CGPoint) -> SIMD3<Float>? {
    guard let query = arView.makeRaycastQuery(
        from: location,
        allowing: .estimatedPlane,
        alignment: .any
    ) else { return nil }
    let results = arView.session.raycast(query)
    guard let result = results.first else { return nil }
    let t = result.worldTransform
    return SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
}
```

**BauMeasurePro heute:** Raycast mit Priorität `.existingPlaneGeometry` → `.estimatedPlane`, Anchors für Drift-Korrektur.

---

## 6️⃣ Kalman-Filter für cm-Genauigkeit

Tracking-Noise und Drift reduzieren.

```swift
class KalmanFilter {
    var estimate: Float = 0
    var error: Float = 1
    var q: Float = 0.01   // Prozessrauschen
    var r: Float = 0.1    // Messrauschen

    func update(measurement: Float) -> Float {
        error += q
        let k = error / (error + r)
        estimate += k * (measurement - estimate)
        error *= (1 - k)
        return estimate
    }
}

// Anwendung auf Distanz
let filter = KalmanFilter()
let correctedDistance = filter.update(measurement: rawDistance)
```

**Erweiterung:** Pro Segment oder pro Gesamtlänge anwenden; ggf. 3D-Variante (x, y, z).

---

## 7️⃣ AR-Koordinaten → GPS (Georeferenzierung)

Damit Messungen auf der 3D-Karte erscheinen.

```swift
func arToGPS(point: SIMD3<Float>, origin: CLLocation) -> CLLocationCoordinate2D {
    let metersLat = 111_111.0
    let metersLon = metersLat * cos(origin.coordinate.latitude * .pi / 180)
    let lat = origin.coordinate.latitude + Double(point.z) / metersLat
    let lon = origin.coordinate.longitude + Double(point.x) / metersLon
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
}
```

**BauMeasurePro heute:** Äquivalent: Geräte-GPS beim Setzen jedes Punkts, Polylinie aus GPS-Punkten.

---

## 8️⃣ Export CAD / GIS / 3D

### DXF (CAD, z. B. AutoCAD)

```swift
func exportDXF(points: [SIMD3<Float>]) -> String {
    var dxf = "0\nSECTION\n2\nENTITIES\n"
    for i in 0..<(points.count - 1) {
        let a = points[i], b = points[i + 1]
        dxf += """
        0\nLINE\n8\n0\n
        10\n\(a.x)\n20\n\(a.z)\n30\n\(a.y)\n
        11\n\(b.x)\n21\n\(b.z)\n31\n\(b.y)\n
        """
    }
    dxf += "0\nENDSEC\n0\nEOF\n"
    return dxf
}
```

### GeoJSON (GIS)

```swift
func exportGeoJSON(coords: [CLLocationCoordinate2D]) -> String {
    let coordinates = coords.map { "[\($0.longitude),\($0.latitude)]" }.joined(separator: ",")
    return """
    {
      "type": "Feature",
      "geometry": { "type": "LineString", "coordinates": [\(coordinates)] }
    }
    """
}
```

**BauMeasurePro heute:** PDF mit Messungen/Karte.  
**Erweiterung:** DXF/GeoJSON aus gespeicherten Polylinien-Punkten (AR- oder GPS-Koordinaten).

---

## 9️⃣ 3D-Modell-Export (RealityKit)

```swift
// ModelEntity z. B. aus gescanntem Mesh erzeugt
func exportModel(entity: ModelEntity, url: URL) throws {
    try entity.export(to: url)
}
```

**Formate:** USDZ, OBJ, ggf. GLTF je nach API/Version.

---

## Status in BauMeasurePro

| Komponente              | Status        | Anmerkung                                      |
|-------------------------|---------------|------------------------------------------------|
| AR + LiDAR Session      | ✅ vorhanden  | Optional Mesh, Raycast, Anchors                |
| Mesh + Klassifikation   | 🔲 Roadmap    | `meshWithClassification`, `environmentTexturing` |
| Mesh sammeln            | 🔲 Roadmap    | `ARMeshAnchor` für Export/Baking               |
| Texture Baking          | 🔲 Roadmap    | Object Capture (PhotogrammetrySession)         |
| MapLibre / OSM 3D       | 🔲 Roadmap    | 3D-Gebäude, aktuell MapKit 2D                  |
| AR-Messpunkte           | ✅ vorhanden  | Raycast, Polylinie, GPS                        |
| Kalman-Filter           | 🔲 Roadmap    | Für Distanz/Position                           |
| AR → GPS                | ✅ vorhanden  | Pro Punkt GPS, Polylinie                       |
| DXF / GeoJSON Export    | 🔲 Roadmap    | Aus gespeicherten Messungen                    |
| 3D-Modell-Export        | 🔲 Roadmap    | USDZ/OBJ aus Scan                              |

---

## Nächste Schritte (Priorität)

1. **ARKit:** `meshWithClassification` + `environmentTexturing = .automatic` aktivieren.
2. **Kalman-Filter:** Optional für Distanz (oder 3D-Position) in der AR-Messung.
3. **Export:** DXF + GeoJSON aus Projekt-Polylinie (bereits gespeicherte Koordinaten).
4. **3D-Karte:** MapLibre (oder MapKit 3D) mit gleicher Polylinie.
5. **Object Capture:** Pipeline „Scan → Fotos + Mesh → PhotogrammetrySession → USDZ“.

Dieses Dokument dient als Referenz und Roadmap für die beschriebene Architektur.
