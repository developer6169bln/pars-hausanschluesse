# Server auf Railway deployen

So hostest du den Auftragspool-Server bei Railway (kostenlos nutzbar). Danach brauchst du lokal keinen `npm run server` mehr – alle nutzen die gleiche URL.

> **⚠️ Ohne persistenten Speicher (Volume + DATA_DIR) gehen bei jedem Redeploy alle Aufträge und Uploads verloren.**  
> Wenn nach dem Deployment abgeschlossene oder neu angelegte Aufträge weg sind: **Volume und DATA_DIR einrichten** (siehe Abschnitt 6). Danach bleiben die Daten bei weiteren Deploys erhalten.

## 1. Bei Railway anmelden

- Gehe zu [railway.app](https://railway.app) und melde dich an (z.B. mit GitHub).

## 2. Neues Projekt aus GitHub

- **New Project** → **Deploy from GitHub repo**
- Repo auswählen: `pars-hausanschluesse` (oder dein Fork)
- **Branch:** `main` (oder den Branch, auf den du pushst)
- Railway erstellt ein neues Projekt und startet einen Build. Bei jedem **Push** auf den verbundenen Branch wird automatisch neu gebaut und deployed.

## 2b. (Neu) QGIS Server als zweiter Service

Wenn ihr **QGIS als Server** mitlaufen lassen wollt (WMS/WFS), richtet ihr im gleichen Railway Projekt einen **zweiten Service** ein:

- **New Service** → **Deploy from GitHub repo**
- **Root Directory:** `qgis-server`
- Dieser Service nutzt das Dockerfile in `qgis-server/Dockerfile` und startet `qgis/qgis-server`.

### QGIS Server Variablen (Service „QGIS“)

- `QGIS_PROJECT_FILE=/data/project.qgz`
  - Das ist euer QGIS Projekt (aus QGIS Desktop exportiert/gespeichert).

### Persistente Daten (Service „QGIS“)

Wenn ihr Projektdateien dauerhaft halten wollt:

- **Volume** hinzufügen → Mount Path: `/data`
- Dann liegt euer Projekt z. B. unter `/data/project.qgz` und bleibt bei Redeploy erhalten.

### Verbindung Admin → QGIS (Service „Admin“)

Im Admin-Service (dieser Repo-Root, `server/index.js`) setzt ihr:

- `QGIS_WMS_BASE_URL` auf die Basis-URL des QGIS Servers, z. B. `http://<qgis-service-host>/ows`

Hinweis: Der konkrete interne Hostname hängt von Railway ab (Private Networking / Service Discovery).
Wenn ihr keine interne URL nutzt, könnt ihr auch eine öffentliche Domain des QGIS-Services nehmen.

## 3. Root-Verzeichnis, Build und Start

**Hinweis:** Auf Railway läuft nur die **Admin-Web-App** (dieser Server + Frontend). Die **iOS-App (BauMeasurePro)** liegt nur als Quellcode im Repo und wird **nicht** auf Railway deployed – sie läuft auf dem iPhone über Xcode.

- In der Service-Konfiguration (Settings):
  - **Root Directory:** leer lassen (Projekt-Root)
  - **Build Command:** `npm run build` (baut das Frontend in `dist/`, **wird für die Startseite benötigt**)
  - **Start Command:** `npm run start` bzw. `node server/index.js`
  - **Watch Paths:** leer

Die Datei `railway.json` setzt **Build Command** = `npm run build` und **Start Command** = `node server/index.js`. Ohne erfolgreichen Build fehlt `dist/` und die Admin-Seite zeigt nur eine Hinweisseite. **Health Check:** `/api/health` – dort siehst du `hasDist: true/false` und ob das Frontend geliefert werden kann.

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

**Warum sind meine Aufträge nach dem Deploy weg?**  
Railway startet bei jedem Deploy einen neuen Container mit leerem Dateisystem. Ohne ein **Volume** und die Variable **DATA_DIR** schreibt der Server in dieses temporäre Dateisystem – nach dem nächsten Deploy ist alles weg (abgeschlossene und neue Aufträge, Uploads).

Damit die Daten **dauerhaft** bleiben:

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
- `dataDir` sollte `/data` sein, `dataDirFromEnv: true`.  
- Steht dort `"warning": "DATA_DIR nicht gesetzt – ..."`, ist das Volume bzw. DATA_DIR noch nicht korrekt eingerichtet – dann gehen bei jedem weiteren Deploy die Daten verloren.  
- In den Railway-Logs (**Deployments → View Logs**) steht beim Start entweder `Datenverzeichnis: /data (persistent)` oder eine Warnung, dass DATA_DIR fehlt.

## 7. Kurz-Check

- Railway-Service läuft (Logs: „Upload-Server: …“, „Datenverzeichnis: …“).
- `API_BASE` ist auf die öffentliche Railway-URL gesetzt.
- **Optional:** `DATA_DIR` und Volume gesetzt → Aufträge bleiben bei Redeploy erhalten.
- Frontend wurde mit dieser URL als `VITE_API_URL` gebaut bzw. gestartet.

Dann können alle die gleiche Auftragspool-URL nutzen, ohne lokal `npm run server` zu starten.

---

## Railway funktioniert nicht – Checkliste

1. **Öffentliche Domain / HTTPS**  
   Unter **Settings → Networking → Generate Domain** (oder **Public Networking**) eine URL erzeugen. Ohne Domain ist der Service oft nur intern erreichbar.

2. **Deploy-Logs**  
   **Deployments** → fehlgeschlagenen oder letzten Deploy → **View Logs**.  
   - **Build:** Muss `npm run build` erfolgreich durchlaufen (Ordner `dist/`).  
   - **Start:** Sollte `Upload-Server: … (bind 0.0.0.0)` erscheinen.

3. **Healthcheck**  
   Im Browser: `https://deine-app.up.railway.app/api/health`  
   - `ok: true` und idealerweise `hasDist: true`.  
   - `hasDist: false` → Build fehlt oder wurde übersprungen → Build Command prüfen.

4. **Umgebungsvariablen (nachdem die Domain feststeht)**  
   | Variable | Wert |
   |----------|------|
   | `API_BASE` | `https://deine-exakte-domain.up.railway.app` (ohne `/` am Ende) |
   | `VITE_API_URL` | **dieselbe** URL – wird beim **Build** ins Frontend geschrieben |

   Nach Änderung an `VITE_API_URL` **neu deployen** (Redeploy), damit `npm run build` die URL einbettet.

5. **Host-Bindung**  
   Der Server muss auf **`0.0.0.0`** lauschen (im Repo so umgesetzt). Nur `localhost` reicht in Containern nicht.

6. **Sleeping / Kosten**  
   Auf dem kostenlosen Plan kann der Service nach Inaktivität „einschlafen“ – erster Aufruf kann länger dauern oder einmal fehlschlagen, kurz warten und neu laden.

---

## Wenn „Push bei Railway nicht durchgeht“

- **Deploy wird nicht ausgelöst:** Im Railway-Dashboard den Service öffnen → **Settings** → **Source**. Prüfen: Ist das richtige **GitHub-Repo** verbunden und der richtige **Branch** (z. B. `main`) eingestellt? Ohne Verbindung löst ein Push kein Deploy aus.
- **Manuell neu deployen:** Im Projekt **Deployments** → **Deploy** / **Redeploy** (oder „Trigger Deploy“), damit der letzte Stand aus dem Repo neu gebaut wird.
- **Deploy schlägt fehl:** Unter **Deployments** den fehlgeschlagenen Deploy öffnen → **View Logs**. Dort siehst du Build- oder Runtime-Fehler (z. B. fehlende Abhängigkeiten, falscher Start-Befehl). Build Command = `npm run build`, Start Command = `node server/index.js`.
- **GitHub-Berechtigung:** Falls Railway das Repo nicht sieht: Bei GitHub unter **Settings → Applications → Railway** prüfen, ob Railway Zugriff auf das Repository hat.

## Wenn die Admin-Web-App auf Railway nicht lädt (weiße Seite / Fehler)

1. **Health-Check aufrufen:** `https://deine-app.up.railway.app/api/health`  
   - `ok: true`, `hasDist: true` → Server und Frontend-Build sind da; Fehler liegt ggf. im Frontend (Browser-Konsole prüfen).  
   - `hasDist: false` → Der **Build** hat kein `dist/` erzeugt. Unter **Deployments** → **View Logs** den **Build**-Abschnitt prüfen: Läuft `npm run build` durch? Wenn der Build übersprungen wird oder fehlschlägt, in den Railway **Settings** **Build Command** auf `npm run build` setzen und neu deployen.
2. **Variablen:** Unter **Variables** `VITE_API_URL` = `https://deine-app.up.railway.app` (ohne Slash). Wird beim Build eingebettet; ohne sie nutzt die App `window.location.origin` (sollte auf gleicher Domain funktionieren).
3. **Browser-Konsole:** Bei weißer Seite F12 → Konsole. Meldungen wie „Can't find variable: React“ oder Netzwerkfehler helfen bei der Ursache.
