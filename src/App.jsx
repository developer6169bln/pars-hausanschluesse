import { Routes, Route, Link, useNavigate, useParams } from 'react-router-dom'
import { useState, useEffect, useRef } from 'react'

const STORAGE_AUFTRAEGE = 'haus-auftraege'

const filesToAttachments = async (files) => {
  const list = Array.from(files || [])
  const readOne = (file) =>
    new Promise((resolve) => {
      const reader = new FileReader()
      reader.onload = () =>
        resolve({
          name: file.name,
          type: file.type,
          size: file.size,
          lastModified: file.lastModified,
          dataUrl: typeof reader.result === 'string' ? reader.result : '',
        })
      reader.onerror = () =>
        resolve({
          name: file.name,
          type: file.type,
          size: file.size,
          lastModified: file.lastModified,
          dataUrl: '',
        })
      reader.readAsDataURL(file)
    })
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
  ausfuehrungBeginn: '',
  ausfuehrungEnde: '',
  kolonne: '',
  ausfuehrungDokumentation: '',
  geoaceVorgang: '',
  aufmassLaenge: '',
  anzahlHausanschluesse: '',
  aufmassBemerkung: '',
}

function useAuftraege() {
  const [auftraege, setAuftraege] = useState(() => {
    const raw = window.localStorage.getItem(STORAGE_AUFTRAEGE)
    return raw ? JSON.parse(raw) : []
  })
  useEffect(() => {
    window.localStorage.setItem(STORAGE_AUFTRAEGE, JSON.stringify(auftraege))
  }, [auftraege])
  return [auftraege, setAuftraege]
}

