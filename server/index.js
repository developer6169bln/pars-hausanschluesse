import express from 'express'
import multer from 'multer'
import path from 'path'
import fs from 'fs'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const PORT = process.env.PORT || 3010
const API_BASE = process.env.API_BASE || `http://localhost:${PORT}`

// Persistente Daten: Wenn DATA_DIR gesetzt (z. B. Railway-Volume unter /data), speichern wir dort.
// So gehen Aufträge und Uploads bei Redeploy nicht verloren.
const DATA_DIR = process.env.DATA_DIR ? path.resolve(process.env.DATA_DIR) : __dirname
const UPLOAD_DIR = path.join(DATA_DIR, 'uploads')
const AUFTRAEGE_FILE = path.join(DATA_DIR, 'auftraege.json')

// DATA_DIR und Upload-Ordner anlegen (wichtig für Volume: muss existieren)
try {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true })
    console.log('DATA_DIR erstellt:', DATA_DIR)
  }
  if (!fs.existsSync(UPLOAD_DIR)) {
    fs.mkdirSync(UPLOAD_DIR, { recursive: true })
    console.log('UPLOAD_DIR erstellt:', UPLOAD_DIR)
  }
} catch (err) {
  console.error('Fehler beim Anlegen der Verzeichnisse:', err.message)
}

const dataDirIsVolume = Boolean(process.env.DATA_DIR)
console.log('Datenverzeichnis:', DATA_DIR, dataDirIsVolume ? '(persistent, DATA_DIR gesetzt)' : '(lokal)')
console.log('Aufträge-Datei:', AUFTRAEGE_FILE)

function readAuftraege() {
  try {
    const raw = fs.readFileSync(AUFTRAEGE_FILE, 'utf8')
    return JSON.parse(raw)
  } catch (err) {
    if (err.code !== 'ENOENT') console.error('Lesefehler auftraege.json:', err.message)
    return []
  }
}

function writeAuftraege(list) {
  try {
    fs.writeFileSync(AUFTRAEGE_FILE, JSON.stringify(list), 'utf8')
  } catch (err) {
    console.error('Schreibfehler auftraege.json:', err.message, 'Pfad:', AUFTRAEGE_FILE)
    throw err
  }
}

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
  filename: (_req, file, cb) => {
    const safeName = (file.originalname || 'file').replace(/[^a-zA-Z0-9.-]/g, '_')
    const unique = `${Date.now()}-${Math.random().toString(36).slice(2, 9)}-${safeName}`
    cb(null, unique)
  },
})
const upload = multer({ storage, limits: { fileSize: 25 * 1024 * 1024 } }) // 25 MB

const app = express()
app.use(express.json({ limit: '2mb' }))

app.use((_req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type')
  next()
})

app.use('/uploads', express.static(UPLOAD_DIR))

app.get('/api/auftraege', (_req, res) => {
  res.json(readAuftraege())
})

// Debug: prüfen, ob DATA_DIR/Volume genutzt wird und Datei existiert (z. B. /api/debug aufrufen)
app.get('/api/debug', (_req, res) => {
  const list = readAuftraege()
  res.json({
    dataDir: DATA_DIR,
    auftraegeFile: AUFTRAEGE_FILE,
    auftraegeFileExists: fs.existsSync(AUFTRAEGE_FILE),
    uploadDirExists: fs.existsSync(UPLOAD_DIR),
    dataDirFromEnv: Boolean(process.env.DATA_DIR),
    count: Array.isArray(list) ? list.length : 0,
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
  res.json({ url, name: req.file.originalname, size: req.file.size })
})

// Frontend (Vite-Build) ausliefern, damit Railway die App unter / anzeigt
const DIST = path.join(__dirname, '..', 'dist')
if (fs.existsSync(DIST)) {
  app.use(express.static(DIST))
  app.get('*', (_req, res) => {
    res.sendFile(path.join(DIST, 'index.html'))
  })
}

app.listen(PORT, () => {
  console.log(`Upload-Server: ${API_BASE} (Port ${PORT})`)
})
