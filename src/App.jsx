import { Routes, Route, Link, useNavigate, useParams } from 'react-router-dom'
import { useState, useEffect, useRef } from 'react'

const STORAGE_AUFTRAEGE = 'haus-auftraege'
const MAX_IMAGE_WIDTH = 800
const JPEG_QUALITY = 0.75

const API_BASE = (import.meta.env.VITE_API_URL || '').replace(/\/$/, '')

function getAttachmentSrc(item) {
  return item?.url || item?.dataUrl || ''
}

async function uploadOneToServer(file) {
  const formData = new FormData()
  formData.append('file', file)
  const res = await fetch(`${API_BASE}/api/upload`, { method: 'POST', body: formData })
  if (!res.ok) throw new Error(await res.text().catch(() => 'Upload fehlgeschlagen'))
  const data = await res.json()
  return { name: data.name || file.name, url: data.url, size: data.size ?? file.size, type: file.type }
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

const filesToAttachments = async (files) => {
  const list = Array.from(files || [])
  if (!list.length) return []
  if (API_BASE) {
    try {
      return await Promise.all(list.map((file) => uploadOneToServer(file)))
    } catch (e) {
      console.warn('Server-Upload fehlgeschlagen, Fallback auf lokale Speicherung', e)
    }
  }
  const readOne = async (file) => {
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
  return await Promise.all(list.map(readOne))
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
  strasse: '',
  hausnummer: '',
  kontaktName: '',
  telefon: '',
  nvt: '',
  nvtStandort: '',
  standort: null, // { lat, lng, accuracy, timestamp }
  geoAceMessung: 'nein',
  geprueft: 'nein',
  messungGraben: '',
  messungSonstiges: '',
  notizen: '',
  abgeschlossen: false,
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
}

function useAuftraege() {
  const [auftraege, setAuftraege] = useState([])
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    if (API_BASE) {
      fetch(`${API_BASE}/api/auftraege`)
        .then((r) => r.json())
        .then((list) => setAuftraege(Array.isArray(list) ? list : []))
        .catch(() => setAuftraege([]))
        .finally(() => setLoaded(true))
      return
    }
    try {
      const raw = window.localStorage.getItem(STORAGE_AUFTRAEGE)
      setAuftraege(raw ? JSON.parse(raw) : [])
    } catch {
      setAuftraege([])
    }
    setLoaded(true)
  }, [])

  useEffect(() => {
    if (!loaded) return
    if (API_BASE) {
      fetch(`${API_BASE}/api/auftraege`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(auftraege),
      }).catch(() => {})
      return
    }
    try {
      window.localStorage.setItem(STORAGE_AUFTRAEGE, JSON.stringify(auftraege))
    } catch (e) {
      if (e?.name === 'QuotaExceededError' || e?.code === 22) {
        const ohneFotos = auftraege.map((a) => ({
          ...a,
          dokumentationFotos: (a.dokumentationFotos || []).map((f) => ({ ...f, dataUrl: '' })),
          auftragsDateien: (a.auftragsDateien || []).map((f) => ({ ...f, dataUrl: '' })),
        }))
        try {
          window.localStorage.setItem(STORAGE_AUFTRAEGE, JSON.stringify(ohneFotos))
        } catch {}
      }
    }
  }, [auftraege, loaded])
  return [auftraege, setAuftraege, loaded]
}