function AuftragListe() {
  const [auftraege, setAuftraege] = useAuftraege()
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
  })
  const [importVorschau, setImportVorschau] = useState([])

  const standortSpeichern = async () => {
    if (!('geolocation' in navigator)) return
    const pos = await new Promise((resolve, reject) => {
      navigator.geolocation.getCurrentPosition(resolve, reject, {
        enableHighAccuracy: true,
        timeout: 15000,
        maximumAge: 0,
      })
    })
    setForm((f) => ({
      ...f,
      standort: {
        lat: pos.coords.latitude,
        lng: pos.coords.longitude,
        accuracy: pos.coords.accuracy,
        timestamp: pos.timestamp,
      },
    }))
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

  const renderAuftragListenItem = (a) => (
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
      <Link className="btn ghost" to={`/auftrag/${a.id}`}>
        Bearbeiten
      </Link>
    </li>
  )

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
              <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                <button
                  className="btn ghost"
                  type="button"
                  onClick={() => standortSpeichern().catch(() => {})}
                  disabled={!('geolocation' in navigator)}
                >
                  Standort speichern
                </button>
                <span className="muted" style={{ fontSize: '0.9rem' }}>
                  {form.standort
                    ? `${form.standort.lat.toFixed(6)}, ${form.standort.lng.toFixed(6)} (±${Math.round(form.standort.accuracy)} m)`
                    : '—'}
                </span>
              </div>
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
          {auftraege.length === 0 && <p className="muted">Noch keine Aufträge erfasst.</p>}
          {auftraege.length > 0 && (
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
    </div>
  )
}

function AuftragDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const isNeu = id === 'neu'
  const [auftraege, setAuftraege] = useAuftraege()
  const kameraInputRef = useRef(null)
  const [auftrag, setAuftrag] = useState(() => {
    if (isNeu) return { ...defaultAuftrag }
    const found = (auftraege || []).find((a) => String(a.id) === String(id))
    return found ? { ...defaultAuftrag, ...found } : null
  })

  useEffect(() => {
    if (!isNeu && !auftrag) navigate('/', { replace: true })
  }, [isNeu, auftrag, navigate])

  if (!auftrag) return null

  const speichern = () => {
    if (!auftrag.bezeichnung?.trim() || !auftrag.adresse?.trim()) return
    if (isNeu) {
      const neueId = Date.now()
      const neu = { ...auftrag, id: neueId }
      setAuftraege((list) => [neu, ...list])
      setAuftrag(neu)
      navigate(`/auftrag/${neueId}`, { replace: true })
    } else {
      setAuftraege((list) =>
        list.map((a) => (String(a.id) === String(auftrag.id) ? { ...a, ...auftrag } : a)),
      )
    }
  }

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
          <h2>2. Tiefbau / Trasse</h2>
          <div className="row">
            <label>
              Trasse von
              <input
                type="text"
                value={auftrag.trasseVon}
                onChange={(e) => setAuftrag((p) => ({ ...p, trasseVon: e.target.value }))}
              />
            </label>
            <label>
              Trasse bis
              <input
                type="text"
                value={auftrag.trasseBis}
                onChange={(e) => setAuftrag((p) => ({ ...p, trasseBis: e.target.value }))}
              />
            </label>
            <label>
              Bauart
              <input
                type="text"
                value={auftrag.bauart}
                onChange={(e) => setAuftrag((p) => ({ ...p, bauart: e.target.value }))}
                placeholder="offener Graben, Spülbohrung, Pflasteraufnahme …"
              />
            </label>
          </div>
          <label>
            Besonderheiten / Hindernisse
            <textarea
              rows={2}
              value={auftrag.besonderheiten}
              onChange={(e) => setAuftrag((p) => ({ ...p, besonderheiten: e.target.value }))}
            />
          </label>
        </section>

        <section className="card">
          <h2>3. Rohrbelegung & Übersichtsplan</h2>
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
              value={auftrag.uebersichtsplanReferenz}
              onChange={(e) => setAuftrag((p) => ({ ...p, uebersichtsplanReferenz: e.target.value }))}
              placeholder="Plannummer, Datei‑Link oder DMS‑Referenz"
            />
          </label>
        </section>

        <section className="card">
          <h2>3a. Technische Daten / Rohrverband</h2>
          <div className="row">
            <label>
              SNR / Nr.
              <input
                type="text"
                value={auftrag.sNr}
                onChange={(e) => setAuftrag((p) => ({ ...p, sNr: e.target.value }))}
                placeholder="laufende Rohrnummer"
              />
            </label>
            <label>
              BP-Einf. (Baupunkt Einführung)
              <input
                type="text"
                value={auftrag.bpEinf ?? ''}
                onChange={(e) => setAuftrag((p) => ({ ...p, bpEinf: e.target.value }))}
                placeholder="Baupunkt Einführung"
              />
            </label>
            <label>
              Bauabschnitt / hav
              <input
                type="text"
                value={auftrag.hav}
                onChange={(e) => setAuftrag((p) => ({ ...p, hav: e.target.value }))}
                placeholder="z. B. hav 91–95"
              />
            </label>
            <label>
              Rohrverband / SN-RV
              <input
                type="text"
                value={auftrag.rohrverband}
                onChange={(e) => setAuftrag((p) => ({ ...p, rohrverband: e.target.value }))}
                placeholder="z. B. 22x7 + 1x12 (O)"
              />
            </label>
          </div>
          <div className="row">
            <label>
              Mikrorohr‑Code / Belegung
              <input
                type="text"
                value={auftrag.rohrCode}
                onChange={(e) => setAuftrag((p) => ({ ...p, rohrCode: e.target.value }))}
                placeholder="z. B. rt/1, gn/2, rt-/13 …"
              />
            </label>
          </div>
          <div className="row">
            <label>
              Kabellänge (m)
              <input
                type="text"
                value={auftrag.kabellaenge}
                onChange={(e) => setAuftrag((p) => ({ ...p, kabellaenge: e.target.value }))}
              />
            </label>
            <label>
              Haushalte (HH)
              <input
                type="text"
                value={auftrag.hh}
                onChange={(e) => setAuftrag((p) => ({ ...p, hh: e.target.value }))}
              />
            </label>
            <label>
              KLS / APL‑ID
              <input
                type="text"
                value={auftrag.klsId}
                onChange={(e) => setAuftrag((p) => ({ ...p, klsId: e.target.value }))}
              />
            </label>
          </div>
          <label>
            Ausbauzustand
            <input
              type="text"
              value={auftrag.ausbauzustand}
              onChange={(e) => setAuftrag((p) => ({ ...p, ausbauzustand: e.target.value }))}
              placeholder="z. B. passed+"
            />
          </label>
          <p className="muted" style={{ marginTop: '0.75rem' }}>
            Farbcode‑Legende: rt=rot, gn=grün, bl=blau, ge=gelb, ws=weiß, gr=grau, br=braun, vi=violett, tk=türkis,
            sw=schwarz, or=orange, rs=rosa. „rt-/13“ = zweites Bündel, Rohr 13, Farbe rot.
          </p>
        </section>

        <section className="card">
          <h2>4. Ausführung / Dokumentation</h2>
          <div className="row">
            <label>
              Ausführung Beginn
              <input
                type="date"
                value={auftrag.ausfuehrungBeginn}
                onChange={(e) => setAuftrag((p) => ({ ...p, ausfuehrungBeginn: e.target.value }))}
              />
            </label>
            <label>
              Ausführung Ende
              <input
                type="date"
                value={auftrag.ausfuehrungEnde}
                onChange={(e) => setAuftrag((p) => ({ ...p, ausfuehrungEnde: e.target.value }))}
              />
            </label>
            <label>
              Kolonne / Trupp
              <input
                type="text"
                value={auftrag.kolonne}
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
          <h2>5. Aufmaß / Geoace (nur Referenz)</h2>
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
          <h2>6. Messung & Abschluss</h2>
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

        <button className="btn primary" type="button" onClick={speichern}>
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

