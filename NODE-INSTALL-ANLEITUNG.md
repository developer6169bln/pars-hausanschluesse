# Node.js installieren (damit `npm` funktioniert)

Die Meldung **„command not found: npm“** bedeutet: Node.js ist nicht installiert oder nicht im Suchpfad (PATH).

## Option 1: Offizieller Installer (empfohlen)

1. Öffne im Browser: **https://nodejs.org**
2. Lade die **LTS-Version** (grüner Button) für macOS herunter.
3. Öffne die heruntergeladene `.pkg`-Datei und folge der Installation.
4. **Terminal komplett schließen** und **neu öffnen** (oder Cursor neu starten).
5. Prüfen:
   ```bash
   node -v
   npm -v
   ```
   Es sollten Versionsnummern erscheinen (z. B. `v20.10.0` und `10.2.0`).

---

## Option 2: Über Homebrew (falls du Homebrew nutzt)

Im Terminal:

```bash
brew install node
```

Danach Terminal neu öffnen und `node -v` sowie `npm -v` prüfen.

---

## Danach: Admin-Web starten

Wenn `node` und `npm` laufen:

**Terminal 1 – Server:**
```bash
cd "/Users/yaskomasko/Documents/curser daten/hausanschluesse-app"
npm run server
```

**Terminal 2 – Web-App (neues Tab/Fenster):**
```bash
cd "/Users/yaskomasko/Documents/curser daten/hausanschluesse-app"
npm run dev
```

Im Browser: **http://localhost:5180** öffnen (Port steht in `vite.config.js`; abweichend siehe Terminal-Ausgabe von `npm run dev`).
