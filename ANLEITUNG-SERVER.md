# Auftragspool einrichten – so siehst du die Aufträge

Damit die Auftragsliste geladen wird und alle Nutzer denselben Pool sehen, müssen **Server** und **Umgebungsvariable** gesetzt sein. So geht’s:

---

## 1. Ordner öffnen

Wechsle in den Projektordner der App (dort, wo `package.json` und der Ordner `server` liegen):

```bash
cd /pfad/zu/pars-hausanschluesse
```

(z.B. `cd hausanschluesse-app` oder der Name deines Projektordners)

---

## 2. Datei `.env` anlegen

Im **gleichen Ordner** wie `package.json` brauchst du eine Datei mit dem Namen **`.env`** (mit Punkt am Anfang).

**Option A – per Editor:**  
Neue Datei anlegen, Namen **`.env`** geben und folgenden Inhalt eintragen:

```
VITE_API_URL=http://localhost:3010
```

Dann speichern. Die Datei liegt dann z.B. hier:  
`pars-hausanschluesse/.env`

**Option B – per Terminal (im Projektordner):**

```bash
echo "VITE_API_URL=http://localhost:3010" > .env
```

Wichtig: Kein Leerzeichen um das `=`, und **keine Anführungszeichen** um die URL (oder genau so wie oben).

---

## 3. Server starten (Terminal 1)

Im Projektordner:

```bash
npm run server
```

Du solltest etwas sehen wie:  
`Upload-Server: http://localhost:3010 (Port 3010)`  
Das Fenster **offen lassen** – der Server muss laufen, sonst kommen keine Aufträge.

---

## 4. App starten (Terminal 2)

Ein **zweites** Terminal/Fenster öffnen, wieder in den **gleichen Projektordner** wechseln, dann:

```bash
npm run dev
```

Es erscheint eine Adresse, z.B.  
`http://localhost:5180` oder `http://localhost:5181`.

---

## 5. Im Browser öffnen

Diese Adresse (z.B. `http://localhost:5180`) im Browser öffnen.

- Wenn alles stimmt: Der gelbe/blaue Hinweis **„Auftragspool: Server starten …“** **verschwindet** und du siehst die Auftragsliste (oder „Noch keine Aufträge erfasst“, wenn der Pool noch leer ist).
- Wenn der Hinweis **noch da** ist:  
  - Prüfen, ob die Datei wirklich **`.env`** heißt und im **Projektordner** (neben `package.json`) liegt.  
  - **App neu starten** (im Terminal 2 `Strg+C`, dann wieder `npm run dev`), damit Vite die `.env` neu einliest.

---

## Kurz-Checkliste

| Schritt | Befehl / Aktion |
|--------|------------------|
| 1 | Im Projektordner sein (dort wo `package.json` ist) |
| 2 | Datei `.env` anlegen mit Inhalt: `VITE_API_URL=http://localhost:3010` |
| 3 | Terminal 1: `npm run server` (laufen lassen) |
| 4 | Terminal 2: `npm run dev` |
| 5 | Im Browser die angezeigte Adresse (z.B. http://localhost:5180) öffnen |

Wenn du das so machst, sollte der Auftragspool Aufträge anzeigen (sobald welche angelegt wurden) und der Hinweis weg sein.
