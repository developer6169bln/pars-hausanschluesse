import { Routes, Route, Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { useState, useEffect, useRef, createContext, useContext } from 'react'

const AuftraegeContext = createContext(null)

const STORAGE_AUFTRAEGE = 'haus-auftraege'
const MAX_IMAGE_WIDTH = 800
const JPEG_QUALITY = 0.75

// API-URL:
// - Lokal: über VITE_API_URL (z.B. http://localhost:3010)
// - Produktion (Railway, gleiche Domain für Frontend+API): Fallback auf window.location.origin,
//   damit der Auftragspool auch ohne gesetztes VITE_API_URL funktioniert.
const API_BASE = (
  import.meta.env.VITE_API_URL ||
  ((import.meta.env.PROD && typeof window !== 'undefined' && window.location?.origin) ? window.location.origin : '') ||
  ''
).replace(/\/$/, '')

function getAttachmentSrc(item) {
  return item?.url || item?.dataUrl || ''
}

function getUploadFilenameFromUrl(url) {
  try {
    const u = new URL(url, window.location.origin)
    const parts = (u.pathname || '').split('/').filter(Boolean)
    const filename = parts[parts.length - 1] || ''
    return filename
  } catch {
    const s = String(url || '')
    const parts = s.split('?')[0].split('/').filter(Boolean)
    return parts[parts.length - 1] || ''
  }
}

async function deleteUploadOnServer(attachment) {
  if (!API_BASE) return { ok: false, skipped: true }
  const url = attachment?.url
  if (!url || typeof url !== 'string') return { ok: false, skipped: true }
  const filename = getUploadFilenameFromUrl(url)
  if (!filename) return { ok: false, skipped: true }
  const res = await fetch(`${API_BASE}/api/upload/${encodeURIComponent(filename)}`, { method: 'DELETE' })
  if (res.ok) return { ok: true }
  if (res.status === 404) return { ok: true, notFound: true }
  const msg = await res.text().catch(() => '')
  return { ok: false, status: res.status, message: msg }
}

async function uploadOneToServer(file) {
  const formData = new FormData()
  formData.append('file', file)
  const res = await fetch(`${API_BASE}/api/upload`, { method: 'POST', body: formData })
  if (!res.ok) throw new Error(await res.text().catch(() => 'Upload fehlgeschlagen'))
  const data = await res.json()
  return { name: data.name || file.name, url: data.url, size: data.size ?? file.size, type: file.type }
}

function formatAccuracyHint(accuracy) {
  const a = Number(accuracy)
  if (!Number.isFinite(a) || a <= 0) return ''
  return `GPS Genauigkeit: ±${Math.round(a)} m`
}

async function reverseGeocodeNominatim(lat, lon) {
  const url = `https://nominatim.openstreetmap.org/reverse?lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lon)}&format=json`
  const res = await fetch(url, { headers: { Accept: 'application/json' } })
  if (!res.ok) throw new Error('Reverse-Geocoding fehlgeschlagen')
  const data = await res.json()
  const a = data?.address || {}
  const street = a.road || a.pedestrian || a.footway || a.cycleway || a.path || ''
  const house = a.house_number || ''
  return { street, house, raw: data }
}

function drawOverlay(ctx, canvasW, canvasH, { street, house, nvt, tsLabel }) {
  const addressLine = [street, house].filter(Boolean).join(' ').trim()
  const nvtLine = (nvt || '').toString().trim() ? `NVT: ${(nvt || '').toString().trim()}` : ''
  const lines = [addressLine || 'Adresse: —', nvtLine, tsLabel || ''].filter(Boolean)
  const pad = Math.max(12, Math.round(canvasW * 0.02))
  const fontSize = Math.max(18, Math.round(canvasW * 0.03))
  const lineHeight = Math.round(fontSize * 1.25)
  const boxH = pad * 2 + lineHeight * (lines.filter(Boolean).length || 1)
  const y0 = canvasH - boxH - pad

  ctx.save()
  ctx.fillStyle = 'rgba(0,0,0,0.6)'
  ctx.fillRect(pad, y0, canvasW - pad * 2, boxH)
  ctx.fillStyle = '#fff'
  ctx.font = `${fontSize}px system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif`
  ctx.textBaseline = 'top'

  let y = y0 + pad
  for (const line of lines) {
    if (!line) continue
    ctx.fillText(line, pad * 1.5, y)
    y += lineHeight
  }
  ctx.restore()
}

async function fileToCanvas(canvas, file, { maxWidth = 1600 } = {}) {
  const url = URL.createObjectURL(file)
  try {
    const img = await new Promise((resolve, reject) => {
      const i = new Image()
      i.onload = () => resolve(i)
      i.onerror = reject
      i.src = url
    })
    let w = img.naturalWidth || img.width
    let h = img.naturalHeight || img.height
    if (maxWidth && w > maxWidth) {
      h = Math.round((h * maxWidth) / w)
      w = maxWidth
    }
    canvas.width = w
    canvas.height = h
    const ctx = canvas.getContext('2d')
    if (!ctx) throw new Error('Canvas nicht verfügbar')
    ctx.drawImage(img, 0, 0, w, h)
    return { width: w, height: h }
  } finally {
    URL.revokeObjectURL(url)
  }
}

async function canvasToJpegFile(canvas, fileNameBase = 'foto', quality = 0.9) {
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality))
  if (!blob) throw new Error('Bild konnte nicht erzeugt werden')
  const safeBase = (fileNameBase || 'foto').replace(/[^a-zA-Z0-9._-]/g, '_')
  const name = `${safeBase}-${Date.now()}.jpg`
  return new File([blob], name, { type: 'image/jpeg' })
}

async function fileToAttachmentWithMeta(file, meta) {
  if (API_BASE) {
    try {
      const att = await uploadOneToServer(file)
      return { attachment: { ...att, meta }, fallbackUsed: false }
    } catch (e) {
      console.warn('Server-Upload fehlgeschlagen, Fallback auf lokale Speicherung', e)
    }
  }
  const att = await readOneAsDataUrl(file)
  return { attachment: { ...att, meta }, fallbackUsed: true }
}

function compressDataUrl(dataUrl) {
  return new Promise((resolve) => {
    if (!dataUrl || !dataUrl.startsWith('data:image')) {
      resolve(dataUrl)
      return
    }
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.onload = () => {
      const canvas = document.createElement('canvas')
      let { width, height } = img
      if (width > MAX_IMAGE_WIDTH) {
        height = (height * MAX_IMAGE_WIDTH) / width
        width = MAX_IMAGE_WIDTH
      }
      canvas.width = width
      canvas.height = height
      const ctx = canvas.getContext('2d')
      if (!ctx) {
        resolve(dataUrl)
        return
      }
      ctx.drawImage(img, 0, 0, width, height)
      try {
        const compressed = canvas.toDataURL('image/jpeg', JPEG_QUALITY)
        resolve(compressed)
      } catch {
        resolve(dataUrl)
      }
    }
    img.onerror = () => resolve(dataUrl)
    img.src = dataUrl
  })
}

const readOneAsDataUrl = async (file) => {
  const dataUrl = await new Promise((resolve) => {
    const reader = new FileReader()
    reader.onload = () => resolve(typeof reader.result === 'string' ? reader.result : '')
    reader.onerror = () => resolve('')
    reader.readAsDataURL(file)
  })
  const compressed = await compressDataUrl(dataUrl)
  return {
    name: file.name,
    type: file.type,
    size: file.size,
    lastModified: file.lastModified,
    dataUrl: compressed,
  }
}

/** Nimmt File-Liste (oder Array), lädt auf Server hoch oder speichert als Data-URL.
 *  Gibt { attachments, fallbackUsed } zurück. fallbackUsed = true, wenn Server-Upload fehlgeschlagen. */
const filesToAttachments = async (files) => {
  const list = Array.from(files || [])
  if (!list.length) return { attachments: [], fallbackUsed: false }
  try {
    if (API_BASE) {
      try {
        const attachments = await Promise.all(list.map((file) => uploadOneToServer(file)))
        return { attachments, fallbackUsed: false }
      } catch (e) {
        console.warn('Server-Upload fehlgeschlagen, Fallback auf lokale Speicherung', e)
      }
    }
    const attachments = await Promise.all(list.map(readOneAsDataUrl))
    return { attachments, fallbackUsed: true }
  } catch (e) {
    console.error('Fotos konnten nicht verarbeitet werden:', e)
    return { attachments: [], fallbackUsed: false }
  }
}

const defaultAuftrag = {
  bezeichnung: '',
  kunde: '',
  adresse: '',
  plz: '',
  ort: '',
  netzbetreiber: '',
  status: 'eingang',
  // Stammdaten / Kontakt
  termin: '', // datetime-local string: YYYY-MM-DDTHH:mm
  verbundGroesse: '', // 22x7 | 8x7 | 12x7
  verbundFarbe: '', // Orange | Orange/Schwarz | Orange/Weiß | Orange/Rot
  pipesFarbe1: '', // Farbnamen
  pipesFarbe2: '',
  strasse: '',
  hausnummer: '',
  kontaktName: '',
  telefon: '',
  nvt: '',
  nvtStandort: '',
  standort: null, // { lat, lng, accuracy, timestamp }
  ortsanwesenheit: null, // { lat, lng, accuracy?, timestamp } – Standort + Uhrzeit per Klick
  geoAceMessung: 'nein',
  geprueft: 'nein',
  messungGraben: '',
  messungSonstiges: '',
  notizen: '',
  abgeschlossen: false,
  inklusivMeter010: false, // Checkbox: Inklusiv Meter (0-10m)
  // Technische Metadaten aus Import (alle Spalten der Tabelle)
  sNr: '',
  bpEinf: '',
  hav: '',
  rohrCode: '',
  kabellaenge: '',
  hh: '',
  klsId: '',
  ausbauzustand: '',
  rohrverband: '',
  trasseVon: '',
  trasseBis: '',
  bauart: '',
  besonderheiten: '',
  rohrbelegung: '',
  uebersichtsplanReferenz: '',
  uebersichtsplanDownloadUrl: '',
  ausfuehrungBeginn: '',
  ausfuehrungBeginnUhrzeit: '',
  ausfuehrungEnde: '',
  ausfuehrungEndeUhrzeit: '',
  kolonne: '',
  ausfuehrungDokumentation: '',
  geoaceVorgang: '',
  aufmassLaenge: '',
  anzahlHausanschluesse: '',
  aufmassBemerkung: '',
  dokumentationFotos: [],
  baugrubenLaengen: [], // Längen in m pro Baugrube, Gesamtlänge = Summe (z. B. aus AR-Messung)
}

const COLOR_HEX = {
  rot: '#ef4444',
  grün: '#22c55e',
  blau: '#3b82f6',
  gelb: '#facc15',
  weiß: '#ffffff',
  grau: '#9ca3af',
  braun: '#a16207',
  violett: '#8b5cf6',
  türkis: '#06b6d4',
  schwarz: '#111827',
  orange: '#f97316',
  rosa: '#ec4899',
}

const normalizeColorKey = (name) => (name || '').toString().trim().toLowerCase()

function ColorSwatch({ name }) {
  const key = normalizeColorKey(name)
  const hex = COLOR_HEX[key]
  if (!hex) return null
  const isWhite = key === 'weiß'
  return (
    <span
      className={`color-swatch${isWhite ? ' is-white' : ''}`}
      title={name}
      aria-label={name}
      style={{ background: hex }}
    />
  )
}

function ColorPair({ left, right }) {
  const a = (left || '').trim()
  const b = (right || '').trim()
  if (!a && !b) return null
  return (
    <span className="color-pair" aria-label="Farbkombination">
      <ColorSwatch name={a} />
      <ColorSwatch name={b || a} />
    </span>
  )
}

// Google Drive: Ordner öffnen, Nutzer kopiert Link aus Adresszeile und fügt hier ein.
const GOOGLE_DRIVE_MY_DRIVE_URL = 'https://drive.google.com/drive/my-drive'
/** Such-URL für Drive: Ordner vorschlagen, die mit der NVT-Nummer enden bzw. sie enthalten. */
function getGoogleDriveSearchUrl(nvtValue) {
  const q = (nvtValue && String(nvtValue).trim()) || ''
  if (!q) return ''
  return `https://drive.google.com/drive/search?q=${encodeURIComponent(q)}`
}

// Geolocation: Nur über HTTPS (Ausnahme localhost). iOS: Standort nur nach User-Interaktion (Button-Klick).
const GEO_OPTIONS = { enableHighAccuracy: true, timeout: 30000, maximumAge: 0 }
const GEO_ERROR_HINT = 'Standort erfordert HTTPS (außer localhost). iOS: nur nach Tippen auf den Button; bei Ablehnung: Einstellungen → Datenschutz → Standort prüfen.'

function buildMapsNavUrl({ adresse, plz, ort, standort }) {
  const hasGps = standort && typeof standort.lat === 'number' && typeof standort.lng === 'number'
  const destination = hasGps
    ? `${standort.lat},${standort.lng}`
    : [adresse, plz, ort].filter(Boolean).join(', ')
  if (!destination.trim()) return ''
  return `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(destination)}`
}

function formatOrtsanwesenheit(o) {
  if (!o || (o.timestamp == null && o.lat == null)) return ''
  const ts = o.timestamp != null ? o.timestamp : (o.lat != null ? Date.now() : null)
  if (ts == null) return ''
  const dateStr = new Date(ts).toLocaleString('de-DE', { dateStyle: 'short', timeStyle: 'short' })
  if (typeof o.lat === 'number' && typeof o.lng === 'number') {
    return `${dateStr} (${o.lat.toFixed(5)}, ${o.lng.toFixed(5)})`
  }
  return dateStr
}

