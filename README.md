# Pars Hausanschlüsse

Webapp für die Erfassung und Dokumentation von Glasfaser-Hausanschlüssen (Tiefbau). Aufträge anlegen, Standort speichern, Fotos per Kamera aufnehmen und Aufträge nach Status (offen/abgeschlossen) mit Gesamtlänge verwalten.

## Technologie

- React, Vite
- **Auftragspool nur auf dem Server** – Aufträge werden nicht lokal, sondern zentral gespeichert. Alle Nutzer sehen und bearbeiten denselben Pool.

## Start (Auftragspool – Server erforderlich)

1. **Server starten** (in einem Terminal):
   ```bash
   npm run server
   ```
   Server läuft auf Port 3010.

2. **Umgebungsvariable setzen**: Erstelle `.env` (siehe `.env.example`):
   ```
   VITE_API_URL=http://localhost:3010
   ```
   Bei Produktion: `VITE_API_URL=https://deine-domain.de`

3. **App starten** (in einem weiteren Terminal):
   ```bash
   npm run dev
   ```

Aufträge, Fotos und PDFs liegen nur auf dem Server; alle Nutzer arbeiten im gleichen Auftragspool. Ohne konfigurierten Server bleibt die Liste leer (Hinweis in der App).

## Admin: Monteure & Projekt-Zuweisung (BauMeasurePro-App)

Über die Webapp können **Monteure** (App-Nutzer) angelegt und **Projekte** diesen zugewiesen werden. Die BauMeasurePro-iOS-App kann dann nur die zugewiesenen Projekte abrufen.

1. **Monteure (App-Zuweisung)** (Link in der Übersicht): Monteure anlegen (Name, optionale Geräte-ID). Jeder Monteur erhält eine Geräte-ID – diese trägt er in der App ein.
2. **Projekte zuweisen** (Link in der Übersicht): Projekte anlegen und einem Monteur zuweisen (oder Zuweisung pro Projekt ändern).

**API für die App:**  
`GET /api/mobile/assigned-projects?deviceId=GERAETE-ID`  
Liefert alle Projekte, die dem Monteur mit dieser Geräte-ID zugewiesen sind. Die App sendet die Geräte-ID und erhält die Projektliste vom Server.

Daten liegen im Server-Verzeichnis in `users.json` und `projects.json` (bzw. unter `DATA_DIR`, falls gesetzt).

## Build

```bash
npm run build
```