function AuftragListe() {
  const [auftraege, setAuftraege, loaded] = useAuftraege()
  const [form, setForm] = useState({
    strasse: '',
    hausnummer: '',
    kontaktName: '',
    telefon: '',
    nvt: '',
    nvtStandort: '',
    standort: null,
    plz: '',
    ort: '',
    netzbetreiber: '',
    auftragsDateien: [],
    dokumentationFotos: [],
    geoAceMessung: 'nein',
    geprueft: 'nein',
    messungGraben: '',
    messungSonstiges: '',
    notizen: '',
    abgeschlossen: false,
    uebersichtsplanDownloadUrl: '',
  })
  const [importVorschau, setImportVorschau] = useState([])
  const [standortStatus, setStandortStatus] = useState('') // '' | 'loading' | 'ok' | 'error'

  const standortSpeichern = async () => {
    if (!('geolocation' in navigator)) {
      setStandortStatus('error')
      return
    }
    setStandortStatus('loading')
    try {
      const pos = await new Promise((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(resolve, reject, {
          enableHighAccuracy: true,
          timeout: 30000,
          maximumAge: 0,
        })
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

  const parseLaenge = (auftrag) => {
    const roh = auftrag.aufmassLaenge ?? auftrag.kabellaenge ?? ''
    if (!roh) return 0
    const num = parseFloat(String(roh).replace(',', '.'))
    return Number.isFinite(num) ? num : 0
  }

  const offeneAuftraege = auftraege.filter((a) => !a.abgeschlossen)
  const abgeschlosseneAuftraege = auftraege.filter((a) => a.abgeschlossen)
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
    return (
      <li key={a.id} className="list-item">
        <div>
          <div className="item-title">{a.bezeichnung}</div>
          <div className="item-sub">
            {a.adresse}
            {a.ort ? `, ${a.ort}` : ''}
            {a.netzbetreiber ? ` · ${a.netzbetreiber}` : ''}
            {a.aufmassLaenge && (
              <> · Länge: {String(a.aufmassLaenge).replace('.', ',')} m</>
            )}
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
    if (!form.strasse.trim() || !form.hausnummer.trim()) return
    const id = Date.now()
    const adresse = `${form.strasse} ${form.hausnummer}`.trim()
    const bezeichnung = adresse
    const neu = {
      id,
      ...defaultAuftrag,
      bezeichnung,
      adresse,
      strasse: form.strasse.trim(),
      hausnummer: form.hausnummer.trim(),
      kontaktName: form.kontaktName.trim(),
      telefon: form.telefon.trim(),
      nvt: form.nvt.trim(),
      nvtStandort: form.nvtStandort.trim(),
      standort: form.standort,
      plz: form.plz.trim(),
      ort: form.ort.trim(),
      netzbetreiber: form.netzbetreiber.trim(),
      geoAceMessung: form.geoAceMessung,
      geprueft: form.geprueft,
      messungGraben: form.messungGraben.trim(),
      messungSonstiges: form.messungSonstiges.trim(),
      notizen: form.notizen.trim(),
      abgeschlossen: !!form.abgeschlossen,
      auftragsDateien: form.auftragsDateien,
      dokumentationFotos: form.dokumentationFotos,
      uebersichtsplanDownloadUrl: form.uebersichtsplanDownloadUrl.trim(),
    }
    setAuftraege((a) => [neu, ...a])
    setForm({
      strasse: '',
      hausnummer: '',
      kontaktName: '',
      telefon: '',
      nvt: '',
      nvtStandort: '',
      standort: null,
      plz: '',
      ort: '',
      netzbetreiber: '',
      auftragsDateien: [],
      dokumentationFotos: [],
      geoAceMessung: 'nein',
      geprueft: 'nein',
      messungGraben: '',
      messungSonstiges: '',
      notizen: '',
      abgeschlossen: false,
      uebersichtsplanDownloadUrl: '',
    })
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
      </header>

      <main className="content">
        <section className="card">
          <h2>Neuer Auftrag</h2>
          <div className="row">
            <label>
              Straße *
              <input
                type="text"
                value={form.strasse}
                onChange={(e) => setForm((f) => ({ ...f, strasse: e.target.value }))}
                placeholder="z. B. Musterstraße"
              />
            </label>
            <label>
              Hausnummer *
              <input
                type="text"
                value={form.hausnummer}
                onChange={(e) => setForm((f) => ({ ...f, hausnummer: e.target.value }))}
                placeholder="z. B. 12a"
              />
            </label>
          </div>
          <div className="row">
            <label>
              Kontakt Name
              <input
                type="text"
                value={form.kontaktName}
                onChange={(e) => setForm((f) => ({ ...f, kontaktName: e.target.value }))}
              />
            </label>
            <label>
              Telefon
              <input
                type="text"
                value={form.telefon}
                onChange={(e) => setForm((f) => ({ ...f, telefon: e.target.value }))}
                placeholder="+49 …"
              />
            </label>
            <label>
              Ort
              <input
                type="text"
                value={form.ort}
                onChange={(e) => setForm((f) => ({ ...f, ort: e.target.value }))}
              />
            </label>
            <label>
              PLZ
              <input
                type="text"
                value={form.plz}
                onChange={(e) => setForm((f) => ({ ...f, plz: e.target.value }))}
                placeholder="Postleitzahl"
              />
            </label>
          </div>
          <div className="row">
            <label>
              NVT
              <input
                type="text"
                value={form.nvt}
                onChange={(e) => setForm((f) => ({ ...f, nvt: e.target.value }))}
              />
            </label>
            <label>
              NVT Standort
              <input
                type="text"
                value={form.nvtStandort}
                onChange={(e) => setForm((f) => ({ ...f, nvtStandort: e.target.value }))}
              />
            </label>
            <label>
              Netzbetreiber
              <input
                type="text"
                value={form.netzbetreiber}
                onChange={(e) => setForm((f) => ({ ...f, netzbetreiber: e.target.value }))}
              />
            </label>
          </div>
          <div className="row">
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
                  <span className="standort-error">
                    Standort fehlgeschlagen. iPhone: Einstellungen → Datenschutz → Standort prüfen; „Standort zulassen“ beim ersten Klick tippen. Seite ggf. über HTTPS öffnen.
                  </span>
                )}
              </div>
              <p className="muted" style={{ marginTop: '0.35rem', fontSize: '0.8rem' }}>
                Beim ersten Klick wird die Standortberechtigung angefragt (iPhone: „Standort zulassen“ tippen).
              </p>
            </label>
          </div>
          <div className="row">
            <label>
              Auftragsdateien hochladen (PDF)
              <input
                type="file"
                accept=".pdf,application/pdf"
                multiple
                onChange={async (e) => {
                  const atts = await filesToAttachments(e.target.files)
                  setForm((f) => ({ ...f, auftragsDateien: atts }))
                }}
              />
            </label>
            <label>
              Auftragsdokumentation Fotos
              <input
                type="file"
                accept="image/*"
                multiple
                onChange={async (e) => {
                  const atts = await filesToAttachments(e.target.files)
                  setForm((f) => ({ ...f, dokumentationFotos: atts }))
                }}
              />
            </label>
          </div>
          <div className="row">
            <label>
              Übersichtsplan Download-Link
              <input
                type="url"
                value={form.uebersichtsplanDownloadUrl}
                onChange={(e) => setForm((f) => ({ ...f, uebersichtsplanDownloadUrl: e.target.value }))}
                placeholder="https://…"
              />
            </label>
          </div>
          <div className="row">
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
            <label style={{ alignSelf: 'end' }}>
              <input
                type="checkbox"
                checked={!!form.abgeschlossen}
                onChange={(e) => setForm((f) => ({ ...f, abgeschlossen: e.target.checked }))}
              />{' '}
              Auftrag abgeschlossen
            </label>
          </div>
          <div className="row">
            <label>
              Messung Graben
              <input
                type="text"
                value={form.messungGraben}
                onChange={(e) => setForm((f) => ({ ...f, messungGraben: e.target.value }))}
              />
            </label>
            <label>
              Messung sonstiges
              <input
                type="text"
                value={form.messungSonstiges}
                onChange={(e) => setForm((f) => ({ ...f, messungSonstiges: e.target.value }))}
              />
            </label>
          </div>
          <label>
            Notizen
            <textarea
              rows={2}
              value={form.notizen}
              onChange={(e) => setForm((f) => ({ ...f, notizen: e.target.value }))}
            />
          </label>
          <button className="btn primary" type="button" onClick={addAuftrag}>
            Auftrag anlegen
          </button>
        </section>

        <section className="card">
          <h2>Auftragsliste</h2>
          {!loaded && API_BASE && <p className="muted">Laden…</p>}
          {loaded && auftraege.length === 0 && <p className="muted">Noch keine Aufträge erfasst.</p>}
          {loaded && auftraege.length > 0 && (
            <>
              <p className="muted">
                Offene Aufträge: {offeneAuftraege.length} · Abgeschlossen: {abgeschlosseneAuftraege.length} ·{' '}
                Gesamtlänge: {summeGesamt.toFixed(1)} m
              </p>

              <h3>Offene Aufträge</h3>
              {offeneAuftraege.length === 0 && (
                <p className="muted">Keine offenen Aufträge.</p>
              )}
              {offeneAuftraege.length > 0 && (
                <>
                  <ul className="list">
                    {offeneAuftraege.map(renderAuftragListenItem)}
                  </ul>
                  <p className="muted">Länge offen: {summeOffen.toFixed(1)} m</p>
                </>
              )}

              <h3>Abgeschlossene Aufträge</h3>
              {abgeschlosseneAuftraege.length === 0 && (
                <p className="muted">Noch keine abgeschlossenen Aufträge.</p>
              )}
              {abgeschlosseneAuftraege.length > 0 && (
                <>
                  <ul className="list">
                    {abgeschlosseneAuftraege.map(renderAuftragListenItem)}
                  </ul>
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
    </div>
  )
}

function AuftragDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const isNeu = id === 'neu'
  const [auftraege, setAuftraege, loaded] = useAuftraege()
  const kameraInputRef = useRef(null)
  const [auftrag, setAuftrag] = useState(null)
  const [saveStatus, setSaveStatus] = useState('') // '' | 'gespeichert'

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

  if (!loaded) return <div className="page"><p className="muted" style={{ padding: '2rem' }}>Laden…</p></div>
  if (!auftrag) return null

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
    }
  }

  useEffect(() => {
    if (saveStatus !== 'gespeichert') return
    const t = setTimeout(() => navigate('/', { replace: true }), 1800)
    return () => clearTimeout(t)
  }, [saveStatus, navigate])

  return (
    <div className="page">
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
          <div className="row">
            <label>
              Bezeichnung / Projekt *
              <input
                type="text"
                value={auftrag.bezeichnung}
                onChange={(e) => setAuftrag((p) => ({ ...p, bezeichnung: e.target.value }))}
              />
            </label>
            <label>
              Kunde / Auftraggeber
              <input
                type="text"
                value={auftrag.kunde}
                onChange={(e) => setAuftrag((p) => ({ ...p, kunde: e.target.value }))}
              />
            </label>
          </div>
          <div className="row">
            <label>
              Adresse (Hausanschluss) *
              <input
                type="text"
                value={auftrag.adresse}
                onChange={(e) => setAuftrag((p) => ({ ...p, adresse: e.target.value }))}
              />
            </label>
            <label>
              PLZ
              <input
                type="text"
                value={auftrag.plz ?? ''}
                onChange={(e) => setAuftrag((p) => ({ ...p, plz: e.target.value }))}
                placeholder="Postleitzahl"
              />
            </label>
            <label>
              Ort
              <input
                type="text"
                value={auftrag.ort}
                onChange={(e) => setAuftrag((p) => ({ ...p, ort: e.target.value }))}
              />
            </label>
            <label>
              Netzbetreiber
              <input
                type="text"
                value={auftrag.netzbetreiber}
                onChange={(e) => setAuftrag((p) => ({ ...p, netzbetreiber: e.target.value }))}
              />
            </label>
          </div>
        </section>

        <section className="card">
          <h2>2. Rohrbelegung & Übersichtsplan</h2>
          <label>
            Rohrbelegung (z. B. Rohr 1 = GF, Rohr 2 = Reserve)
            <textarea
              rows={3}
              value={auftrag.rohrbelegung}
              onChange={(e) => setAuftrag((p) => ({ ...p, rohrbelegung: e.target.value }))}
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
            <input
              type="url"
              value={auftrag.uebersichtsplanDownloadUrl ?? ''}
              onChange={(e) => setAuftrag((p) => ({ ...p, uebersichtsplanDownloadUrl: e.target.value }))}
              placeholder="https://…"
            />
          </label>
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
          <div className="row">
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
              />
            </label>
          </div>
          <label>
            Dokumentation der Ausführung
            <textarea
              rows={3}
              value={auftrag.ausfuehrungDokumentation}
              onChange={(e) => setAuftrag((p) => ({ ...p, ausfuehrungDokumentation: e.target.value }))}
            />
          </label>
          <div className="row" style={{ marginTop: '0.75rem' }}>
            <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap' }}>
              <button
                type="button"
                className="btn ghost"
                onClick={() => kameraInputRef.current?.click()}
              >
                Kamera öffnen (Foto)
              </button>
              <input
                ref={kameraInputRef}
                type="file"
                accept="image/*"
                capture="environment"
                multiple
                style={{ display: 'none' }}
                onChange={async (e) => {
                  const atts = await filesToAttachments(e.target.files)
                  if (!atts.length) return
                  setAuftrag((p) => ({
                    ...p,
                    dokumentationFotos: [...(p.dokumentationFotos || []), ...atts],
                  }))
                  e.target.value = ''
                }}
              />
              <span className="muted" style={{ fontSize: '0.9rem' }}>
                Fotos gespeichert: {(auftrag.dokumentationFotos || []).length}
              </span>
            </div>
          </div>
        </section>

        <section className="card">
          <h2>4. Aufmaß / Geoace (nur Referenz)</h2>
          <div className="row">
            <label>
              Geoace‑Vorgangsnummer
              <input
                type="text"
                value={auftrag.geoaceVorgang}
                onChange={(e) => setAuftrag((p) => ({ ...p, geoaceVorgang: e.target.value }))}
              />
            </label>
            <label>
              Länge Trasse (m)
              <input
                type="number"
                min="0"
                step="0.1"
                value={auftrag.aufmassLaenge}
                onChange={(e) => setAuftrag((p) => ({ ...p, aufmassLaenge: e.target.value }))}
              />
            </label>
            <label>
              Anzahl Hausanschlüsse
              <input
                type="number"
                min="0"
                step="1"
                value={auftrag.anzahlHausanschluesse}
                onChange={(e) => setAuftrag((p) => ({ ...p, anzahlHausanschluesse: e.target.value }))}
              />
            </label>
          </div>
          <label>
            Bemerkungen zum Aufmaß
            <textarea
              rows={2}
              value={auftrag.aufmassBemerkung}
              onChange={(e) => setAuftrag((p) => ({ ...p, aufmassBemerkung: e.target.value }))}
            />
          </label>
        </section>

        <section className="card">
          <h2>5. Messung & Abschluss</h2>
          <div className="row">
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
          </div>
          <div className="row">
            <label>
              Messung Graben
              <input
                type="text"
                value={auftrag.messungGraben}
                onChange={(e) => setAuftrag((p) => ({ ...p, messungGraben: e.target.value }))}
              />
            </label>
            <label>
              Messung sonstiges
              <input
                type="text"
                value={auftrag.messungSonstiges}
                onChange={(e) => setAuftrag((p) => ({ ...p, messungSonstiges: e.target.value }))}
              />
            </label>
          </div>
          <label>
            Notizen
            <textarea
              rows={2}
              value={auftrag.notizen}
              onChange={(e) => setAuftrag((p) => ({ ...p, notizen: e.target.value }))}
            />
          </label>
          <label style={{ marginTop: '0.75rem' }}>
            <input
              type="checkbox"
              checked={!!auftrag.abgeschlossen}
              onChange={(e) => setAuftrag((p) => ({ ...p, abgeschlossen: e.target.checked }))}
            />{' '}
            Auftrag abgeschlossen
          </label>
        </section>

        {saveStatus === 'gespeichert' && (
          <p className="save-success" role="status">
            ✓ Gespeichert. Weiterleitung zur Übersicht…
          </p>
        )}
        <button className="btn primary" type="button" onClick={speichern} disabled={saveStatus === 'gespeichert'}>
          Auftrag speichern
        </button>
      </main>
    </div>
  )
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<AuftragListe />} />
      <Route path="/auftrag/:id" element={<AuftragDetail />} />
    </Routes>
  )
}

