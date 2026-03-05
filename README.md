# Pars Hausanschlüsse

Webapp für die Erfassung und Dokumentation von Glasfaser-Hausanschlüssen (Tiefbau). Aufträge anlegen, Standort speichern, Fotos per Kamera aufnehmen und Aufträge nach Status (offen/abgeschlossen) mit Gesamtlänge verwalten.

## Technologie

- React, Vite
- Optional: Node/Express-Server für **Bilder, Dokumente und Fotos** sowie **Auftragsliste** – dann für alle Nutzer sichtbar

## Start (nur App, lokale Speicherung)

```bash
npm install
npm run dev
```

Öffne http://localhost:5180 (oder den angezeigten Port). Daten und Fotos liegen nur im Browser (localStorage).

## Start mit Server (für alle Nutzer sichtbar)

1. **Server starten** (in einem Terminal):
   ```bash
   npm run server
   ```
   Server läuft auf Port 3001.

2. **Umgebungsvariable setzen**: Erstelle `.env` (siehe `.env.example`):
   ```
   VITE_API_URL=http://localhost:3001
   ```
   Bei Produktion: `VITE_API_URL=https://deine-domain.de`

3. **App starten** (in einem weiteren Terminal):
   ```bash
   npm run dev
   ```

Dann werden Fotos, PDFs und die Auftragsliste auf dem Server gespeichert; alle Nutzer sehen dieselben Daten und Dateien.

## Build

```bash
npm run build
```
