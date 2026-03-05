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

## Build

```bash
npm run build
```
