import express from 'express'
import multer from 'multer'
import path from 'path'
import fs from 'fs'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const PORT = process.env.PORT || 3010
const API_BASE = process.env.API_BASE || `http://localhost:${PORT}`

// QGIS Server (WMS/WFS) Anbindung via Proxy (vermeidet CORS + verhindert Open-Proxy)
// Beispiel: QGIS_WMS_BASE_URL="https://gis.example.com/ows"
const QGIS_WMS_BASE_URL = (process.env.QGIS_WMS_BASE_URL || '').trim()

// Persistente Daten: Wenn DATA_DIR gesetzt (z. B. Railway-Volume unter /data), speichern wir dort.
// So gehen Aufträge und Uploads bei Redeploy nicht verloren.
const DATA_DIR = process.env.DATA_DIR ? path.resolve(process.env.DATA_DIR) : __dirname
const UPLOAD_DIR = path.join(DATA_DIR, 'uploads')
const BACKUPS_DIR = path.join(DATA_DIR, 'backups')
const AUFTRAEGE_FILE = path.join(DATA_DIR, 'auftraege.json')
const USERS_FILE = path.join(DATA_DIR, 'users.json')
const PROJECTS_FILE = path.join(DATA_DIR, 'projects.json')
const BACKUP_LATEST = path.join(DATA_DIR, 'auftraege-backup-latest.json')
const MAX_BACKUP_FILES = 30 // Anzahl zeitgestempelter Backups (älteste werden gelöscht)

// DATA_DIR, Upload- und Backup-Ordner anlegen (wichtig für Volume: muss existieren)
try {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true })
    console.log('DATA_DIR erstellt:', DATA_DIR)
  }
  if (!fs.existsSync(UPLOAD_DIR)) {
    fs.mkdirSync(UPLOAD_DIR, { recursive: true })
    console.log('UPLOAD_DIR erstellt:', UPLOAD_DIR)
  }
  if (!fs.existsSync(BACKUPS_DIR)) {
    fs.mkdirSync(BACKUPS_DIR, { recursive: true })
    console.log('Backup-Ordner erstellt:', BACKUPS_DIR)
  }
} catch (err) {
  console.error('Fehler beim Anlegen der Verzeichnisse:', err.message)
}

const dataDirIsVolume = Boolean(process.env.DATA_DIR)
console.log('Datenverzeichnis:', DATA_DIR, dataDirIsVolume ? '(persistent, DATA_DIR gesetzt)' : '(lokal)')
console.log('Aufträge-Datei:', AUFTRAEGE_FILE)
if (!dataDirIsVolume && process.env.PORT) {
  console.warn('⚠️ DATA_DIR ist nicht gesetzt – bei jedem Redeploy gehen alle Aufträge und Uploads verloren!')
  console.warn('   Lösung: Railway Volume unter /data mounten und Umgebungsvariable DATA_DIR=/data setzen.')
}

function readAuftraege() {
  try {
    const raw = fs.readFileSync(AUFTRAEGE_FILE, 'utf8')
    return JSON.parse(raw)
  } catch (err) {
    if (err.code !== 'ENOENT') console.error('Lesefehler auftraege.json:', err.message)
    return []
  }
}

/** Nach jeder Änderung Sicherung anlegen, damit keine Auftragsdaten verloren gehen. */
function createBackups(list) {
  const json = JSON.stringify(list)
  try {
    fs.writeFileSync(BACKUP_LATEST, json, 'utf8')
  } catch (err) {
    console.error('Backup (latest) fehlgeschlagen:', err.message)
  }
  try {
    const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
    const name = `auftraege-${ts}.json`
    const file = path.join(BACKUPS_DIR, name)
    fs.writeFileSync(file, json, 'utf8')
    const files = fs.readdirSync(BACKUPS_DIR).filter((f) => f.startsWith('auftraege-') && f.endsWith('.json'))
    files.sort()
    while (files.length > MAX_BACKUP_FILES) {
      const oldest = files.shift()
      try {
        fs.unlinkSync(path.join(BACKUPS_DIR, oldest))
      } catch (_) {}
    }
  } catch (err) {
    console.error('Backup (zeitgestempelt) fehlgeschlagen:', err.message)
  }
}

