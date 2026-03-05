# Server auf Railway deployen

So hostest du den Auftragspool-Server bei Railway (kostenlos nutzbar). Danach brauchst du lokal keinen `npm run server` mehr – alle nutzen die gleiche URL.

## 1. Bei Railway anmelden

- Gehe zu [railway.app](https://railway.app) und melde dich an (z.B. mit GitHub).

## 2. Neues Projekt aus GitHub

- **New Project** → **Deploy from GitHub repo**
- Repo auswählen: `pars-hausanschluesse` (oder dein Fork)
- Railway erstellt ein neues Projekt und startet einen Build.

## 3. Root-Verzeichnis und Start-Befehl

- In der Service-Konfiguration (Settings):
  - **Root Directory:** leer lassen (Projekt-Root)
  - **Build Command:** leer oder `npm install`
  - **Start Command:** `npm run start` (startet den Server)
  - **Watch Paths:** leer

Railway nutzt automatisch die Variable **PORT** – der Server verwendet sie bereits.

## 4. Umgebungsvariable für die öffentliche URL

Damit Upload-Links stimmen, muss der Server seine eigene URL kennen:

- Im Railway-Dashboard: deinen Service öffnen → **Variables**
- Variable anlegen:
  - **Name:** `API_BASE`
  - **Wert:** die öffentliche URL deines Services (z.B. `https://pars-hausanschluesse-production-xxxx.up.railway.app`)

Die URL findest du unter **Settings** → **Networking** → **Generate Domain** (oder bei **Public Networking**).

Nach dem ersten Deploy steht dort etwas wie:
`https://<name>.up.railway.app`  
Genau diese URL (ohne Slash am Ende) als `API_BASE` eintragen.

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

## 6. Kurz-Check

- Railway-Service läuft (Logs: „Upload-Server: …“).
- `API_BASE` ist auf die öffentliche Railway-URL gesetzt.
- Frontend wurde mit dieser URL als `VITE_API_URL` gebaut bzw. gestartet.

Dann können alle die gleiche Auftragspool-URL nutzen, ohne lokal `npm run server` zu starten.