function useAuftraegeState() {
  const [auftraege, setAuftraege] = useState([])
  const [loaded, setLoaded] = useState(false)
  const [fetchError, setFetchError] = useState(false)
  const [reloadKey, setReloadKey] = useState(0)

  const reload = () => {
    setLoaded(false)
    setFetchError(false)
    setReloadKey((k) => k + 1)
  }

  useEffect(() => {
    if (!API_BASE) {
      setAuftraege([])
      setLoaded(true)
      setFetchError(false)
      return
    }
    setFetchError(false)
    fetch(`${API_BASE}/api/auftraege`)
      .then((r) => {
        if (!r.ok) throw new Error('Server fehlgeschlagen')
        return r.json()
      })
      .then((list) => {
        setAuftraege(Array.isArray(list) ? list : [])
        setFetchError(false)
      })
      .catch(() => {
        setAuftraege([])
        setFetchError(true)
      })
      .finally(() => setLoaded(true))
  }, [reloadKey])

  useEffect(() => {
    if (!loaded || !API_BASE || fetchError) return
    fetch(`${API_BASE}/api/auftraege`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(auftraege),
    })
      .then((r) => {
        if (!r.ok) throw new Error('Speichern fehlgeschlagen (Server ' + r.status + ')')
      })
      .catch((e) => console.error('Aufträge speichern:', e.message))
  }, [auftraege, loaded])
  return [auftraege, setAuftraege, loaded, fetchError, reload]
}

function AuftraegeProvider({ children }) {
  const value = useAuftraegeState()
  return <AuftraegeContext.Provider value={value}>{children}</AuftraegeContext.Provider>
}

function useAuftraege() {
  const ctx = useContext(AuftraegeContext)
  if (!ctx) throw new Error('useAuftraege muss innerhalb von AuftraegeProvider verwendet werden')
  return ctx
}

// Gemeinsam für Bericht-Seite und AuftragListe
function parseLaenge(auftrag) {
  const roh = (auftrag?.messungGraben ?? auftrag?.aufmassLaenge ?? auftrag?.kabellaenge ?? '').toString().trim()
  if (!roh) return 0
  const num = parseFloat(roh.replace(',', '.'))
  return Number.isFinite(num) ? num : 0
}