function writeAuftraege(list) {
  try {
    fs.writeFileSync(AUFTRAEGE_FILE, JSON.stringify(list), 'utf8')
    createBackups(list)
  } catch (err) {
    console.error('Schreibfehler auftraege.json:', err.message, 'Pfad:', AUFTRAEGE_FILE)
    throw err
  }
}

// --- Users (Monteure / App-Nutzer) ---
function readUsers() {
  try {
    const raw = fs.readFileSync(USERS_FILE, 'utf8')
    const data = JSON.parse(raw)
    return Array.isArray(data) ? data : []
  } catch (err) {
    if (err.code !== 'ENOENT') console.error('Lesefehler users.json:', err.message)
    return []
  }
}

function writeUsers(list) {
  const arr = Array.isArray(list) ? list : []
  fs.writeFileSync(USERS_FILE, JSON.stringify(arr, null, 2), 'utf8')
}

// --- Projects (für Zuweisung an Monteure; kompatibel mit BauMeasurePro-App) ---
function readProjects() {
  try {
    const raw = fs.readFileSync(PROJECTS_FILE, 'utf8')
    const data = JSON.parse(raw)
    return Array.isArray(data) ? data : []
  } catch (err) {
    if (err.code !== 'ENOENT') console.error('Lesefehler projects.json:', err.message)
    return []
  }
}

function writeProjects(list) {
  const arr = Array.isArray(list) ? list : []
  fs.writeFileSync(PROJECTS_FILE, JSON.stringify(arr, null, 2), 'utf8')
}

const PROJECTS_UPLOAD_DIR = path.join(DATA_DIR, 'uploads', 'projects')

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
  filename: (_req, file, cb) => {
    const safeName = (file.originalname || 'file').replace(/[^a-zA-Z0-9.-]/g, '_')
    const unique = `${Date.now()}-${Math.random().toString(36).slice(2, 9)}-${safeName}`
    cb(null, unique)
  },
})
const upload = multer({ storage, limits: { fileSize: 25 * 1024 * 1024 } }) // 25 MB

const projectUploadStorage = multer.diskStorage({
  destination: (req, _file, cb) => {
    const id = req.params.id || 'unknown'
    const dir = path.join(PROJECTS_UPLOAD_DIR, String(id))
    try {
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true })
      cb(null, dir)
    } catch (err) {
      cb(err, null)
    }
  },
  filename: (_req, file, cb) => {
    const safeName = (file.originalname || 'file').replace(/[^a-zA-Z0-9.-]/g, '_')
    const unique = `${Date.now()}-${Math.random().toString(36).slice(2, 9)}-${safeName}`
    cb(null, unique)
  },
})
const projectUpload = multer({ storage: projectUploadStorage, limits: { fileSize: 50 * 1024 * 1024 } }) // 50 MB für 3D

const app = express()
// Größeres Limit, damit Aufträge mit vielen Fotos (base64-Fallback) gespeichert werden können
app.use(express.json({ limit: '50mb' }))

app.use((_req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type')
  next()
})

// CORS-Preflight (z. B. für Upload vom Frontend auf anderem Port)
app.options('*', (_req, res) => res.sendStatus(204))

app.use('/uploads', express.static(UPLOAD_DIR))

