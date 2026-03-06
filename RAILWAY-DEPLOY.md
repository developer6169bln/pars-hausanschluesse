# Server auf Railway deployen

So hostest du den Auftragspool-Server bei Railway (kostenlos nutzbar). Danach brauchst du lokal keinen `npm run server` mehr – alle nutzen die gleiche URL.

## 1. Bei Railway anmelden

- Gehe zu [railway.app](https://railway.app) und melde dich an (z.B. mit GitHub).

## 2. Neues Projekt aus GitHub

- **New Project** → **Deploy from GitHub repo**
- Repo auswählen: `pars-hausanschluesse` (oder dein Fork)
- Railway erstellt ein neues Projekt und startet einen Build.

## 3. Root-Verzeichnis, Build und Start

- In der Service-Konfiguration (Settings):
  - **Root Directory:** leer lassen (Projekt-Root)
  - **Build Command:** `npm run build` (baut das Frontend in `dist/`, damit die Startseite geliefert wird)
  - **Start Command:** `npm run start` (startet den Server, der API + Frontend ausliefert)
  - **Watch Paths:** leer

Die Datei `railway.json` setzt den Build-Befehl und **Start Command** = `node server/index.js` (direkt ohne npm, damit der Container stabil läuft). Unter **Settings → Build** prüfen: **Build Command** = `npm run build`, **Start Command** = `node server/index.js`. Optional unter **Settings → Deploy** einen **Health Check** mit Pfad `/api/health` einrichten.

Railway nutzt automatisch die Variable **PORT** – der Server verwendet sie bereits.

## 4. Umgebungsvariablen für die öffentliche URL

Im Railway-Dashboard: deinen Service öffnen → **Variables**. Beide Variablen auf die **gleiche** öffentliche URL setzen (ohne Slash am Ende), z.B. `https://pars-hausanschluesse-production.up.railway.app`:

| Name | Wert | Zweck |
|------|------|--------|
| `API_BASE` | `https://deine-app.up.railway.app` | Upload-Links und Server-Basis-URL |
| `VITE_API_URL` | `https://deine-app.up.railway.app` | Wird beim **Build** eingebettet, damit das Frontend die API unter derselben Domain aufruft |

Die URL findest du unter **Settings** → **Networking** → **Generate Domain** (oder **Public Networking**). Ohne `VITE_API_URL` weiß die gebaute App nicht, wo die API liegt, und die Auftragsliste bleibt leer.

## 5. Frontend mit der Railway-URL bauen

Die **Web-App** (Vite) muss die API-URL der Railway-Instanz kennen:

- Beim **Build** der App (lokal oder in CI) die Umgebungsvariable setzen:
  ```bash
  VITE_API_URL=https://deine-railway-url.up.railway.app npm run build
  ```
- Oder in einer `.env.production` (wird nicht ins Repo committed):
  ```
  VITE_API_URL=https://deine-railway-url.up.railway.app
  ```

Wenn du auch das Frontend auf Railway (oder z.B. Vercel/Netlify) deployst, dort **VITE_API_URL** auf die gleiche Railway-Server-URL setzen.

## 6. **Wichtig: Aufträge dauerhaft speichern (kein Datenverlust bei Redeploy)**

Ohne persistenten Speicher gehen **alle Aufträge und hochgeladenen Dateien bei jedem Redeploy verloren**. Damit die Daten bleiben:

1. **Volume hinzufügen**
   - Im Railway-Dashboard: deinen Service öffnen → **Settings** → **Volumes**
   - **Add Volume** → Mount Path: `/data` (oder z.B. `data`)
   - Volume wird bei Redeploy beibehalten.

2. **Umgebungsvariable setzen**
   - Unter **Variables** eine neue Variable anlegen:
   - **Name:** `DATA_DIR`
   - **Wert:** `/data` (exakt der Mount Path aus Schritt 1)

3. **Service neu starten** (Redeploy), damit der Server das Volume nutzt.

Danach speichert der Server `auftraege.json` und den Ordner `uploads/` unter `/data` – diese Daten bleiben bei weiteren Deploys erhalten. In den Logs siehst du: `Datenverzeichnis: /data (persistent)`.

**Hinweis:** Aufträge, die vor dem Einrichten des Volumes angelegt wurden, sind nach einem Redeploy leider weg. Ab jetzt gehen keine Daten mehr verloren, wenn du das Volume wie oben einrichtest.

**Prüfen, ob es funktioniert:** Nach Redeploy im Browser aufrufen: `https://deine-app.up.railway.app/api/debug`  
Dort siehst du: `dataDir` (sollte `/data` sein), `dataDirFromEnv: true`, `auftraegeFileExists`. Wenn beim Speichern etwas schiefgeht, liefert der Server Fehlermeldungen; in den Railway-Logs unter **Deployments → View Logs** erscheinen dann z. B. Schreibfehler.

## 7. Kurz-Check

- Railway-Service läuft (Logs: „Upload-Server: …“, „Datenverzeichnis: …“).
- `API_BASE` ist auf die öffentliche Railway-URL gesetzt.
- **Optional:** `DATA_DIR` und Volume gesetzt → Aufträge bleiben bei Redeploy erhalten.
- Frontend wurde mit dieser URL als `VITE_API_URL` gebaut bzw. gestartet.

Dann können alle die gleiche Auftragspool-URL nutzen, ohne lokal `npm run server` zu starten.