/** Summe aller Baugruben-Längen (m). Array aus Zahlen oder parsebarer Strings. */
function parseBaugrubenGesamt(auftrag) {
  const arr = Array.isArray(auftrag?.baugrubenLaengen) ? auftrag.baugrubenLaengen : []
  return arr.reduce((sum, v) => {
    const n = typeof v === 'number' ? v : parseFloat(String(v).replace(',', '.'))
    return sum + (Number.isFinite(n) ? n : 0)
  }, 0)
}
function terminToTs(termin) {
  const t = (termin || '').trim()
  if (!t) return Number.POSITIVE_INFINITY
  const m = t.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/)
  if (!m) return Number.POSITIVE_INFINITY
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), 0, 0).getTime()
}
function formatTermin(termin) {
  const ts = terminToTs(termin)
  if (!Number.isFinite(ts) || ts === Number.POSITIVE_INFINITY) return ''
  try {
    return new Date(ts).toLocaleString('de-DE', { dateStyle: 'short', timeStyle: 'short' })
  } catch {
    return String(termin || '')
  }
}
function sortByTermin(list) {
  return [...(list || [])].sort((a, b) => {
    const da = terminToTs(a?.termin)
    const db = terminToTs(b?.termin)
    if (da !== db) return da - db
    return String(a?.bezeichnung || '').localeCompare(String(b?.bezeichnung || ''), 'de')
  })
}
function getBerichtData(auftraege, von, bis) {
  const vonS = (von || '').trim()
  const bisS = (bis || '').trim()
  const list = (auftraege || []).filter((a) => {
    const ts = terminToTs(a?.termin)
    if (!Number.isFinite(ts) || ts === Number.POSITIVE_INFINITY) return false
    const d = new Date(ts).toISOString().slice(0, 10)
    if (vonS && d < vonS) return false
    if (bisS && d > bisS) return false
    return true
  })
  return { sortedBericht: sortByTermin(list), berichtSumme: list.reduce((s, a) => s + parseLaenge(a), 0) }
}
function openBerichtPdf(von, bis, sortedBericht, berichtSumme) {
  const vonLabel = von ? new Date(von + 'T12:00:00').toLocaleDateString('de-DE') : '—'
  const bisLabel = bis ? new Date(bis + 'T12:00:00').toLocaleDateString('de-DE') : '—'
  const rows = sortedBericht
    .map(
      (a) =>
        `<tr><td>${(formatTermin(a.termin) || '—').replace(/</g, '&lt;')}</td><td>${(a.bezeichnung || '—').replace(/</g, '&lt;')}</td><td>${([a.adresse, a.plz, a.ort].filter(Boolean).join(', ') || '—').replace(/</g, '&lt;')}</td><td>${parseLaenge(a).toFixed(1)}</td></tr>`
    )
    .join('')
  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Bericht nach Datum</title><style>body{font-family:system-ui,sans-serif;padding:1.5rem;color:#1e293b;}h1{font-size:1.25rem;margin:0 0 0.5rem;}p{margin:0 0 1rem;color:#64748b;}table{width:100%;border-collapse:collapse;}th,td{padding:0.5rem 0.75rem;text-align:left;border-bottom:1px solid #e2e8f0;}th{background:#f1f5f9;font-weight:600;}tfoot td{border-top:2px solid #cbd5e1;padding-top:0.75rem;font-weight:600;}</style></head><body><h1>Bericht nach Datum</h1><p>Zeitraum: ${vonLabel} – ${bisLabel} · ${sortedBericht.length} Auftrag/Aufträge</p><table><thead><tr><th>Termin</th><th>Bezeichnung</th><th>Adresse</th><th>Messung Graben (m)</th></tr></thead><tbody>${rows}</tbody><tfoot><tr><td colspan="3"><strong>Summe Zeitraum</strong></td><td><strong>${berichtSumme.toFixed(1)} m</strong></td></tr></tfoot></table></body></html>`
  const w = window.open('', '_blank')
  if (w) {
    w.document.write(html)
    w.document.close()
    w.focus()
    setTimeout(() => w.print(), 500)
  }
}
function openBerichtWhatsApp(von, bis, sortedBericht, berichtSumme) {
  const vonLabel = von ? new Date(von + 'T12:00:00').toLocaleDateString('de-DE') : '—'
  const bisLabel = bis ? new Date(bis + 'T12:00:00').toLocaleDateString('de-DE') : '—'
  const lines = [
    `Bericht nach Datum – Zeitraum ${vonLabel} bis ${bisLabel}`,
    `${sortedBericht.length} Auftrag/Aufträge · Summe Messung Graben: ${berichtSumme.toFixed(1)} m`,
    '',
    ...sortedBericht.map((a) => {
      const adr = [a.adresse, a.plz, a.ort].filter(Boolean).join(', ') || '—'
      return `• ${formatTermin(a.termin) || '—'} | ${a.bezeichnung || '—'} | ${adr} | ${parseLaenge(a).toFixed(1)} m`
    }),
    '',
    `Summe: ${berichtSumme.toFixed(1)} m`,
  ]
  window.open(`https://wa.me/?text=${encodeURIComponent(lines.join('\n'))}`, '_blank', 'noopener,noreferrer')
}

function AuftragListe() {
  const [auftraege, setAuftraege, loaded, fetchError, reload] = useAuftraege()
  const [form, setForm] = useState({
    termin: '',
    verbundGroesse: '',
    verbundFarbe: '',
    pipesFarbe1: '',
    pipesFarbe2: '',
    strasse: '',
    hausnummer: '',
    kontaktName: '',
    telefon: '',
    nvt: '',
    nvtStandort: '',
    standort: null,
    ortsanwesenheit: null,
    plz: '',
    ort: '',
    dokumentationFotos: [],
    geoAceMessung: 'nein',
    geprueft: 'nein',
    messungGraben: '',
    notizen: '',
    abgeschlossen: false,
    uebersichtsplanDownloadUrl: '',
  })
  const [importVorschau, setImportVorschau] = useState([])
  const [showNeuerAuftragForm, setShowNeuerAuftragForm] = useState(false)
  const [standortStatus, setStandortStatus] = useState('') // '' | 'loading' | 'ok' | 'error'
  const [ortsanwesenheitStatus, setOrtsanwesenheitStatus] = useState('') // '' | 'loading' | 'ok' | 'error'
  const [formFotoHinweis, setFormFotoHinweis] = useState('')
  const [formFotoViewer, setFormFotoViewer] = useState({ open: false, fotos: [], currentIndex: 0 })
  const openFormFotos = (fotos, idx = 0) => {
    if (!fotos?.length) return
    setFormFotoViewer({ open: true, fotos, currentIndex: Math.max(0, Math.min(idx, fotos.length - 1)) })
  }
  const closeFormFotos = () => setFormFotoViewer((v) => ({ ...v, open: false }))
  const nextFormFoto = () =>
    setFormFotoViewer((v) => ({ ...v, currentIndex: (v.currentIndex + 1) % v.fotos.length }))
  const prevFormFoto = () =>
    setFormFotoViewer((v) => ({ ...v, currentIndex: (v.currentIndex - 1 + v.fotos.length) % v.fotos.length }))
  const removeFormFoto = async (idx) => {
    const att = (form.dokumentationFotos || [])[idx]
    if (att?.url) {
      const result = await deleteUploadOnServer(att)
      if (!result.ok && !result.skipped) {
        alert('Server-Foto konnte nicht gelöscht werden.')
        return
      }
    }
    setForm((f) => {
      const list = Array.isArray(f.dokumentationFotos) ? [...f.dokumentationFotos] : []
      if (idx < 0 || idx >= list.length) return f
      list.splice(idx, 1)
      return { ...f, dokumentationFotos: list }
    })
  }

  const standortSpeichern = async () => {
    if (!('geolocation' in navigator)) {
      setStandortStatus('error')
      return
    }
    setStandortStatus('loading')
    try {
      const pos = await new Promise((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(resolve, reject, GEO_OPTIONS)
      })
      const standort = {
        lat: pos.coords.latitude,
        lng: pos.coords.longitude,
        accuracy: pos.coords.accuracy ?? 0,
        timestamp: pos.timestamp ?? Date.now(),
      }
      setForm((f) => ({ ...f, standort }))
      setStandortStatus('ok')
      setTimeout(() => setStandortStatus(''), 3000)
    } catch (err) {
      setStandortStatus('error')
      console.warn('Standort fehlgeschlagen', err)
    }
  }

  const ortsanwesenheitErfassen = async () => {
    if (!('geolocation' in navigator)) {
      setOrtsanwesenheitStatus('error')
      return
    }
    setOrtsanwesenheitStatus('loading')
    try {
      const pos = await new Promise((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(resolve, reject, GEO_OPTIONS)
      })
      const ortsanwesenheit = {
        lat: pos.coords.latitude,
        lng: pos.coords.longitude,
        accuracy: pos.coords.accuracy ?? 0,
        timestamp: Date.now(),
      }
      setForm((f) => ({ ...f, ortsanwesenheit }))
      setOrtsanwesenheitStatus('ok')
      setTimeout(() => setOrtsanwesenheitStatus(''), 3000)
    } catch (err) {
      setOrtsanwesenheitStatus('error')
      console.warn('Ortsanwesenheit fehlgeschlagen', err)
    }
  }

  const isAbgeschlossen = (a) => {
    if (!a) return false
    if (typeof a.abgeschlossen === 'boolean') return a.abgeschlossen
    if (typeof a.abgeschlossen === 'string') {
      const v = a.abgeschlossen.toLowerCase()
      if (v === 'true' || v === 'ja' || v === '1') return true
      if (v === 'false' || v === 'nein' || v === '0') return false
    }
    if (typeof a.status === 'string' && a.status.toLowerCase().includes('abgeschlossen')) return true
    return false
  }

  const groupByTerminDate = (list) => {
    const groups = new Map()
    for (const a of list || []) {
      const ts = terminToTs(a?.termin)
      const key = Number.isFinite(ts) && ts !== Number.POSITIVE_INFINITY ? new Date(ts).toISOString().slice(0, 10) : 'none'
      if (!groups.has(key)) groups.set(key, [])
      groups.get(key).push(a)
    }
    const keys = Array.from(groups.keys()).sort((ka, kb) => {
      if (ka === 'none') return 1
      if (kb === 'none') return -1
      return ka.localeCompare(kb)
    })
    return keys.map((key) => {
      const items = sortByTermin(groups.get(key) || [])
      const label =
        key === 'none'
          ? 'Ohne Termin'
          : new Date(`${key}T00:00:00`).toLocaleDateString('de-DE', { weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric' })
      return { key, label, items }
    })
  }

  const renderGroupedList = (list) => {
    const groups = groupByTerminDate(list)
    return (
      <div className="termin-groups">
        {groups.map((g) => (
          <div key={g.key} className="termin-group">
            <div className="termin-group-title">
              {g.label}
              <span className="termin-group-sum"> · {g.items.reduce((s, a) => s + parseLaenge(a), 0).toFixed(1)} m</span>
            </div>
            <ul className="list">
              {g.items.map(renderAuftragListenItem)}
            </ul>
          </div>
        ))}
      </div>
    )
  }

  const offeneAuftraege = sortByTermin(auftraege.filter((a) => !isAbgeschlossen(a)))
  const abgeschlosseneAuftraege = sortByTermin(auftraege.filter((a) => isAbgeschlossen(a)))
  const summeOffen = offeneAuftraege.reduce((sum, a) => sum + parseLaenge(a), 0)
  const summeAbgeschlossen = abgeschlosseneAuftraege.reduce((sum, a) => sum + parseLaenge(a), 0)
  const summeGesamt = summeOffen + summeAbgeschlossen

  const [fotoViewer, setFotoViewer] = useState({ open: false, fotos: [], currentIndex: 0 })
  const openFotos = (fotos) => {
    if (!fotos?.length) return
    setFotoViewer({ open: true, fotos, currentIndex: 0 })
  }
  const closeFotos = () => setFotoViewer((v) => ({ ...v, open: false }))
  const nextFoto = () =>
    setFotoViewer((v) => ({
      ...v,
      currentIndex: (v.currentIndex + 1) % v.fotos.length,
    }))
  const prevFoto = () =>
    setFotoViewer((v) => ({
      ...v,
      currentIndex: (v.currentIndex - 1 + v.fotos.length) % v.fotos.length,
    }))

  const deleteAuftrag = (auftragId, bezeichnung) => {
    if (!window.confirm(`Auftrag „${bezeichnung || auftragId}“ wirklich löschen?`)) return
    setAuftraege((list) => list.filter((a) => String(a.id) !== String(auftragId)))
  }

  const renderAuftragListenItem = (a) => {
    const fotos = a.dokumentationFotos || []
    const hasFotos = fotos.length > 0
    const firstThumb = hasFotos ? getAttachmentSrc(fotos[0]) : null
    const terminText = (a.termin || '').trim() ? formatTermin(a.termin) : ''
    const navUrl = buildMapsNavUrl({ adresse: a.adresse, plz: a.plz, ort: a.ort, standort: a.standort })
    const planUrl = (a.uebersichtsplanDownloadUrl || '').trim()
    const verbund = (a.verbundFarbe || '').trim()
    const pipes1 = (a.pipesFarbe1 || '').trim()
    const pipes2 = (a.pipesFarbe2 || '').trim()
    const addrLabel = [a.adresse, a.plz, a.ort].filter(Boolean).join(', ')
    return (
      <li key={a.id} className="list-item">
        <div>
          <div className="item-title">{a.bezeichnung}</div>
          <div className="item-sub">
            {navUrl ? (
              <a className="nav-link" href={navUrl} target="_blank" rel="noopener noreferrer" title="In Google Maps navigieren">
                {addrLabel || a.adresse || 'Adresse'}
              </a>
            ) : (
              <span>{addrLabel || a.adresse}</span>
            )}
            {terminText ? <span> · Termin: {terminText}</span> : null}
          </div>
          <div className="item-meta">
            {(a.messungGraben != null && String(a.messungGraben).trim() !== '') ? (
              <span className="meta-chip">Messung Graben: {parseLaenge(a).toFixed(1)} m</span>
            ) : null}
            {parseBaugrubenGesamt(a) > 0 ? (
              <span className="meta-chip">Baugruben: {parseBaugrubenGesamt(a).toFixed(1)} m</span>
            ) : null}
            {verbund ? (
              <span className="meta-chip">
                Verbund: {verbund}{' '}
                {verbund.includes('/') ? (
                  <ColorPair left={verbund.split('/')[0]} right={verbund.split('/')[1]} />
                ) : (
                  <ColorSwatch name={verbund} />
                )}
              </span>
            ) : null}
            {(pipes1 || pipes2) ? (
              <span className="meta-chip">
                Pipes: {pipes1 || '—'} / {pipes2 || pipes1 || '—'} <ColorPair left={pipes1} right={pipes2 || pipes1} />
              </span>
            ) : null}
            {planUrl ? (
              <a className="nav-link" href={planUrl} target="_blank" rel="noopener noreferrer">
                Übersichtsplan
              </a>
            ) : null}
          </div>
        </div>
        <div className="list-item-actions">
          {hasFotos && (
            <button
              type="button"
              className="foto-thumb-btn"
              onClick={() => openFotos(fotos)}
              title={`${fotos.length} Foto(s) anzeigen`}
              aria-label="Fotos anzeigen"
            >
            {(firstThumb && (firstThumb.startsWith('data:') || firstThumb.startsWith('http'))) ? (
              <img src={firstThumb} alt="" className="foto-thumb" crossOrigin="anonymous" />
            ) : (
              <span className="foto-thumb-icon">📷</span>
            )}
            {fotos.length > 1 && <span className="foto-count">{fotos.length}</span>}
          </button>
          )}
          <Link className="btn ghost" to={`/auftrag/${a.id}`}>
            Bearbeiten
          </Link>
          {isAbgeschlossen(a) && (
            <Link className="btn ghost" to={`/auftrag/${a.id}/protokoll`} target="_blank" rel="noopener noreferrer" title="Abschlussprotokoll">
              Protokoll
            </Link>
          )}
          <button
            type="button"
            className="btn btn-delete"
            onClick={() => deleteAuftrag(a.id, a.bezeichnung)}
            title="Auftrag löschen"
            aria-label="Löschen"
          >
            Löschen
          </button>
        </div>
      </li>
    )
  }

  const parseTableText = (text) => {
    const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean)
    if (lines.length < 2) return []
    const delim = lines[0].includes(';') ? ';' : lines[0].includes('\t') ? '\t' : ','
    const headers = lines[0].split(delim).map((h) => h.trim())
    return lines.slice(1).map((line) => {
      const cols = line.split(delim)
      const obj = {}
      headers.forEach((h, idx) => {
        obj[h] = (cols[idx] || '').trim()
      })
      return obj
    }).filter((row) => Object.values(row).some((v) => v))
  }

  const guessField = (row, keys) => {
    const lowerEntries = Object.entries(row).map(([k, v]) => [k.toLowerCase().trim(), v])
    const v = (val) => (val != null && String(val).trim() !== '' ? String(val).trim() : '')
    // Spezifischste Keywords zuerst prüfen (längere Treffer bevorzugen)
    const sortedKeys = [...keys].sort((a, b) => (b.length - a.length))
    for (const kw of sortedKeys) {
      const hit = lowerEntries.find(([k]) => k.includes(kw))
      if (hit && v(hit[1])) return v(hit[1])
    }
    const hit = lowerEntries.find(([k]) => keys.some((kw) => k.includes(kw)))
    return hit ? v(hit[1]) : ''
  }

  const parseExcelToRows = async (buffer) => {
    const XLSX = await import('xlsx')
    const wb = XLSX.read(buffer, { type: 'array' })
    const firstSheetName = wb.SheetNames[0]
    if (!firstSheetName) return []
    const sheet = wb.Sheets[firstSheetName]
    const raw = XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '' })
    if (raw.length < 2) return []
    const headers = raw[0].map((h, i) => String(h ?? '').trim() || `Spalte_${i}`)
    return raw.slice(1).map((row) => {
      const obj = {}
      headers.forEach((h, idx) => {
        obj[h] = String(row[idx] ?? '').trim()
      })
      return obj
    }).filter((row) => Object.values(row).some((v) => v))
  }

  const handleImportFile = async (e) => {
    const file = e.target.files?.[0]
    if (!file) return
    try {
      let rows = []
      const name = file.name.toLowerCase()
      const isPdf = file.type === 'application/pdf' || name.endsWith('.pdf')
      const isExcel = file.type === 'application/vnd.ms-excel' ||
        file.type === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
        name.endsWith('.xls') || name.endsWith('.xlsx')

      if (isPdf) {
        let text = ''
        const { GlobalWorkerOptions, getDocument } = await import('pdfjs-dist/legacy/build/pdf.mjs')
        GlobalWorkerOptions.workerSrc =
          'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.4.168/pdf.worker.min.js'
        const data = new Uint8Array(await file.arrayBuffer())
        const pdf = await getDocument({ data }).promise
        for (let pageNo = 1; pageNo <= pdf.numPages; pageNo += 1) {
          const page = await pdf.getPage(pageNo)
          const tc = await page.getTextContent()
          text += tc.items.map((it) => it.str).join(' ') + '\n'
        }
        rows = parseTableText(text)
      } else if (isExcel) {
        const buffer = await file.arrayBuffer()
        rows = await parseExcelToRows(buffer)
      } else {
        const text = await file.text()
        rows = parseTableText(text)
      }
      setImportVorschau(rows)
    } catch (err) {
      console.error('Import fehlgeschlagen', err)
      setImportVorschau([])
    }
  }

  const auftragAusImportAnnehmen = (row) => {
    const strasse = guessField(row, ['straße', 'strasse', 'str.', 'street'])
    const hausnr = guessField(row, ['hs. nr', 'hs nr', 'hausnr', 'hausnummer', 'hnr', 'haus-nr'])
    const zusammengesetzt = [strasse, hausnr].filter(Boolean).join(' ').trim()
    const bezeichnung =
      guessField(row, ['bezeichnung', 'projekt', 'objekt', 'bezeichnung/projekt']) ||
      zusammengesetzt ||
      Object.values(row)[0] ||
      ''
    const adresse =
      guessField(row, ['adresse', 'anschrift', 'straße', 'strasse']) ||
      zusammengesetzt ||
      ''
    const plz = guessField(row, ['plz', 'postleitzahl', 'plz / ort', 'plz/ort'])
    const ort = guessField(row, ['ort', 'plz / ort', 'plz/ort', 'stadt', 'standort']) || ''
    const netzbetreiber = guessField(row, ['netz', 'netzbetreiber', 'betreiber'])
    const kunde = guessField(row, ['kunde', 'auftraggeber'])
    const sNr = guessField(row, ['snr/nr', 'snr', 's/nr', 'rohrnummer', 'laufende nummer', 'snr-nr'])
    const bpEinf = guessField(row, ['bp-einf', 'bp einführung', 'baupunkt', 'bapunkt', 'bp.einf', 'bpeinf'])
    const hav = guessField(row, ['hav', 'bauabschnitt', 'muffe', 'muffenkennzeichnung'])
    const rohrCode = guessField(row, ['rohr/mikrorohr', 'rohr', 'mikrorohr', 'pipe', 'farbe', 'rohrbelegung', 'farbcode'])
    const kabellaenge = guessField(row, ['kabellänge', 'kabellaenge', 'kabellange', 'länge', 'laenge', 'meter', 'kabel'])
    const hh = guessField(row, ['hh', 'haushalte', 'anzahl haushalte'])
    const klsId = guessField(row, ['kls_id', 'kls-id', 'kls', 'apl', 'apl-id', 'apl_id', 'apl identnummer'])
    const ausbauzustand = guessField(row, ['ausbauzustand', 'passed', 'vorbereitet'])
    const rohrverband = guessField(row, ['rohrverband', 'snrv', 'sn/rv', 'speedpipe', 'speednet', '22x7', '8x7', '8x7 (o)', '22x7 + 1x12'])
    if (!bezeichnung.trim() || !adresse.trim()) return
    const id = Date.now()
    const neu = {
      id,
      ...defaultAuftrag,
      bezeichnung: bezeichnung.trim(),
      kunde: kunde.trim(),
      adresse: adresse.trim(),
      plz: plz.trim(),
      ort: ort.trim(),
      netzbetreiber: netzbetreiber.trim(),
      sNr,
      bpEinf,
      hav,
      rohrCode,
      kabellaenge,
      hh,
      klsId,
      ausbauzustand,
      rohrverband,
      quelleTabelle: row,
      status: 'angenommen',
    }
    setAuftraege((a) => [neu, ...a])
  }

  const addAuftrag = () => {
    const adr = (form.adresse || '').trim() || ([form.strasse, form.hausnummer].filter(Boolean).join(' ').trim())
    const bezeichnung = (form.bezeichnung || '').trim() || adr
    if (!bezeichnung || !adr) return
    const id = Date.now()
    const neu = {
      id,
      ...defaultAuftrag,
      bezeichnung,
      adresse: adr,
      termin: (form.termin || '').trim(),
      verbundGroesse: (form.verbundGroesse || '').trim(),
      verbundFarbe: (form.verbundFarbe || '').trim(),
      pipesFarbe1: (form.pipesFarbe1 || '').trim(),
      pipesFarbe2: (form.pipesFarbe2 || '').trim(),
      strasse: form.strasse.trim(),
      hausnummer: form.hausnummer.trim(),
      kontaktName: form.kontaktName.trim(),
      telefon: form.telefon.trim(),
      nvt: form.nvt.trim(),
      nvtStandort: form.nvtStandort.trim(),
      standort: form.standort,
      ortsanwesenheit: form.ortsanwesenheit,
      plz: form.plz.trim(),
      ort: form.ort.trim(),
      geoAceMessung: form.geoAceMessung,
      geprueft: form.geprueft,
      messungGraben: form.messungGraben.trim(),
      notizen: form.notizen.trim(),
      abgeschlossen: !!form.abgeschlossen,
      dokumentationFotos: form.dokumentationFotos,
      uebersichtsplanDownloadUrl: form.uebersichtsplanDownloadUrl.trim(),
    }
    setAuftraege((a) => [neu, ...a])
    setFormFotoHinweis('')
    setForm({
      termin: '',
      verbundGroesse: '',
      verbundFarbe: '',
      pipesFarbe1: '',
      pipesFarbe2: '',
      strasse: '',
      hausnummer: '',
      bezeichnung: '',
      adresse: '',
      kontaktName: '',
      telefon: '',
      nvt: '',
      nvtStandort: '',
      standort: null,
      ortsanwesenheit: null,
      plz: '',
      ort: '',
      dokumentationFotos: [],
      geoAceMessung: 'nein',
      geprueft: 'nein',
      messungGraben: '',
      notizen: '',
      abgeschlossen: false,
      uebersichtsplanDownloadUrl: '',
    })
    setShowNeuerAuftragForm(false)
  }

  return (
    <div className="page">
      <header className="topbar">
        <div className="logo">
          <img
            src="https://parsbau.de/wp-content/uploads/2023/10/logo-pars22-e1696588277925.jpg"
            alt="PARS Bau Logo"
          />
        </div>
        <h1>Hausanschlüsse – Tiefbau Webapp</h1>
        <p className="subtitle">
          Vom Gehweg bis ins Haus: Glasfaser‑Hausanschlüsse planen, dokumentieren und für das Aufmaß vorbereiten.
        </p>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.5rem', justifyContent: 'center', marginTop: '0.5rem' }}>
          <Link to="/bericht" className="btn ghost">
            Bericht nach Datum
          </Link>
          <Link to="/monteure" className="btn ghost">
            Monteure (App-Zuweisung)
          </Link>
          <Link to="/projekte" className="btn ghost">
            Projekte zuweisen
          </Link>
        </div>
      </header>

      <main className="content">
        {!showNeuerAuftragForm ? (
          <section className="card">
            <button
              type="button"
              className="btn primary"
              onClick={() => setShowNeuerAuftragForm(true)}
              style={{ fontSize: '1rem', padding: '0.6rem 1.25rem' }}
            >
              + Neuer Auftrag
            </button>
            <p className="muted" style={{ marginTop: '0.5rem', marginBottom: 0 }}>
              Klicken, um einen neuen Auftrag zu erfassen. Nach dem Speichern gelangen Sie zurück zur Übersicht.
            </p>
          </section>
        ) : (
        <section className="card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '0.5rem', marginBottom: '1rem' }}>
            <h2 style={{ margin: 0 }}>Neuer Auftrag</h2>
            <button type="button" className="btn ghost" onClick={() => setShowNeuerAuftragForm(false)}>
              Abbrechen
            </button>
          </div>
          <div className="form-stack">
            <label>
              Straße *
              <input
                type="text"
                value={form.strasse}
                onChange={(e) => setForm((f) => ({ ...f, strasse: e.target.value }))}
                placeholder="z. B. Musterstraße"
                autoComplete="address-line1"
              />
            </label>
            <label>
              Hausnummer *
              <input
                type="text"
                value={form.hausnummer}
                onChange={(e) => setForm((f) => ({ ...f, hausnummer: e.target.value }))}
                placeholder="z. B. 12 oder 12a"
                inputMode="numeric"
                autoComplete="address-line2"
              />
            </label>
            <label>
              PLZ
              <input
                type="text"
                value={form.plz}
                onChange={(e) => setForm((f) => ({ ...f, plz: e.target.value }))}
                placeholder="Postleitzahl"
                inputMode="numeric"
                autoComplete="postal-code"
              />
            </label>
            <label>
              Ort
              <input
                type="text"
                value={form.ort}
                onChange={(e) => setForm((f) => ({ ...f, ort: e.target.value }))}
                placeholder="Ort"
                autoComplete="address-level2"
              />
            </label>
            <label>
              Kontakt Name
              <input
                type="text"
                value={form.kontaktName}
                onChange={(e) => setForm((f) => ({ ...f, kontaktName: e.target.value }))}
                placeholder="Name des Ansprechpartners"
                autoComplete="name"
              />
            </label>
            <label>
              Telefon
              <input
                type="tel"
                value={form.telefon}
                onChange={(e) => setForm((f) => ({ ...f, telefon: e.target.value }))}
                placeholder="+49 …"
                inputMode="tel"
                autoComplete="tel"
              />
            </label>
            <label>
              NVT
              <input
                type="text"
                value={form.nvt}
                onChange={(e) => setForm((f) => ({ ...f, nvt: e.target.value }))}
                placeholder="NVT"
              />
            </label>
            <label>
              Termin (Datum & Uhrzeit)
              <input
                type="datetime-local"
                value={form.termin}
                onChange={(e) => setForm((f) => ({ ...f, termin: e.target.value }))}
              />
            </label>
            <label>
              Verbund Größe
              <select
                value={form.verbundGroesse}
                onChange={(e) => setForm((f) => ({ ...f, verbundGroesse: e.target.value }))}
              >
                <option value="">—</option>
                <option value="22x7">22x7</option>
                <option value="8x7">8x7</option>
                <option value="12x7">12x7</option>
              </select>
            </label>
            <label>
              Verbund Farbe
              <div className="select-with-swatch">
                <select
                  value={form.verbundFarbe}
                  onChange={(e) => setForm((f) => ({ ...f, verbundFarbe: e.target.value }))}
                >
                  <option value="">—</option>
                  <option value="Orange">Orange</option>
                  <option value="Orange/Schwarz">Orange/Schwarz</option>
                  <option value="Orange/Weiß">Orange/Weiß</option>
                  <option value="Orange/Rot">Orange/Rot</option>
                </select>
                {form.verbundFarbe.includes('/') ? (
                  <ColorPair left={form.verbundFarbe.split('/')[0]} right={form.verbundFarbe.split('/')[1]} />
                ) : (
                  <ColorSwatch name={form.verbundFarbe} />
                )}
              </div>
            </label>
            <label>
              Pipes Farbe (Kombination)
              <div className="pipes-row">
                <div className="select-with-swatch">
                  <select
                    value={form.pipesFarbe1}
                    onChange={(e) => setForm((f) => ({ ...f, pipesFarbe1: e.target.value }))}
                  >
                    <option value="">—</option>
                    <option value="rot">rot</option>
                    <option value="grün">grün</option>
                    <option value="blau">blau</option>
                    <option value="gelb">gelb</option>
                    <option value="weiß">weiß</option>
                    <option value="grau">grau</option>
                    <option value="braun">braun</option>
                    <option value="violett">violett</option>
                    <option value="türkis">türkis</option>
                    <option value="schwarz">schwarz</option>
                    <option value="orange">orange</option>
                    <option value="rosa">rosa</option>
                  </select>
                  <ColorSwatch name={form.pipesFarbe1} />
                </div>
                <div className="select-with-swatch">
                  <select
                    value={form.pipesFarbe2}
                    onChange={(e) => setForm((f) => ({ ...f, pipesFarbe2: e.target.value }))}
                  >
                    <option value="">—</option>
                    <option value="rot">rot</option>
                    <option value="grün">grün</option>
                    <option value="blau">blau</option>
                    <option value="gelb">gelb</option>
                    <option value="weiß">weiß</option>
                    <option value="grau">grau</option>
                    <option value="braun">braun</option>
                    <option value="violett">violett</option>
                    <option value="türkis">türkis</option>
                    <option value="schwarz">schwarz</option>
                    <option value="orange">orange</option>
                    <option value="rosa">rosa</option>
                  </select>
                  <ColorSwatch name={form.pipesFarbe2 || form.pipesFarbe1} />
                </div>
                <ColorPair left={form.pipesFarbe1} right={form.pipesFarbe2 || form.pipesFarbe1} />
              </div>
            </label>
            <label>
              Standort (GPS)
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.5rem', alignItems: 'center' }}>
                <button
                  className="btn ghost"
                  type="button"
                  onClick={standortSpeichern}
                  disabled={!('geolocation' in navigator) || standortStatus === 'loading'}
                >
                  {standortStatus === 'loading' ? 'Wird ermittelt…' : 'Standort speichern'}
                </button>
                <span className="muted" style={{ fontSize: '0.9rem' }}>
                  {form.standort
                    ? `${form.standort.lat.toFixed(6)}, ${form.standort.lng.toFixed(6)} (±${Math.round(form.standort.accuracy)} m)`
                    : '—'}
                </span>
                {standortStatus === 'ok' && <span className="standort-ok">Standort übernommen.</span>}
                {standortStatus === 'error' && (
                  <span className="standort-error">{GEO_ERROR_HINT}</span>
                )}
              </div>
              <p className="muted" style={{ marginTop: '0.35rem', fontSize: '0.8rem' }}>
                Beim ersten Klick fragt der Browser nach der Standortberechtigung. iOS: nur nach Tippen auf den Button; Seite über HTTPS aufrufen (localhost geht auch).
              </p>
            </label>
            <label>
              Ortsanwesenheit (Standort + Uhrzeit)
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.5rem', alignItems: 'center' }}>
                <button
                  className="btn ghost"
                  type="button"
                  onClick={ortsanwesenheitErfassen}
                  disabled={!('geolocation' in navigator) || ortsanwesenheitStatus === 'loading'}
                >
                  {ortsanwesenheitStatus === 'loading' ? 'Wird erfasst…' : 'Ortsanwesenheit jetzt erfassen'}
                </button>
                <span className="muted" style={{ fontSize: '0.9rem' }}>
                  {form.ortsanwesenheit ? formatOrtsanwesenheit(form.ortsanwesenheit) : '—'}
                </span>
                {ortsanwesenheitStatus === 'ok' && <span className="standort-ok">Erfasst.</span>}
                {ortsanwesenheitStatus === 'error' && <span className="standort-error">{GEO_ERROR_HINT}</span>}
              </div>
              <p className="muted" style={{ marginTop: '0.35rem', fontSize: '0.8rem' }}>
                Wie Standort: Berechtigung beim ersten Klick; iOS nur nach Tippen; HTTPS nötig (außer localhost).
              </p>
            </label>
            <label>
              Auftragsdokumentation Fotos
              <input
                type="file"
                accept="image/*"
                multiple
                onChange={async (e) => {
                  const list = Array.from(e.target.files || [])
                  e.target.value = ''
                  if (!list.length) return
                  const { attachments, fallbackUsed } = await filesToAttachments(list)
                  if (attachments?.length) {
                    setForm((f) => ({ ...f, dokumentationFotos: [...(f.dokumentationFotos || []), ...attachments] }))
                    if (fallbackUsed) setFormFotoHinweis('Server-Upload nicht möglich – Fotos werden mit dem Auftrag gespeichert.')
                  }
                }}
              />
              <span className="field-hint">Fotos werden mit dem neuen Auftrag übernommen. Nicht vergessen, den Auftrag anzulegen.</span>
              {formFotoHinweis && <span className="foto-upload-hinweis" role="status">{formFotoHinweis}</span>}
              {(form.dokumentationFotos || []).length > 0 && (
                <>
                  <div className="foto-grid" style={{ marginTop: '0.5rem' }}>
                    {(form.dokumentationFotos || []).map((att, i) => (
                      <div key={i} className="foto-tile">
                        <button type="button" className="foto-tile-imgbtn" onClick={() => openFormFotos(form.dokumentationFotos || [], i)} aria-label={`Foto ${i + 1} ansehen`}>
                          <img src={getAttachmentSrc(att)} alt="" crossOrigin="anonymous" />
                        </button>
                        <button
                          type="button"
                          className="foto-tile-del"
                          onClick={async () => {
                            if (window.confirm('Foto wirklich löschen?')) await removeFormFoto(i)
                          }}
                          aria-label={`Foto ${i + 1} löschen`}
                          title="Foto löschen"
                        >
                          ✕
                        </button>
                      </div>
                    ))}
                  </div>
                  <p className="muted" style={{ marginTop: '0.35rem' }}>
                    Fotos: {(form.dokumentationFotos || []).length} (werden erst beim Anlegen des Auftrags gespeichert)
                  </p>
                </>
              )}
            </label>
            <label>
              Übersichtsplan Download-Link
              <div className="input-with-action">
                <input
                  type="url"
                  value={form.uebersichtsplanDownloadUrl}
                  onChange={(e) => setForm((f) => ({ ...f, uebersichtsplanDownloadUrl: e.target.value }))}
                  placeholder="https://drive.google.com/drive/folders/…"
                />
                <button
                  type="button"
                  className="btn ghost"
                  onClick={() => {
                    window.open(GOOGLE_DRIVE_MY_DRIVE_URL, '_blank', 'noopener')
                  }}
                  title="Google Drive öffnen, Zielordner anwählen, Link aus Adresszeile kopieren und hier einfügen"
                >
                  Drive öffnen
                </button>
                {getGoogleDriveSearchUrl(form.nvt) && (
                  <button
                    type="button"
                    className="btn ghost"
                    onClick={() => {
                      window.open(getGoogleDriveSearchUrl(form.nvt), '_blank', 'noopener')
                    }}
                    title={`In Google Drive nach „${(form.nvt || '').trim()}“ suchen (z. B. Ordner, der mit der NVT-Nummer endet)`}
                  >
                    Nach NVT in Drive suchen
                  </button>
                )}
              </div>
              <span className="field-hint">
                Drive öffnen oder nach NVT-Nummer suchen (Ordner, der mit der NVT endet). Link aus der Adresszeile hier einfügen.
              </span>
            </label>
            <label>
              GEO ACE Messung
              <select
                value={form.geoAceMessung}
                onChange={(e) => setForm((f) => ({ ...f, geoAceMessung: e.target.value }))}
              >
                <option value="nein">Nein</option>
                <option value="ja">Ja</option>
              </select>
            </label>
            <label>
              Geprüft
              <select
                value={form.geprueft}
                onChange={(e) => setForm((f) => ({ ...f, geprueft: e.target.value }))}
              >
                <option value="nein">Nein</option>
                <option value="ja">Ja</option>
              </select>
            </label>
            <label className="label-inline">
              <input
                type="checkbox"
                checked={!!form.abgeschlossen}
                onChange={(e) => setForm((f) => ({ ...f, abgeschlossen: e.target.checked }))}
              />
              Auftrag abgeschlossen
            </label>
            <label>
              Messung Graben
              <input
                type="text"
                value={form.messungGraben}
                onChange={(e) => setForm((f) => ({ ...f, messungGraben: e.target.value }))}
              />
            </label>
            <label>
              Notizen
              <textarea
                rows={3}
                value={form.notizen}
                onChange={(e) => setForm((f) => ({ ...f, notizen: e.target.value }))}
                placeholder="Optionale Notizen"
              />
            </label>
          </div>
          <button className="btn primary" type="button" onClick={addAuftrag}>
            Auftrag speichern
          </button>
        </section>
        )}

        <section className="card" id="auftragsliste">
          <h2>Auftragsliste</h2>
          {API_BASE && <p className="muted" style={{ marginTop: '-0.25rem', marginBottom: '0.5rem' }}>Gemeinsamer Auftragspool – für alle Nutzer sichtbar und bearbeitbar.</p>}
          {!loaded && API_BASE && <p className="muted">Laden…</p>}
          {loaded && fetchError && (
            <div className="server-error" role="alert">
              <p>Server nicht erreichbar. Bitte in einem Terminal <code>npm run server</code> starten (Port 3010). In <code>.env</code> muss <code>VITE_API_URL=http://localhost:3010</code> stehen – danach Dev-Server neu starten (<code>npm run dev</code>).</p>
              <button type="button" className="btn primary" onClick={reload}>Erneut laden</button>
            </div>
          )}
          {loaded && !API_BASE && auftraege.length === 0 && <p className="muted">Ohne Server keine Aufträge. Bitte VITE_API_URL in .env setzen und Server starten.</p>}
          {loaded && API_BASE && !fetchError && auftraege.length === 0 && <p className="muted">Noch keine Aufträge erfasst.</p>}
          {loaded && !fetchError && auftraege.length > 0 && (
            <>
              <p className="muted">
                Offene Aufträge: {offeneAuftraege.length} · Abgeschlossen: {abgeschlosseneAuftraege.length} ·{' '}
                Länge offen: {summeOffen.toFixed(1)} m · Länge abgeschlossen: {summeAbgeschlossen.toFixed(1)} m · Gesamtlänge: {summeGesamt.toFixed(1)} m
              </p>

              <h3>Offene Aufträge</h3>
              {offeneAuftraege.length === 0 && (
                <p className="muted">Keine offenen Aufträge.</p>
              )}
              {offeneAuftraege.length > 0 && (
                <>
                  {renderGroupedList(offeneAuftraege)}
                  <p className="muted">Länge offen: {summeOffen.toFixed(1)} m</p>
                </>
              )}

              <h3>Abgeschlossene Aufträge</h3>
              {abgeschlosseneAuftraege.length === 0 && (
                <p className="muted">Noch keine abgeschlossenen Aufträge.</p>
              )}
              {abgeschlosseneAuftraege.length > 0 && (
                <>
                  {renderGroupedList(abgeschlosseneAuftraege)}
                  <p className="muted">Länge abgeschlossen: {summeAbgeschlossen.toFixed(1)} m</p>
                </>
              )}
            </>
          )}
        </section>
      </main>

      {fotoViewer.open && fotoViewer.fotos.length > 0 && (
        <div className="foto-lightbox" onClick={closeFotos} role="dialog" aria-modal="true" aria-label="Foto anzeigen">
          <button type="button" className="foto-lightbox-close" onClick={closeFotos} aria-label="Schließen">
            ×
          </button>
          <div className="foto-lightbox-inner" onClick={(e) => e.stopPropagation()}>
            {fotoViewer.fotos.length > 1 && (
              <button type="button" className="foto-lightbox-prev" onClick={prevFoto} aria-label="Vorheriges Foto">
                ‹
              </button>
            )}
            <img
              src={getAttachmentSrc(fotoViewer.fotos[fotoViewer.currentIndex])}
              alt=""
              className="foto-lightbox-img"
              crossOrigin="anonymous"
            />
            {fotoViewer.fotos.length > 1 && (
              <button type="button" className="foto-lightbox-next" onClick={nextFoto} aria-label="Nächstes Foto">
                ›
              </button>
            )}
          </div>
          {fotoViewer.fotos.length > 1 && (
            <p className="foto-lightbox-counter">
              {fotoViewer.currentIndex + 1} / {fotoViewer.fotos.length}
            </p>
          )}
        </div>
      )}

      {formFotoViewer.open && formFotoViewer.fotos.length > 0 && (
        <div className="foto-lightbox" onClick={closeFormFotos} role="dialog" aria-modal="true" aria-label="Foto anzeigen">
          <button type="button" className="foto-lightbox-close" onClick={closeFormFotos} aria-label="Schließen">
            ×
          </button>
          <div className="foto-lightbox-inner" onClick={(e) => e.stopPropagation()}>
            {formFotoViewer.fotos.length > 1 && (
              <button type="button" className="foto-lightbox-prev" onClick={prevFormFoto} aria-label="Vorheriges Foto">
                ‹
              </button>
            )}
            <img
              src={getAttachmentSrc(formFotoViewer.fotos[formFotoViewer.currentIndex])}
              alt=""
              className="foto-lightbox-img"
              crossOrigin="anonymous"
            />
            {formFotoViewer.fotos.length > 1 && (
              <button type="button" className="foto-lightbox-next" onClick={nextFormFoto} aria-label="Nächstes Foto">
                ›
              </button>
            )}
          </div>
          {formFotoViewer.fotos.length > 1 && (
            <p className="foto-lightbox-counter">
              {formFotoViewer.currentIndex + 1} / {formFotoViewer.fotos.length}
            </p>
          )}
        </div>
      )}
    </div>
  )
}

function AuftragDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const isNeu = id === 'neu'
  const [auftraege, setAuftraege, loaded] = useAuftraege()
  const [auftrag, setAuftrag] = useState(null)
  const [saveStatus, setSaveStatus] = useState('') // '' | 'gespeichert'
  const [ortsanwesenheitStatus, setOrtsanwesenheitStatus] = useState('')
  const [fotoUploadHinweis, setFotoUploadHinweis] = useState('')
  const [detailFotoViewer, setDetailFotoViewer] = useState({ open: false, fotos: [], currentIndex: 0 })
  const openDetailFotos = (fotos, idx = 0) => {
    if (!fotos?.length) return
    setDetailFotoViewer({ open: true, fotos, currentIndex: Math.max(0, Math.min(idx, fotos.length - 1)) })
  }
  const closeDetailFotos = () => setDetailFotoViewer((v) => ({ ...v, open: false }))
  const nextDetailFoto = () =>
    setDetailFotoViewer((v) => ({ ...v, currentIndex: (v.currentIndex + 1) % v.fotos.length }))
  const prevDetailFoto = () =>
    setDetailFotoViewer((v) => ({ ...v, currentIndex: (v.currentIndex - 1 + v.fotos.length) % v.fotos.length }))
  const removeDetailFoto = async (idx) => {
    const att = (auftrag?.dokumentationFotos || [])[idx]
    if (att?.url) {
      const result = await deleteUploadOnServer(att)
      if (!result.ok && !result.skipped) {
        alert('Server-Foto konnte nicht gelöscht werden.')
        return
      }
    }
    setAuftrag((p) => {
      const list = Array.isArray(p?.dokumentationFotos) ? [...p.dokumentationFotos] : []
      if (idx < 0 || idx >= list.length) return p
      list.splice(idx, 1)
      return { ...p, dokumentationFotos: list }
    })
  }
  const kameraCanvasRef = useRef(null)
  const [kameraFlow, setKameraFlow] = useState({
    open: false,
    loading: false,
    error: '',
    file: null,
    lat: null,
    lng: null,
    accuracy: null,
    street: '',
    house: '',
  })

  const closeKameraFlow = () => {
    setKameraFlow({
      open: false,
      loading: false,
      error: '',
      file: null,
      lat: null,
      lng: null,
      accuracy: null,
      street: '',
      house: '',
    })
  }

  const startKameraFlow = async (file) => {
    if (!file) return
    setFotoUploadHinweis('')
    setKameraFlow((p) => ({
      ...p,
      open: true,
      loading: true,
      error: '',
      file,
      lat: null,
      lng: null,
      accuracy: null,
      street: '',
      house: '',
    }))
    await requestKameraStandort()
  }

  const requestKameraStandort = async () => {
    setKameraFlow((p) => ({ ...p, loading: true, error: '' }))
    let pos = null
    try {
      pos = await new Promise((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(resolve, reject, GEO_OPTIONS)
      })
    } catch (err) {
      console.warn('Geolocation fehlgeschlagen', err)
    }

    const lat = pos?.coords?.latitude ?? null
    const lng = pos?.coords?.longitude ?? null
    const accuracy = pos?.coords?.accuracy ?? null

    let street = ''
    let house = ''
    let error = ''
    if (lat != null && lng != null) {
      try {
        const geo = await reverseGeocodeNominatim(lat, lng)
        street = geo.street || ''
        house = geo.house || ''
      } catch (err) {
        console.warn('Reverse-Geocoding fehlgeschlagen', err)
        error = 'Adresse konnte nicht automatisch ermittelt werden. Bitte manuell prüfen.'
      }
    } else {
      error = 'Standort nicht verfügbar. Bitte „Standort freigeben“ tippen oder Adresse manuell prüfen.'
    }

    setKameraFlow((p) => ({
      ...p,
      loading: false,
      error,
      lat,
      lng,
      accuracy,
      street: street || p.street,
      house: house || p.house,
    }))
  }

  useEffect(() => {
    if (!kameraFlow.open || !kameraFlow.file) return
    const canvas = kameraCanvasRef.current
    if (!canvas) return
    fileToCanvas(canvas, kameraFlow.file, { maxWidth: 1600 }).catch((e) => {
      console.warn('Vorschau fehlgeschlagen', e)
    })
  }, [kameraFlow.open, kameraFlow.file])

  const speichernKameraFoto = async () => {
    const canvas = kameraCanvasRef.current
    if (!canvas || !kameraFlow.file) return
    const street = (kameraFlow.street || '').trim()
    const house = (kameraFlow.house || '').trim()
    if (!house) {
      alert('Hausnummer bitte prüfen.')
      return
    }

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    const tsLabel = new Date().toLocaleString('de-DE')
    const nvt = (auftrag?.nvt || '').toString().trim()
    drawOverlay(ctx, canvas.width, canvas.height, { street, house, nvt, tsLabel })

    try {
      const annotatedFile = await canvasToJpegFile(canvas, 'hausanschluss', 0.9)
      const meta = {
        capturedAt: Date.now(),
        street,
        house,
        nvt,
        lat: kameraFlow.lat,
        lng: kameraFlow.lng,
        accuracy: kameraFlow.accuracy,
        reverseGeocode: 'nominatim',
      }
      const { attachment, fallbackUsed } = await fileToAttachmentWithMeta(annotatedFile, meta)
      setAuftrag((p) => ({
        ...p,
        dokumentationFotos: [...(p.dokumentationFotos || []), attachment],
      }))
      if (fallbackUsed) setFotoUploadHinweis('Server-Upload nicht möglich – Foto wird beim Speichern des Auftrags mitgespeichert.')
      closeKameraFlow()
    } catch (e) {
      console.error('Foto speichern fehlgeschlagen', e)
      alert('Foto konnte nicht gespeichert werden.')
    }
  }

  const ortsanwesenheitErfassen = async () => {
    if (!('geolocation' in navigator)) {
      setOrtsanwesenheitStatus('error')
      return
    }
    setOrtsanwesenheitStatus('loading')
    try {
      const pos = await new Promise((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(resolve, reject, GEO_OPTIONS)
      })
      setAuftrag((p) => ({
        ...p,
        ortsanwesenheit: {
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          accuracy: pos.coords.accuracy ?? 0,
          timestamp: Date.now(),
        },
      }))
      setOrtsanwesenheitStatus('ok')
      setTimeout(() => setOrtsanwesenheitStatus(''), 3000)
    } catch (err) {
      setOrtsanwesenheitStatus('error')
      console.warn('Ortsanwesenheit fehlgeschlagen', err)
    }
  }

  useEffect(() => {
    if (!loaded) return
    if (isNeu) {
      setAuftrag({ ...defaultAuftrag })
      return
    }
    const found = (auftraege || []).find((a) => String(a.id) === String(id))
    if (found) {
      setAuftrag({ ...defaultAuftrag, ...found })
    } else {
      navigate('/', { replace: true })
    }
  }, [loaded, isNeu, id, auftraege, navigate])

  const speichern = () => {
    const adr = (auftrag.adresse || '').trim() || (auftrag.strasse && auftrag.hausnummer ? `${auftrag.strasse} ${auftrag.hausnummer}`.trim() : '')
    if (!(auftrag.bezeichnung || '').trim()) return
    if (!adr) return
    if (isNeu) {
      const neueId = Date.now()
      const neu = { ...defaultAuftrag, ...auftrag, id: neueId, adresse: adr || auftrag.adresse }
      setAuftraege((list) => [neu, ...list])
      setAuftrag(neu)
      navigate(`/auftrag/${neueId}`, { replace: true })
    } else {
      const auftragId = auftrag.id
      setAuftraege((list) =>
        list.map((a) => {
          if (String(a.id) !== String(auftragId)) return a
          const merged = {
            ...defaultAuftrag,
            ...a,
            ...auftrag,
            id: a.id,
            adresse: adr || auftrag.adresse || a.adresse,
            dokumentationFotos: Array.isArray(auftrag.dokumentationFotos) ? auftrag.dokumentationFotos : (a.dokumentationFotos || []),
            auftragsDateien: Array.isArray(auftrag.auftragsDateien) ? auftrag.auftragsDateien : (a.auftragsDateien || []),
          }
          return merged
        }),
      )
      setSaveStatus('gespeichert')
      setFotoUploadHinweis('')
    }
  }

  useEffect(() => {
    if (saveStatus !== 'gespeichert') return
    const t = setTimeout(() => navigate('/', { replace: true }), 1800)
    return () => clearTimeout(t)
  }, [saveStatus, navigate])

  return (
    <div className="page">
      {!loaded && <p className="muted" style={{ padding: '2rem' }}>Laden…</p>}
      {loaded && !auftrag && <p className="muted" style={{ padding: '2rem' }}>Auftrag wird geladen…</p>}
      {loaded && auftrag && (
        <>
          <header className="topbar">
            <Link to="/" className="link-back">
              ← Zurück zur Übersicht
            </Link>
            <div className="logo">
              <img
                src="https://parsbau.de/wp-content/uploads/2023/10/logo-pars22-e1696588277925.jpg"
                alt="PARS Bau Logo"
              />
            </div>
            <h1>Hausanschluss – Auftrag</h1>
            <p className="subtitle">
              Auftragseingang, Trasse, Rohrbelegung, Übersichtsplan, Ausführung und Aufmaß (Geoace nur als Referenz).
            </p>
          </header>

          <main className="content">
        <section className="card">
          <h2>1. Auftragseingang / Stammdaten</h2>
          <div className="form-stack">
            <label>
              Bezeichnung / Projekt *
              <input
                type="text"
                value={auftrag.bezeichnung}
                onChange={(e) => setAuftrag((p) => ({ ...p, bezeichnung: e.target.value }))}
                placeholder="Projektbezeichnung"
              />
            </label>
            <label>
              Kunde / Auftraggeber
              <input
                type="text"
                value={auftrag.kunde}
                onChange={(e) => setAuftrag((p) => ({ ...p, kunde: e.target.value }))}
                placeholder="Kunde / Auftraggeber"
              />
            </label>
            <label>
              Adresse (Hausanschluss) *
              <input
                type="text"
                value={auftrag.adresse}
                onChange={(e) => setAuftrag((p) => ({ ...p, adresse: e.target.value }))}
                placeholder="Straße und Hausnummer"
              />
            </label>
            {(() => {
              const navUrl = buildMapsNavUrl({ adresse: auftrag.adresse, plz: auftrag.plz, ort: auftrag.ort, standort: auftrag.standort })
              return navUrl ? (
                <a className="btn ghost" href={navUrl} target="_blank" rel="noopener noreferrer" style={{ width: 'fit-content' }}>
                  Navigation in Google Maps
                </a>
              ) : null
            })()}
            <label>
              Termin (Datum & Uhrzeit)
              <input
                type="datetime-local"
                value={auftrag.termin ?? ''}
                onChange={(e) => setAuftrag((p) => ({ ...p, termin: e.target.value }))}
              />
            </label>
            <label>
              NVT
              <input
                type="text"
                value={auftrag.nvt ?? ''}
                onChange={(e) => setAuftrag((p) => ({ ...p, nvt: e.target.value }))}
                placeholder="NVT"
              />
            </label>
            <label>
              Ortsanwesenheit (Standort + Uhrzeit)
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.5rem', alignItems: 'center' }}>
                <button
                  className="btn ghost"
                  type="button"
                  onClick={ortsanwesenheitErfassen}
                  disabled={!('geolocation' in navigator) || ortsanwesenheitStatus === 'loading'}
                >
                  {ortsanwesenheitStatus === 'loading' ? 'Wird erfasst…' : 'Ortsanwesenheit jetzt erfassen'}
                </button>
                <span className="muted" style={{ fontSize: '0.9rem' }}>
                  {auftrag.ortsanwesenheit ? formatOrtsanwesenheit(auftrag.ortsanwesenheit) : '—'}
                </span>
                {ortsanwesenheitStatus === 'ok' && <span className="standort-ok">Erfasst.</span>}
                {ortsanwesenheitStatus === 'error' && <span className="standort-error">{GEO_ERROR_HINT}</span>}
              </div>
              <p className="muted" style={{ marginTop: '0.35rem', fontSize: '0.8rem' }}>
                Beim ersten Klick fragt der Browser nach der Standortberechtigung. iOS: nur nach Tippen; Seite über HTTPS (localhost geht auch).
              </p>
            </label>
            <label>
              PLZ
              <input
                type="text"
                value={auftrag.plz ?? ''}
                onChange={(e) => setAuftrag((p) => ({ ...p, plz: e.target.value }))}
                placeholder="Postleitzahl"
                inputMode="numeric"
              />
            </label>
            <label>
              Ort
              <input
                type="text"
                value={auftrag.ort}
                onChange={(e) => setAuftrag((p) => ({ ...p, ort: e.target.value }))}
                placeholder="Ort"
              />
            </label>
            <label>
              Netzbetreiber
              <input
                type="text"
                value={auftrag.netzbetreiber}
                onChange={(e) => setAuftrag((p) => ({ ...p, netzbetreiber: e.target.value }))}
                placeholder="Netzbetreiber"
              />
            </label>
          </div>
        </section>

        <section className="card">
          <h2>2. Rohrbelegung & Übersichtsplan</h2>
          <div className="form-stack">
            <label>
              Rohrbelegung (z. B. Rohr 1 = GF, Rohr 2 = Reserve)
              <textarea
                rows={3}
                value={auftrag.rohrbelegung}
                onChange={(e) => setAuftrag((p) => ({ ...p, rohrbelegung: e.target.value }))}
                placeholder="Rohrbelegung beschreiben"
              />
            </label>
            <label>
              Übersichtsplan‑Referenz
              <input
                type="text"
                value={auftrag.uebersichtsplanReferenz ?? ''}
                onChange={(e) => setAuftrag((p) => ({ ...p, uebersichtsplanReferenz: e.target.value }))}
                placeholder="Plannummer, Datei‑Link oder DMS‑Referenz"
              />
            </label>
            <label>
              Übersichtsplan Download-Link
              <div className="input-with-action">
                <input
                  type="url"
                  value={auftrag.uebersichtsplanDownloadUrl ?? ''}
                  onChange={(e) => setAuftrag((p) => ({ ...p, uebersichtsplanDownloadUrl: e.target.value }))}
                  placeholder="https://drive.google.com/drive/folders/…"
                />
                <button
                  type="button"
                  className="btn ghost"
                  onClick={() => {
                    window.open(GOOGLE_DRIVE_MY_DRIVE_URL, '_blank', 'noopener')
                  }}
                  title="Google Drive öffnen, Zielordner anwählen, Link aus Adresszeile kopieren und hier einfügen"
                >
                  Drive öffnen
                </button>
                {getGoogleDriveSearchUrl(auftrag.nvt) && (
                  <button
                    type="button"
                    className="btn ghost"
                    onClick={() => {
                      window.open(getGoogleDriveSearchUrl(auftrag.nvt), '_blank', 'noopener')
                    }}
                    title={`In Google Drive nach „${(auftrag.nvt || '').trim()}“ suchen (z. B. Ordner, der mit der NVT-Nummer endet)`}
                  >
                    Nach NVT in Drive suchen
                  </button>
                )}
              </div>
              <span className="field-hint">
                Drive öffnen oder nach NVT-Nummer suchen (Ordner, der mit der NVT endet). Link aus der Adresszeile hier einfügen.
              </span>
            </label>
          </div>
          {(auftrag.uebersichtsplanDownloadUrl || '').trim() && (
            <p style={{ marginTop: '0.5rem' }}>
              <a
                href={auftrag.uebersichtsplanDownloadUrl.trim()}
                target="_blank"
                rel="noopener noreferrer"
                className="btn ghost"
                style={{ display: 'inline-block' }}
              >
                Übersichtsplan herunterladen
              </a>
            </p>
          )}
        </section>

        <section className="card">
          <h2>3. Ausführung / Dokumentation</h2>
          <div className="form-stack">
            <label>
              Ausführung Beginn (Datum)
              <input
                type="date"
                value={auftrag.ausfuehrungBeginn ?? ''}
                onChange={(e) => setAuftrag((p) => ({ ...p, ausfuehrungBeginn: e.target.value }))}
              />
            </label>
            <label>
              Ausführung Beginn (Uhrzeit)
              <input
                type="time"
                value={auftrag.ausfuehrungBeginnUhrzeit ?? ''}
                onChange={(e) => setAuftrag((p) => ({ ...p, ausfuehrungBeginnUhrzeit: e.target.value }))}
              />
            </label>
            <label>
              Ausführung Ende (Datum)
              <input
                type="date"
                value={auftrag.ausfuehrungEnde ?? ''}
                onChange={(e) => setAuftrag((p) => ({ ...p, ausfuehrungEnde: e.target.value }))}
              />
            </label>
            <label>
              Ausführung Ende (Uhrzeit)
              <input
                type="time"
                value={auftrag.ausfuehrungEndeUhrzeit ?? ''}
                onChange={(e) => setAuftrag((p) => ({ ...p, ausfuehrungEndeUhrzeit: e.target.value }))}
              />
            </label>
            <label>
              Kolonne / Trupp
              <input
                type="text"
                value={auftrag.kolonne ?? ''}
                onChange={(e) => setAuftrag((p) => ({ ...p, kolonne: e.target.value }))}
                placeholder="Kolonne / Trupp"
              />
            </label>
            <label>
              Dokumentation der Ausführung
              <textarea
                rows={3}
                value={auftrag.ausfuehrungDokumentation}
                onChange={(e) => setAuftrag((p) => ({ ...p, ausfuehrungDokumentation: e.target.value }))}
                placeholder="Dokumentation der Ausführung"
              />
            </label>
            <label>
              Fotos
              <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap' }}>
                <div className="file-trigger-wrap">
                  <span className="btn ghost" aria-hidden>Kamera öffnen (Foto)</span>
                  <input
                    type="file"
                    accept="image/*"
                    capture="environment"
                    multiple
                    onChange={async (e) => {
                      const list = Array.from(e.target.files || [])
                      e.target.value = ''
                      if (!list.length) return
                      // Kamera-Workflow: GPS → Adresse prüfen → Overlay rendern → speichern
                      await startKameraFlow(list[0])
                      // Falls mehrere Bilder gewählt wurden: Rest normal hinzufügen (ohne Adress-Overlay)
                      if (list.length > 1) {
                        const rest = list.slice(1)
                        const { attachments, fallbackUsed } = await filesToAttachments(rest)
                        if (attachments?.length) {
                          setAuftrag((p) => ({
                            ...p,
                            dokumentationFotos: [...(p.dokumentationFotos || []), ...attachments],
                          }))
                          if (fallbackUsed) setFotoUploadHinweis('Server-Upload nicht möglich – Fotos werden beim Speichern des Auftrags mitgespeichert.')
                        }
                      }
                    }}
                  />
                </div>
                <div className="file-trigger-wrap">
                  <span className="btn ghost" aria-hidden>Fotos hochladen</span>
                  <input
                    type="file"
                    accept="image/*"
                    multiple
                    onChange={async (e) => {
                      const list = Array.from(e.target.files || [])
                      e.target.value = ''
                      if (!list.length) return
                      const { attachments, fallbackUsed } = await filesToAttachments(list)
                      if (attachments?.length) {
                        setAuftrag((p) => ({
                          ...p,
                          dokumentationFotos: [...(p.dokumentationFotos || []), ...attachments],
                        }))
                        if (fallbackUsed) setFotoUploadHinweis('Server-Upload nicht möglich – Fotos werden beim Speichern des Auftrags mitgespeichert.')
                      }
                    }}
                  />
                </div>
                <span className="muted" style={{ fontSize: '0.9rem' }}>
                  Fotos gespeichert: {(auftrag.dokumentationFotos || []).length}
                </span>
                <p className="foto-speichern-hinweis">Bitte auf «Speichern» klicken, damit die Fotos dauerhaft gespeichert werden.</p>
                {fotoUploadHinweis && <p className="foto-upload-hinweis" role="status">{fotoUploadHinweis}</p>}
              </div>
              {(auftrag.dokumentationFotos || []).length > 0 && (
                <div className="foto-grid" style={{ marginTop: '0.75rem' }}>
                  {(auftrag.dokumentationFotos || []).map((att, i) => (
                    <div key={i} className="foto-tile">
                      <button type="button" className="foto-tile-imgbtn" onClick={() => openDetailFotos(auftrag.dokumentationFotos || [], i)} aria-label={`Foto ${i + 1} ansehen`}>
                        <img src={getAttachmentSrc(att)} alt="" crossOrigin="anonymous" />
                      </button>
                      <button
                        type="button"
                        className="foto-tile-del"
                        onClick={async () => {
                          if (window.confirm('Foto wirklich löschen?')) await removeDetailFoto(i)
                        }}
                        aria-label={`Foto ${i + 1} löschen`}
                        title="Foto löschen"
                      >
                        ✕
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </label>
          </div>
        </section>

        <section className="card">
          <h2>4. Messung & Abschluss</h2>
          <div className="form-stack">
            <label>
              GEO ACE Messung
              <select
                value={auftrag.geoAceMessung}
                onChange={(e) => setAuftrag((p) => ({ ...p, geoAceMessung: e.target.value }))}
              >
                <option value="nein">Nein</option>
                <option value="ja">Ja</option>
              </select>
            </label>
            <label>
              Geprüft
              <select
                value={auftrag.geprueft}
                onChange={(e) => setAuftrag((p) => ({ ...p, geprueft: e.target.value }))}
              >
                <option value="nein">Nein</option>
                <option value="ja">Ja</option>
              </select>
            </label>
            <label>
              Baugruben-Messung (Längen in m)
              <p className="muted" style={{ marginBottom: '0.5rem', fontSize: '0.85rem' }}>
                Eine Baugrube oder mehrere Baugruben – Längen addieren sich zur Gesamtlänge (z. B. aus AR-/LiDAR-Messung oder manuell).
              </p>
              <div className="baugruben-list">
                {(Array.isArray(auftrag.baugrubenLaengen) ? auftrag.baugrubenLaengen : []).map((val, i) => (
                  <div key={i} className="baugrube-row">
                    <input
                      type="number"
                      min="0"
                      step="0.01"
                      value={val === '' || val == null ? '' : (Number(val) || 0)}
                      onChange={(e) => {
                        const v = e.target.value === '' ? '' : parseFloat(e.target.value)
                        setAuftrag((p) => {
                          const list = [...(Array.isArray(p.baugrubenLaengen) ? p.baugrubenLaengen : [])]
                          while (list.length <= i) list.push(0)
                          list[i] = Number.isFinite(v) ? v : 0
                          return { ...p, baugrubenLaengen: list }
                        })
                      }}
                      placeholder="m"
                      inputMode="decimal"
                    />
                    <span className="baugrube-unit">m</span>
                    <button
                      type="button"
                      className="btn ghost baugrube-del"
                      onClick={() => {
                        setAuftrag((p) => {
                          const list = [...(Array.isArray(p.baugrubenLaengen) ? p.baugrubenLaengen : [])]
                          list.splice(i, 1)
                          return { ...p, baugrubenLaengen: list }
                        })
                      }}
                      aria-label="Baugrube entfernen"
                      title="Entfernen"
                    >
                      ✕
                    </button>
                  </div>
                ))}
                <button
                  type="button"
                  className="btn ghost"
                  onClick={() => {
                    setAuftrag((p) => ({
                      ...p,
                      baugrubenLaengen: [...(Array.isArray(p.baugrubenLaengen) ? p.baugrubenLaengen : []), 0],
                    }))
                  }}
                >
                  + Baugrube
                </button>
              </div>
              {parseBaugrubenGesamt(auftrag) > 0 && (
                <p className="baugruben-sum" role="status">
                  Gesamtlänge Baugruben: <strong>{parseBaugrubenGesamt(auftrag).toFixed(2)} m</strong>
                </p>
              )}
            </label>
            <label>
              Messung Graben
              <input
                type="text"
                value={auftrag.messungGraben}
                onChange={(e) => setAuftrag((p) => ({ ...p, messungGraben: e.target.value }))}
                placeholder="Messung Graben"
              />
            </label>
            <label>
              Messung sonstiges
              <input
                type="text"
                value={auftrag.messungSonstiges}
                onChange={(e) => setAuftrag((p) => ({ ...p, messungSonstiges: e.target.value }))}
                placeholder="Messung sonstiges"
              />
            </label>
            <label>
              Notizen
              <textarea
                rows={3}
                value={auftrag.notizen}
                onChange={(e) => setAuftrag((p) => ({ ...p, notizen: e.target.value }))}
                placeholder="Notizen"
              />
            </label>
            <label className="label-inline">
              <input
                type="checkbox"
                checked={!!auftrag.inklusivMeter010}
                onChange={(e) => setAuftrag((p) => ({ ...p, inklusivMeter010: e.target.checked }))}
              />
              Inklusiv Meter (0-10m)
            </label>
            <label className="label-inline">
              <input
                type="checkbox"
                checked={!!auftrag.abgeschlossen}
                onChange={(e) => {
                  const checked = e.target.checked
                  setAuftrag((p) => ({ ...p, abgeschlossen: checked }))
                  if (checked && auftrag?.id) {
                    setAuftraege((list) =>
                      list.map((a) =>
                        String(a.id) === String(auftrag.id)
                          ? { ...defaultAuftrag, ...a, ...auftrag, abgeschlossen: true, id: a.id }
                          : a
                      )
                    )
                    const base = window.location.pathname.replace(/\/auftrag\/[^/]*$/, '') || '/'
                    const protokollUrl = `${base.replace(/\/$/, '')}/auftrag/${auftrag.id}/protokoll?print=1`
                    setTimeout(() => window.open(protokollUrl, '_blank', 'noopener'), 400)
                  }
                }}
              />
              Auftrag abgeschlossen
            </label>
          </div>
        </section>

        {saveStatus === 'gespeichert' && (
          <p className="save-success" role="status">
            ✓ Gespeichert. Weiterleitung zur Übersicht…
          </p>
        )}
        <div className="detail-actions">
          <button className="btn primary" type="button" onClick={speichern} disabled={saveStatus === 'gespeichert'}>
            Auftrag speichern
          </button>
          {!!auftrag.abgeschlossen && (
            <Link className="btn ghost" to={`/auftrag/${auftrag.id}/protokoll`} target="_blank" rel="noopener noreferrer">
              Abschlussprotokoll
            </Link>
          )}
        </div>
          </main>

          {kameraFlow.open && (
            <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label="Adresse prüfen" onClick={closeKameraFlow}>
              <div className="modal-card" onClick={(e) => e.stopPropagation()}>
                <div className="modal-head">
                  <h3>Adresse prüfen</h3>
                  <button type="button" className="btn ghost" onClick={closeKameraFlow} aria-label="Schließen">Schließen</button>
                </div>
                <div className="modal-body">
                  <canvas ref={kameraCanvasRef} className="kamera-preview-canvas" />
                  <div className="modal-hints">
                    {!!kameraFlow.accuracy && <p className="muted" style={{ margin: 0 }}>{formatAccuracyHint(kameraFlow.accuracy)}</p>}
                    {!!kameraFlow.error && <p className="foto-upload-hinweis" style={{ marginTop: '0.5rem' }}>{kameraFlow.error}</p>}
                    {kameraFlow.lat == null && (typeof window !== 'undefined') && (window.location?.protocol !== 'https:' && window.location?.hostname !== 'localhost') && (
                      <p className="foto-upload-hinweis" style={{ marginTop: '0.5rem' }}>
                        Standort benötigt HTTPS (außer localhost). Öffne die App über https://, dann erneut „Standort freigeben“.
                      </p>
                    )}
                    {kameraFlow.lat == null && (
                      <p className="muted" style={{ marginTop: '0.35rem' }}>
                        iPhone: Einstellungen → Datenschutz &amp; Sicherheit → Ortungsdienste → Browser (Safari/Chrome) → „Beim Verwenden“.{' '}
                        Android: Einstellungen → Apps → Browser → Berechtigungen → Standort erlauben.
                      </p>
                    )}
                    {kameraFlow.accuracy != null && Number(kameraFlow.accuracy) > 30 && (
                      <p className="foto-upload-hinweis" style={{ marginTop: '0.5rem' }}>
                        GPS ungenau – Adresse bitte besonders sorgfältig prüfen.
                      </p>
                    )}
                  </div>
                  <div className="modal-form">
                    <label>
                      Straße
                      <input
                        type="text"
                        value={kameraFlow.street}
                        onChange={(e) => setKameraFlow((p) => ({ ...p, street: e.target.value }))}
                        placeholder="Straße"
                      />
                    </label>
                    <label>
                      Hausnummer
                      <input
                        type="text"
                        value={kameraFlow.house}
                        onChange={(e) => setKameraFlow((p) => ({ ...p, house: e.target.value }))}
                        placeholder="Hausnummer"
                      />
                    </label>
                  </div>
                </div>
                <div className="modal-actions">
                  <button type="button" className="btn ghost" onClick={closeKameraFlow} disabled={kameraFlow.loading}>
                    Neu erfassen
                  </button>
                  {kameraFlow.lat == null && (
                    <button type="button" className="btn ghost" onClick={requestKameraStandort} disabled={kameraFlow.loading}>
                      Standort freigeben
                    </button>
                  )}
                  <button type="button" className="btn primary" onClick={speichernKameraFoto} disabled={kameraFlow.loading}>
                    {kameraFlow.loading ? 'Laden…' : 'Speichern'}
                  </button>
                </div>
              </div>
            </div>
          )}

          {detailFotoViewer.open && detailFotoViewer.fotos.length > 0 && (
            <div className="foto-lightbox" onClick={closeDetailFotos} role="dialog" aria-modal="true" aria-label="Foto anzeigen">
              <button type="button" className="foto-lightbox-close" onClick={closeDetailFotos} aria-label="Schließen">
                ×
              </button>
              <div className="foto-lightbox-inner" onClick={(e) => e.stopPropagation()}>
                {detailFotoViewer.fotos.length > 1 && (
                  <button type="button" className="foto-lightbox-prev" onClick={prevDetailFoto} aria-label="Vorheriges Foto">
                    ‹
                  </button>
                )}
                <img
                  src={getAttachmentSrc(detailFotoViewer.fotos[detailFotoViewer.currentIndex])}
                  alt=""
                  className="foto-lightbox-img"
                  crossOrigin="anonymous"
                />
                {detailFotoViewer.fotos.length > 1 && (
                  <button type="button" className="foto-lightbox-next" onClick={nextDetailFoto} aria-label="Nächstes Foto">
                    ›
                  </button>
                )}
              </div>
              {detailFotoViewer.fotos.length > 1 && (
                <p className="foto-lightbox-counter">
                  {detailFotoViewer.currentIndex + 1} / {detailFotoViewer.fotos.length}
                </p>
              )}
            </div>
          )}
        </>
      )}
    </div>
  )
}

function buildProtokollText(a) {
  if (!a) return ''
  const lines = [
    `Abschlussprotokoll – ${a.bezeichnung || 'Auftrag'}`,
    '',
    `Bezeichnung: ${a.bezeichnung || '—'}`,
    `Adresse: ${[a.adresse, a.plz, a.ort].filter(Boolean).join(', ') || '—'}`,
    a.nvt ? `NVT: ${a.nvt}` : null,
    a.termin ? `Termin: ${a.termin}` : null,
    a.verbundGroesse ? `Verbund Größe: ${a.verbundGroesse}` : null,
    a.verbundFarbe ? `Verbund Farbe: ${a.verbundFarbe}` : null,
    (a.pipesFarbe1 || a.pipesFarbe2) ? `Pipes Farbe: ${a.pipesFarbe1 || '—'} / ${a.pipesFarbe2 || a.pipesFarbe1 || '—'}` : null,
    a.kontaktName ? `Kontakt: ${a.kontaktName}` : null,
    a.telefon ? `Telefon: ${a.telefon}` : null,
    a.nvtStandort ? `NVT Standort: ${a.nvtStandort}` : null,
    a.ortsanwesenheit ? `Ortsanwesenheit: ${formatOrtsanwesenheit(a.ortsanwesenheit)}` : null,
    parseBaugrubenGesamt(a) > 0 ? `Baugruben Gesamtlänge: ${parseBaugrubenGesamt(a).toFixed(2)} m` : null,
    a.notizen ? `Notizen: ${a.notizen}` : null,
  ].filter(Boolean)
  return lines.join('\n')
}

function Abschlussprotokoll() {
  const { id } = useParams()
  const [searchParams] = useSearchParams()
  const [auftraege] = useAuftraege()
  const auftrag = (auftraege || []).find((a) => String(a.id) === String(id))
  const fotos = auftrag?.dokumentationFotos || []

  const handlePrint = () => window.print()
  const handleWhatsApp = () => {
    window.print()
    const text = buildProtokollText(auftrag)
    const url = `https://wa.me/?text=${encodeURIComponent(text)}`
    setTimeout(() => window.open(url, '_blank', 'noopener,noreferrer'), 600)
  }

  useEffect(() => {
    if (searchParams.get('print') === '1') {
      const t = setTimeout(() => window.print(), 800)
      return () => clearTimeout(t)
    }
  }, [searchParams])

  if (!auftrag) {
    return (
      <div className="page">
        <p className="muted">Auftrag nicht gefunden.</p>
        <Link to="/">Zurück zur Übersicht</Link>
      </div>
    )
  }

  return (
    <div className="page protokoll-page">
      <div className="no-print protokoll-actions">
        <Link className="btn ghost" to="/">← Zurück</Link>
        <button type="button" className="btn primary" onClick={handlePrint}>
          Als PDF speichern
        </button>
        <button type="button" className="btn ghost" onClick={handleWhatsApp}>
          Per WhatsApp teilen
        </button>
      </div>
      <div className="protokoll-content">
        <header className="protokoll-header">
          <img src="https://parsbau.de/wp-content/uploads/2023/10/logo-pars22-e1696588277925.jpg" alt="PARS Bau" className="protokoll-logo" />
          <h1>Abschlussprotokoll</h1>
          <p className="protokoll-date">Erstellt am {new Date().toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })}</p>
        </header>
        <section className="protokoll-section">
          <h2>Auftrag</h2>
          <dl className="protokoll-dl">
            <dt>Bezeichnung</dt><dd>{auftrag.bezeichnung || '—'}</dd>
            <dt>Adresse</dt><dd>{[auftrag.adresse, auftrag.plz, auftrag.ort].filter(Boolean).join(', ') || '—'}</dd>
            <dt>NVT</dt><dd>{auftrag.nvt || '—'}</dd>
            <dt>Termin</dt><dd>{auftrag.termin ? new Date(auftrag.termin).toLocaleString('de-DE', { dateStyle: 'short', timeStyle: 'short' }) : '—'}</dd>
            <dt>Verbund Größe</dt><dd>{auftrag.verbundGroesse || '—'}</dd>
            <dt>Verbund Farbe</dt><dd>{auftrag.verbundFarbe || '—'}</dd>
            <dt>Pipes Farbe</dt><dd>{(auftrag.pipesFarbe1 || auftrag.pipesFarbe2) ? `${auftrag.pipesFarbe1 || '—'} / ${auftrag.pipesFarbe2 || auftrag.pipesFarbe1 || '—'}` : '—'}</dd>
            <dt>Kontakt</dt><dd>{auftrag.kontaktName || '—'}</dd>
            <dt>Telefon</dt><dd>{auftrag.telefon || '—'}</dd>
            <dt>NVT Standort</dt><dd>{auftrag.nvtStandort || '—'}</dd>
            <dt>Ortsanwesenheit (mit Uhrzeit)</dt><dd>{auftrag.ortsanwesenheit ? formatOrtsanwesenheit(auftrag.ortsanwesenheit) : '—'}</dd>
            {parseBaugrubenGesamt(auftrag) > 0 ? (
              <><dt>Baugruben Gesamtlänge</dt><dd>{parseBaugrubenGesamt(auftrag).toFixed(2)} m</dd></>
            ) : null}
            {auftrag.notizen ? (<><dt>Notizen</dt><dd>{auftrag.notizen}</dd></>) : null}
          </dl>
        </section>
        {fotos.length > 0 && (
          <section className="protokoll-section">
            <h2>Fotos ({fotos.length})</h2>
            <div className="protokoll-fotos">
              {fotos.map((att, i) => (
                <figure key={i} className="protokoll-foto">
                  <img src={getAttachmentSrc(att)} alt={`Foto ${i + 1}`} crossOrigin="anonymous" />
                  <figcaption>Foto {i + 1}</figcaption>
                </figure>
              ))}
            </div>
          </section>
        )}
      </div>
    </div>
  )
}

function BerichtNachDatumPage() {
  const [auftraege] = useAuftraege()
  const [von, setVon] = useState('')
  const [bis, setBis] = useState('')
  const vonS = (von || '').trim()
  const bisS = (bis || '').trim()
  const { sortedBericht, berichtSumme } = getBerichtData(auftraege, vonS, bisS)

  return (
    <div className="page">
      <header className="topbar">
        <Link to="/" className="link-back">← Zurück zur Übersicht</Link>
        <div className="logo">
          <img src="https://parsbau.de/wp-content/uploads/2023/10/logo-pars22-e1696588277925.jpg" alt="PARS Bau Logo" />
        </div>
        <h1>Bericht nach Datum</h1>
        <p className="subtitle">Aufträge nach Termin filtern und Summe „Messung Graben“ für den Zeitraum.</p>
      </header>
      <main className="content">
        <section className="card">
          <div className="form-stack" style={{ maxWidth: '20rem', marginBottom: '1rem' }}>
            <label>Von (Datum)</label>
            <input type="date" value={von} onChange={(e) => setVon(e.target.value)} />
            <label>Bis (Datum)</label>
            <input type="date" value={bis} onChange={(e) => setBis(e.target.value)} />
          </div>
          {vonS || bisS ? (
            <>
              <p className="muted">
                {sortedBericht.length} Auftrag/Aufträge im Zeitraum · Summe Messung Graben: {berichtSumme.toFixed(1)} m
              </p>
              {sortedBericht.length === 0 ? (
                <p className="muted">Keine Aufträge mit Termin in diesem Zeitraum.</p>
              ) : (
                <>
                  <table className="bericht-table">
                    <thead>
                      <tr>
                        <th>Termin</th>
                        <th>Bezeichnung</th>
                        <th>Adresse</th>
                        <th>Messung Graben (m)</th>
                      </tr>
                    </thead>
                    <tbody>
                      {sortedBericht.map((a) => (
                        <tr key={a.id}>
                          <td>{formatTermin(a.termin) || '—'}</td>
                          <td>{a.bezeichnung || '—'}</td>
                          <td>{[a.adresse, a.plz, a.ort].filter(Boolean).join(', ') || '—'}</td>
                          <td>{parseLaenge(a).toFixed(1)}</td>
                        </tr>
                      ))}
                    </tbody>
                    <tfoot>
                      <tr>
                        <td colSpan={3}><strong>Tagessumme / Summe Zeitraum</strong></td>
                        <td><strong>{berichtSumme.toFixed(1)} m</strong></td>
                      </tr>
                    </tfoot>
                  </table>
                  <div className="bericht-actions" style={{ marginTop: '1rem', display: 'flex', flexWrap: 'wrap', gap: '0.5rem' }}>
                    <button type="button" className="btn primary" onClick={() => openBerichtPdf(vonS, bisS, sortedBericht, berichtSumme)}>
                      Als PDF speichern
                    </button>
                    <button type="button" className="btn ghost" onClick={() => { openBerichtPdf(vonS, bisS, sortedBericht, berichtSumme); openBerichtWhatsApp(vonS, bisS, sortedBericht, berichtSumme); }}>
                      PDF erstellen & per WhatsApp teilen
                    </button>
                  </div>
                </>
              )}
            </>
          ) : (
            <p className="muted">Von- und Bis-Datum wählen, um die Auflistung und Summe zu sehen.</p>
          )}
        </section>
      </main>
    </div>
  )
}

// ========== Admin: Monteure (User für App-Zuweisung) ==========
function MonteurePage() {
  const [users, setUsers] = useState([])
  const [loaded, setLoaded] = useState(false)
  const [error, setError] = useState(null)
  const [name, setName] = useState('')
  const [deviceId, setDeviceId] = useState('')

  const load = () => {
    if (!API_BASE) {
      setUsers([])
      setLoaded(true)
      return
    }
    setLoaded(false)
    setError(null)
    fetch(`${API_BASE}/api/users`)
      .then((r) => {
        if (!r.ok) throw new Error('Server fehlgeschlagen')
        return r.json()
      })
      .then((list) => {
        setUsers(Array.isArray(list) ? list : [])
        setError(null)
      })
      .catch((e) => {
        setUsers([])
        setError(e.message)
      })
      .finally(() => setLoaded(true))
  }

  useEffect(load, [])

  const addUser = () => {
    const n = (name || '').trim() || 'Monteur'
    const d = (deviceId || '').trim()
    if (!API_BASE) return
    fetch(`${API_BASE}/api/users`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: n, deviceId: d || undefined }),
    })
      .then((r) => {
        if (!r.ok) throw new Error('Speichern fehlgeschlagen')
        return r.json()
      })
      .then((newUser) => {
        setUsers((prev) => [...prev, newUser])
        setName('')
        setDeviceId('')
      })
      .catch((e) => alert(e.message))
  }

  const removeUser = (user) => {
    if (!window.confirm(`Monteur „${user.name}“ (${user.deviceId}) wirklich entfernen?`)) return
    const next = users.filter((u) => u.id !== user.id)
    setUsers(next)
    fetch(`${API_BASE}/api/users`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(next),
    }).catch((e) => {
      alert('Speichern fehlgeschlagen: ' + e.message)
      load()
    })
  }

  return (
    <div className="page">
      <header className="topbar">
        <Link to="/" className="link-back">← Zurück zur Übersicht</Link>
        <h1>Monteure (App-Zuweisung)</h1>
        <p className="subtitle">
          Hier werden die Nutzer der BauMeasurePro-App angelegt. Jeder Monteur erhält eine <strong>Geräte-ID</strong> – diese trägt er in der App ein, um seine zugewiesenen Projekte zu laden.
        </p>
      </header>
      <main className="content">
        {!API_BASE && (
          <section className="card">
            <p className="muted">Server (VITE_API_URL) nicht konfiguriert. Bitte Server starten und .env setzen.</p>
          </section>
        )}
        {API_BASE && (
          <>
            <section className="card">
              <h2>Neuer Monteur</h2>
              <div className="form-stack" style={{ maxWidth: '24rem', marginBottom: '1rem' }}>
                <label>Name</label>
                <input type="text" value={name} onChange={(e) => setName(e.target.value)} placeholder="z. B. Max Müller" />
                <label>Geräte-ID (optional – sonst wird eine ID erzeugt)</label>
                <input type="text" value={deviceId} onChange={(e) => setDeviceId(e.target.value)} placeholder="z. B. monteur-01" />
              </div>
              <button type="button" className="btn primary" onClick={addUser}>Monteur anlegen</button>
            </section>
            <section className="card">
              <h2>Monteure ({users.length})</h2>
              {!loaded && <p className="muted">Laden…</p>}
              {loaded && error && <p className="muted" style={{ color: 'var(--error, #b91c1c)' }}>{error}</p>}
              {loaded && !error && users.length === 0 && <p className="muted">Noch keine Monteure angelegt. Oben einen anlegen – dann in „Projekte zuweisen“ Projekte zuordnen.</p>}
              {loaded && !error && users.length > 0 && (
                <ul className="list" style={{ listStyle: 'none', padding: 0 }}>
                  {users.map((u) => (
                    <li key={u.id} className="list-item" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '0.5rem' }}>
                      <div>
                        <strong>{u.name}</strong>
                        <span className="muted" style={{ marginLeft: '0.5rem' }}>ID: {u.deviceId}</span>
                      </div>
                      <button type="button" className="btn btn-delete" onClick={() => removeUser(u)}>Entfernen</button>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          </>
        )}
      </main>
    </div>
  )
}

// ========== Admin: Projekte (an Monteure zuweisen) ==========
function ProjektePage() {
  const [projects, setProjects] = useState([])
  const [users, setUsers] = useState([])
  const [loaded, setLoaded] = useState(false)
  const [error, setError] = useState(null)
  const [projectName, setProjectName] = useState('')
  const [assignToUserId, setAssignToUserId] = useState('')

  const load = () => {
    if (!API_BASE) {
      setProjects([])
      setUsers([])
      setLoaded(true)
      return
    }
    setLoaded(false)
    setError(null)
    Promise.all([
      fetch(`${API_BASE}/api/projects`).then((r) => (r.ok ? r.json() : [])),
      fetch(`${API_BASE}/api/users`).then((r) => (r.ok ? r.json() : [])),
    ])
      .then(([projs, us]) => {
        setProjects(Array.isArray(projs) ? projs : [])
        setUsers(Array.isArray(us) ? us : [])
        setError(null)
      })
      .catch((e) => {
        setProjects([])
        setUsers([])
        setError(e.message)
      })
      .finally(() => setLoaded(true))
  }

  useEffect(load, [])

  const addProject = () => {
    const n = (projectName || '').trim() || 'Neues Projekt'
    if (!API_BASE) return
    fetch(`${API_BASE}/api/projects`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: n,
        assignedToUserId: assignToUserId || null,
      }),
    })
      .then((r) => {
        if (!r.ok) throw new Error('Speichern fehlgeschlagen')
        return r.json()
      })
      .then((newProj) => {
        setProjects((prev) => [...prev, newProj])
        setProjectName('')
      })
      .catch((e) => alert(e.message))
  }

  const setAssignment = (projectId, userId) => {
    if (!API_BASE) return
    fetch(`${API_BASE}/api/projects/${encodeURIComponent(projectId)}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ assignedToUserId: userId || null }),
    })
      .then((r) => {
        if (!r.ok) throw new Error('Aktualisieren fehlgeschlagen')
        return r.json()
      })
      .then((updated) => {
        setProjects((prev) => prev.map((p) => (p.id === updated.id ? updated : p)))
      })
      .catch((e) => alert(e.message))
  }

  const userName = (userId) => {
    if (!userId) return '—'
    const u = users.find((x) => x.id === userId)
    return u ? u.name : userId
  }

  return (
    <div className="page">
      <header className="topbar">
        <Link to="/" className="link-back">← Zurück zur Übersicht</Link>
        <h1>Projekte zuweisen</h1>
        <p className="subtitle">
          Projekte anlegen und einem Monteur zuweisen. In der BauMeasurePro-App gibt der Monteur seine <strong>Geräte-ID</strong> ein und erhält nur die ihm zugewiesenen Projekte.
        </p>
      </header>
      <main className="content">
        {!API_BASE && (
          <section className="card">
            <p className="muted">Server (VITE_API_URL) nicht konfiguriert.</p>
          </section>
        )}
        {API_BASE && (
          <>
            <section className="card">
              <h2>Neues Projekt</h2>
              <div className="form-stack" style={{ maxWidth: '24rem', marginBottom: '1rem' }}>
                <label>Projektname</label>
                <input type="text" value={projectName} onChange={(e) => setProjectName(e.target.value)} placeholder="z. B. Musterstraße 1" />
                <label>Zuweisen an Monteur</label>
                <select value={assignToUserId} onChange={(e) => setAssignToUserId(e.target.value)}>
                  <option value="">— Keiner —</option>
                  {users.map((u) => (
                    <option key={u.id} value={u.id}>{u.name} ({u.deviceId})</option>
                  ))}
                </select>
              </div>
              <button type="button" className="btn primary" onClick={addProject}>Projekt anlegen</button>
            </section>
            <section className="card">
              <h2>Projekte ({projects.length})</h2>
              {!loaded && <p className="muted">Laden…</p>}
              {loaded && error && <p className="muted" style={{ color: 'var(--error, #b91c1c)' }}>{error}</p>}
              {loaded && !error && projects.length === 0 && <p className="muted">Noch keine Projekte. Oben ein Projekt anlegen und optional einem Monteur zuweisen.</p>}
              {loaded && !error && projects.length > 0 && (
                <ul className="list" style={{ listStyle: 'none', padding: 0 }}>
                  {projects.map((p) => (
                    <li key={p.id} className="list-item" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '0.5rem' }}>
                      <div>
                        <strong>{p.name}</strong>
                        <span className="muted" style={{ marginLeft: '0.5rem' }}>→ {userName(p.assignedToUserId)}</span>
                      </div>
                      <select
                        value={p.assignedToUserId || ''}
                        onChange={(e) => setAssignment(p.id, e.target.value || null)}
                        style={{ minWidth: '10rem' }}
                      >
                        <option value="">— Keiner —</option>
                        {users.map((u) => (
                          <option key={u.id} value={u.id}>{u.name}</option>
                        ))}
                      </select>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          </>
        )}
      </main>
    </div>
  )
}

export default function App() {
  return (
    <AuftraegeProvider>
      {!API_BASE && (
        <div className="server-hint" role="alert">
          Auftragspool: Server starten (<code>npm run server</code>) und <code>VITE_API_URL</code> in .env eintragen – dann sehen und bearbeiten alle Nutzer dieselben Aufträge.
        </div>
      )}
      <Routes>
        <Route path="/" element={<AuftragListe />} />
        <Route path="/bericht" element={<BerichtNachDatumPage />} />
        <Route path="/monteure" element={<MonteurePage />} />
        <Route path="/projekte" element={<ProjektePage />} />
        <Route path="/auftrag/:id" element={<AuftragDetail />} />
        <Route path="/auftrag/:id/protokoll" element={<Abschlussprotokoll />} />
      </Routes>
    </AuftraegeProvider>
  )
}