// ========== GIS: QGIS Server Proxy (WMS) ==========
// Nutzung im Frontend: `${API_BASE}/api/qgis/wms?SERVICE=WMS&REQUEST=GetMap&...`
app.get('/api/qgis/wms', async (req, res) => {
  if (!QGIS_WMS_BASE_URL) {
    return res.status(503).json({
      error: 'QGIS_WMS_BASE_URL fehlt',
      message: 'Server-ENV QGIS_WMS_BASE_URL setzen (z. B. https://…/ows).',
    })
  }

  let targetUrl
  try {
    const base = new URL(QGIS_WMS_BASE_URL)
    // Query-Parameter 1:1 übernehmen (GetMap, GetCapabilities, GetFeatureInfo, ...)
    for (const [k, v] of Object.entries(req.query || {})) {
      if (v == null) continue
      if (Array.isArray(v)) {
        v.forEach((vv) => base.searchParams.append(k, String(vv)))
      } else {
        base.searchParams.set(k, String(v))
      }
    }
    targetUrl = base.toString()
  } catch (err) {
    return res.status(500).json({ error: 'Ungültige QGIS_WMS_BASE_URL', details: err.message })
  }

  const ac = new AbortController()
  const t = setTimeout(() => ac.abort(), 15000)
  try {
    const upstream = await fetch(targetUrl, {
      method: 'GET',
      signal: ac.signal,
      headers: {
        // QGIS Server braucht i. d. R. keine Auth; falls doch, sollte das per Reverse Proxy geregelt werden.
        'User-Agent': 'hausanschluesse-admin/1.0',
      },
    })

    res.status(upstream.status)
    const ct = upstream.headers.get('content-type')
    if (ct) res.setHeader('Content-Type', ct)
    const cc = upstream.headers.get('cache-control')
    if (cc) res.setHeader('Cache-Control', cc)

    const buf = Buffer.from(await upstream.arrayBuffer())
    return res.send(buf)
  } catch (err) {
    const msg = err?.name === 'AbortError' ? 'Timeout beim QGIS Server' : (err?.message || String(err))
    return res.status(502).json({ error: 'QGIS Proxy Fehler', message: msg })
  } finally {
    clearTimeout(t)
  }
})

// Projekt-Assets (von App hochgeladen): Bilder, 3D-Scans
app.get('/api/uploads/projects/:id/:filename', (req, res) => {
  const { id, filename } = req.params
  if (!id || !filename || filename.includes('..')) return res.status(400).send('Invalid path')
  const filePath = path.join(PROJECTS_UPLOAD_DIR, id, filename)
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) return res.status(404).send('Not found')
  res.sendFile(path.resolve(filePath))
})

app.post('/api/projects/:id/upload', projectUpload.single('file'), (req, res) => {
  const id = req.params.id
  if (!req.file) return res.status(400).json({ error: 'Keine Datei' })
  const url = `${API_BASE}/api/uploads/projects/${id}/${req.file.filename}`
  res.status(201).json({ url, filename: req.file.filename })
})

app.get('/api/auftraege', (_req, res) => {
  res.json(readAuftraege())
})

// Debug: prüfen, ob DATA_DIR/Volume genutzt wird und Datei existiert (z. B. /api/debug aufrufen)
app.get('/api/debug', (_req, res) => {
  const list = readAuftraege()
  const dataDirFromEnv = Boolean(process.env.DATA_DIR)
  let uploadFileCount = 0
  let backupCount = 0
  try {
    if (fs.existsSync(UPLOAD_DIR)) uploadFileCount = fs.readdirSync(UPLOAD_DIR).length
    if (fs.existsSync(BACKUPS_DIR)) {
      backupCount = fs.readdirSync(BACKUPS_DIR).filter((f) => f.startsWith('auftraege-') && f.endsWith('.json')).length
    }
  } catch (_) {}
  res.json({
    dataDir: DATA_DIR,
    auftraegeFile: AUFTRAEGE_FILE,
    auftraegeFileExists: fs.existsSync(AUFTRAEGE_FILE),
    uploadDirExists: fs.existsSync(UPLOAD_DIR),
    uploadFileCount,
    backupLatestExists: fs.existsSync(BACKUP_LATEST),
    backupCount,
    dataDirFromEnv,
    count: Array.isArray(list) ? list.length : 0,
    warning: !dataDirFromEnv && process.env.PORT
      ? 'DATA_DIR nicht gesetzt – Daten gehen bei Redeploy verloren. Volume + DATA_DIR=/data einrichten.'
      : null,
  })
})

app.post('/api/auftraege', (req, res) => {
  const list = Array.isArray(req.body) ? req.body : []
  try {
    writeAuftraege(list)
    res.json(list)
  } catch (err) {
    console.error('POST /api/auftraege Fehler:', err.message)
    res.status(500).json({ error: 'Speichern fehlgeschlagen', details: err.message })
  }
})

app.put('/api/auftraege', (req, res) => {
  const list = Array.isArray(req.body) ? req.body : []
  try {
    writeAuftraege(list)
    res.json(list)
  } catch (err) {
    console.error('PUT /api/auftraege Fehler:', err.message)
    res.status(500).json({ error: 'Speichern fehlgeschlagen', details: err.message })
  }
})

