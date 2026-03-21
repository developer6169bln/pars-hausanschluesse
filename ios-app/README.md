# Hausanschlüsse – iOS-App (Baugruben-Messung)

Native iOS-App für die Baugruben-Messung per ARKit. Nutzt dasselbe Backend wie die Web-App (`/api/auftraege`). Aufträge können in der App angezeigt, bearbeitet und um AR-gemessene Baugruben-Längen ergänzt werden.

**Getestet mit Xcode 26 (Release).**

## Voraussetzungen

- **Xcode 26** (Release) oder neuer
- **Swift 6.x** (mit Xcode 26)
- **iOS 19+** (Ziel-Plattform für ARKit)
- Gerät mit ARKit (iPhone/iPad) oder Simulator (eingeschränkt)

## Projekt in Xcode 26 anlegen

1. **Neues Projekt erstellen**
   - Xcode 26: **File → New → Project…**
   - **iOS → App**
   - Product Name: `HausanschlüsseBaugruben` (oder beliebig)
   - Team: dein Apple-Developer-Account
   - Organization Identifier: z. B. `de.parsbau`
   - Interface: **SwiftUI**, Language: **Swift**
   - Speichern (z. B. im Ordner `ios-app` dieses Repos)

2. **Swift-Dateien hinzufügen**
   - Alle `.swift`-Dateien aus diesem Ordner in das Xcode-Projekt ziehen (Target „HausanschlüsseBaugruben“ anhaken).
   - **Wichtig:** Es gibt zwei Varianten für den App-Start:
     - **Variante A (empfohlen):** Nur **einen** `@main`-Einstieg im Projekt haben. Entweder `HausanschluesseApp.swift` verwenden (zeigt direkt `AuftragListView`) oder die Xcode-Standard-App-Datei.
     - **Variante B:** Verwendet dein Projekt weiterhin die Standard-App mit `ContentView()`, dann muss `ContentView.swift` aus diesem Ordner im Target sein. In der **App-Datei** (z. B. `*App.swift`) den Store anlegen und übergeben:
       ```swift
       @main
       struct DeineApp: App {
           @StateObject private var store = AuftraegeStore(client: AuftraegeClient(baseURL: Config.apiBaseURL))
           var body: some Scene {
               WindowGroup {
                   ContentView()
                       .environmentObject(store)
               }
           }
       }
       ```
   - Der Einstiegspunkt ist entweder `@main struct HausanschluesseApp` (aus HausanschluesseApp.swift) oder deine eigene App-Struct mit `ContentView().environmentObject(store)`.

3. **ARKit & Kamera**
   - Im Target: **Signing & Capabilities** → **+ Capability** → **Camera** (falls angeboten).
   - In **Info** (oder Info.plist) hinzufügen:
     - **Privacy - Camera Usage Description**: `Für die AR-Messung der Baugrube wird die Kamera benötigt.`
   - ARKit braucht keine eigene Capability; die Kamera-Berechtigung reicht.

4. **Backend-URL anpassen**
   - In **Config.swift** die URL setzen:
     - Debug (Lokal): `http://localhost:3010` (Simulator) oder `http://<dein-Mac-IP>:3010` (Gerät im gleichen WLAN).
     - Release: `https://deine-domain.de` (gleiche Domain wie die Web-App).

5. **Build & Run**
   - Gerät auswählen (ARKit läuft nur auf echtem Gerät zuverlässig).
   - **Product → Run**.

## Ordnerstruktur (Quellcode)

```
ios-app/
├── HausanschluesseApp.swift   # App-Einstieg
├── Config.swift               # Backend-URL
├── Models.swift               # Auftrag, Attachment, FotoMeta
├── APIClient.swift            # API-Aufrufe
├── Store.swift                # AuftraegeStore (State)
├── AuftragListView.swift      # Liste der Aufträge
├── AuftragDetailView.swift    # Detail + Button „Baugrube messen (AR)“
├── BaugrubeARView.swift       # AR-Messung (Start-/Endpunkt, Länge)
└── README.md
```

## Ablauf

1. App startet → lädt Aufträge von `GET /api/auftraege`.
2. Auftrag tippen → Detail mit Stammdaten und Baugruben-Liste.
3. **„Baugrube messen (AR)“** → AR-View: Startpunkt tippen, Endpunkt tippen, Länge wird angezeigt.
4. **„Übernehmen“** → Länge wird an den Auftrag angehängt (`baugrubenLaengen`).
5. **„Speichern“** → `POST /api/auftraege` mit der aktualisierten Liste.

Die Web-App zeigt dieselben Aufträge und die Baugruben-Gesamtlänge; Änderungen aus der iOS-App erscheinen dort nach Reload.

## Änderungen in Cursor

Du kannst alle `.swift`-Dateien und diese README in Cursor bearbeiten. Nach dem Speichern in Xcode 26 die Dateien ggf. neu laden (sie liegen im gleichen Ordner wie das Xcode-Projekt).