app.post('/api/upload', upload.single('file'), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'Keine Datei' })
  }
  const url = `${API_BASE}/uploads/${req.file.filename}`
  res.json({ url, name: req.file.originalname, size: req.file.size, type: req.file.mimetype || 'image/jpeg' })
})

app.delete('/api/upload/:filename', (req, res) => {
  const raw = req.params.filename || ''
  let filename = raw
  try {
    filename = decodeURIComponent(raw)
  } catch (_) {}

  // Sicherheit: nur einfache Dateinamen (kein ../, keine Slashes)
  if (!filename || filename.includes('/') || filename.includes('\\') || filename.includes('..')) {
    return res.status(400).json({ error: 'Ungültiger Dateiname' })
  }
  // Optional: nur unsere generierten Namen zulassen
  if (!/^[a-zA-Z0-9._-]+$/.test(filename)) {
    return res.status(400).json({ error: 'Ungültiger Dateiname' })
  }

  const filePath = path.join(UPLOAD_DIR, filename)
  if (!filePath.startsWith(UPLOAD_DIR)) {
    return res.status(400).json({ error: 'Ungültiger Pfad' })
  }

  fs.unlink(filePath, (err) => {
    if (err) {
      if (err.code === 'ENOENT') return res.status(404).json({ error: 'Datei nicht gefunden' })
      console.error('DELETE /api/upload Fehler:', err.message)
      return res.status(500).json({ error: 'Löschen fehlgeschlagen' })
    }
    res.json({ ok: true })
  })
})

// ========== Admin: Users (Monteure) ==========
app.get('/api/users', (_req, res) => {
  res.json(readUsers())
})

app.post('/api/users', (req, res) => {
  const users = readUsers()
  const body = req.body || {}
  const id = body.id || `user-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`
  const name = String(body.name || '').trim() || 'Monteur'
  const deviceId = String(body.deviceId || '').trim() || id
  const newUser = { id, name, deviceId }
  users.push(newUser)
  writeUsers(users)
  res.status(201).json(newUser)
})

app.put('/api/users', (req, res) => {
  const list = Array.isArray(req.body) ? req.body : []
  writeUsers(list)
  res.json(list)
})

// ========== Admin: Projects (Zuweisung an Monteure) ==========
app.get('/api/projects', (_req, res) => {
  res.json(readProjects())
})

app.post('/api/projects', (req, res) => {
  const projects = readProjects()
  const body = req.body || {}
  const id = body.id || `proj-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`
  const project = {
    id,
    name: String(body.name || '').trim() || 'Neues Projekt',
    createdAt: body.createdAt || new Date().toISOString(),
    measurements: Array.isArray(body.measurements) ? body.measurements : [],
    assignedToUserId: body.assignedToUserId || null,
    strasse: body.strasse ?? null,
    hausnummer: body.hausnummer ?? null,
    postleitzahl: body.postleitzahl ?? null,
    ort: body.ort ?? null,
    nvtNummer: body.nvtNummer ?? null,
    kolonne: body.kolonne ?? null,
    verbundGroesse: body.verbundGroesse ?? null,
    verbundFarbe: body.verbundFarbe ?? null,
    pipesFarbe: body.pipesFarbe ?? null,
    pipesFarbe1: body.pipesFarbe1 ?? null,
    pipesFarbe2: body.pipesFarbe2 ?? null,
    auftragAbgeschlossen: body.auftragAbgeschlossen ?? null,
    termin: body.termin ?? null,
    googleDriveLink: body.googleDriveLink ?? null,
    notizen: body.notizen ?? null,
    kundeName: body.kundeName ?? null,
    kundeTelefon: body.kundeTelefon ?? null,
    kundeEmail: body.kundeEmail ?? null,
    threeDScans: Array.isArray(body.threeDScans) ? body.threeDScans : [],
    telefonNotizen: body.telefonNotizen ?? null,
    kundenBeschwerden: body.kundenBeschwerden ?? null,
    kundenBeschwerdenUnterschriebenAm: body.kundenBeschwerdenUnterschriebenAm ?? null,
    auftragBestaetigtText: body.auftragBestaetigtText ?? null,
    auftragBestaetigtUnterschriebenAm: body.auftragBestaetigtUnterschriebenAm ?? null,
    abnahmeProtokollUnterschriftPath: body.abnahmeProtokollUnterschriftPath ?? null,
    abnahmeProtokollDatum: body.abnahmeProtokollDatum ?? null,
    abnahmeOhneMaengel: body.abnahmeOhneMaengel ?? null,
    abnahmeMaengelText: body.abnahmeMaengelText ?? null,
    bauhinderung: body.bauhinderung ?? null,
    mapImagePath: body.mapImagePath ?? null,
  }
  projects.push(project)
  writeProjects(projects)
  res.status(201).json(project)
})

app.put('/api/projects', (req, res) => {
  const list = Array.isArray(req.body) ? req.body : []
  writeProjects(list)
  res.json(list)
})

app.patch('/api/projects/:id', (req, res) => {
  const projects = readProjects()
  const id = req.params.id
  const idx = projects.findIndex((p) => String(p.id) === String(id))
  if (idx === -1) return res.status(404).json({ error: 'Projekt nicht gefunden' })
  const patch = req.body || {}
  const updated = { ...projects[idx], ...patch }
  if (Array.isArray(patch.measurements)) {
    updated.measurements = patch.measurements
  }
  projects[idx] = updated
  writeProjects(projects)
  res.json(projects[idx])
})

// Admin: Projekt löschen (nur in der Admin-Web-App, nicht in der BauMeasurePro-App)
app.delete('/api/projects/:id', (req, res) => {
  const projects = readProjects()
  const id = req.params.id
  const idx = projects.findIndex((p) => String(p.id) === String(id))
  if (idx === -1) return res.status(404).json({ error: 'Projekt nicht gefunden' })
  projects.splice(idx, 1)
  writeProjects(projects)
  res.status(204).send()
})

// ========== Mobile App: zugewiesene Projekte abrufen ==========
// deviceId = Geräte-ID, die der Monteur in der App eingibt (oder die App automatisch sendet)
app.get('/api/mobile/assigned-projects', (req, res) => {
  const deviceId = (req.query.deviceId || req.query.device_id || '').toString().trim()
  if (!deviceId) {
    return res.status(400).json({ error: 'deviceId fehlt', message: 'Query-Parameter deviceId ist erforderlich.' })
  }
  const users = readUsers()
  const user = users.find((u) => String(u.deviceId).trim() === deviceId)
  if (!user) {
    return res.json([])
  }
  const projects = readProjects()
  const assigned = projects.filter((p) => p.assignedToUserId != null && String(p.assignedToUserId) === String(user.id))
  res.json(assigned)
})

// Health-Check für Railway / Debug (vor static, damit es immer erreichbar ist)
const DIST = path.join(__dirname, '..', 'dist')
app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    hasDist: fs.existsSync(DIST),
    dataDir: DATA_DIR,
    message: fs.existsSync(DIST) ? 'Admin-Web-App bereit' : 'Frontend fehlt: Build Command (npm run build) auf Railway prüfen',
  })
})

// Frontend (Vite-Build) ausliefern, damit Railway die App unter / anzeigt
if (fs.existsSync(DIST)) {
  app.use(express.static(DIST))
  app.get('*', (_req, res) => {
    const indexPath = path.join(DIST, 'index.html')
    res.sendFile(indexPath, (err) => {
      if (err && !res.headersSent) res.status(500).json({ error: 'Frontend nicht gefunden' })
    })
  })
} else {
  app.get('/', (_req, res) => {
    res.type('html').send(`
      <!DOCTYPE html>
      <html><head><meta charset="utf-8"><title>Admin – Setup</title></head>
      <body style="font-family:system-ui;max-width:520px;margin:2rem auto;padding:1rem;">
        <h1>Admin-Web-App</h1>
        <p>Das Frontend wurde noch nicht gebaut. Im Projektordner ausführen:</p>
        <pre style="background:#f1f5f9;padding:1rem;border-radius:8px;">npm run build\nnpm run server</pre>
        <p>Dann diese Seite neu laden. API ist unter <a href="/api/projects">/api/projects</a> erreichbar.</p>
      </body></html>
    `)
  })
}

// 0.0.0.0: In Docker/Railway muss der Prozess auf allen Interfaces lauschen – sonst Healthcheck & öffentliche URL greifen nicht.
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Upload-Server: ${API_BASE} (Port ${PORT}, bind 0.0.0.0)`)
})
