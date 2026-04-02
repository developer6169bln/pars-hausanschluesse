import { useEffect, useMemo, useRef, useState } from 'react'
import { Link } from 'react-router-dom'

import Map from 'ol/Map'
import View from 'ol/View'
import TileLayer from 'ol/layer/Tile'
import TileWMS from 'ol/source/TileWMS'
import OSM from 'ol/source/OSM'
import { fromLonLat } from 'ol/proj'

const DEFAULT_CENTER_LONLAT = [13.405, 52.52] // Berlin (Fallback)

export default function QgisMapPage({ apiBase }) {
  const mapElRef = useRef(null)
  const mapRef = useRef(null)
  const wmsSourceRef = useRef(null)

  const qgisWmsUrl = useMemo(() => {
    if (!apiBase) return ''
    return `${apiBase}/api/qgis/wms`
  }, [apiBase])

  const [layers, setLayers] = useState(() => import.meta.env.VITE_QGIS_WMS_LAYERS || '')
  const [visible, setVisible] = useState(true)
  const [featureInfo, setFeatureInfo] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    if (!mapElRef.current) return
    if (mapRef.current) return

    const base = new TileLayer({
      source: new OSM(),
    })

    const wmsSource = new TileWMS({
      url: qgisWmsUrl || 'about:blank',
      params: {
        SERVICE: 'WMS',
        REQUEST: 'GetMap',
        VERSION: '1.3.0',
        LAYERS: layers || '',
        STYLES: '',
        TILED: true,
        FORMAT: 'image/png',
        TRANSPARENT: true,
      },
      crossOrigin: 'anonymous',
    })
    wmsSourceRef.current = wmsSource

    const wms = new TileLayer({
      source: wmsSource,
      opacity: 0.85,
      visible: Boolean(layers) && visible,
    })

    const map = new Map({
      target: mapElRef.current,
      layers: [base, wms],
      view: new View({
        center: fromLonLat(DEFAULT_CENTER_LONLAT),
        zoom: 16,
      }),
    })

    map.on('singleclick', (evt) => {
      setError('')
      setFeatureInfo('Lade Feature-Info…')
      const src = wmsSourceRef.current
      if (!src || !qgisWmsUrl || !layers) {
        setFeatureInfo('')
        return
      }
      const view = map.getView()
      const resolution = view.getResolution()
      const projection = view.getProjection()
      if (!resolution || !projection) {
        setFeatureInfo('')
        return
      }

      const url = src.getFeatureInfoUrl(evt.coordinate, resolution, projection, {
        INFO_FORMAT: 'text/plain',
        QUERY_LAYERS: layers,
        FEATURE_COUNT: 10,
      })
      if (!url) {
        setFeatureInfo('Keine Feature-Info URL (Layer/Style prüfen).')
        return
      }
      fetch(url)
        .then((r) => r.text())
        .then((txt) => setFeatureInfo((txt || '').trim() || 'Keine Treffer.'))
        .catch((e) => {
          setFeatureInfo('')
          setError(e?.message || String(e))
        })
    })

    mapRef.current = map

    return () => {
      try { map.setTarget(undefined) } catch (_) {}
      mapRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    const src = wmsSourceRef.current
    const map = mapRef.current
    if (!src || !map) return

    src.setUrl(qgisWmsUrl || 'about:blank')
    src.updateParams({ LAYERS: layers || '' })

    const wmsLayer = map.getLayers().item(1)
    if (wmsLayer) {
      wmsLayer.setVisible(Boolean(layers) && visible)
    }
    map.render()
  }, [qgisWmsUrl, layers, visible])

  return (
    <div className="page">
      <header className="topbar">
        <Link to="/" className="link-back">← Zurück zur Übersicht</Link>
        <div className="logo">
          <img src="https://parsbau.de/wp-content/uploads/2023/10/logo-pars22-e1696588277925.jpg" alt="PARS Bau Logo" />
        </div>
        <h1>GIS (QGIS Server)</h1>
        <p className="subtitle">Web-Karte (OpenLayers) mit QGIS-WMS. Klick in die Karte → Feature-Info.</p>
      </header>

      <main className="content">
        <section className="card">
          {!apiBase && (
            <p className="muted">
              Server (VITE_API_URL) ist nicht konfiguriert – ohne Backend-Proxy kann kein QGIS Server angebunden werden.
            </p>
          )}

          <div className="form-stack" style={{ maxWidth: '42rem' }}>
            <label>WMS-Layer (Komma-getrennt, z. B. <code>projekt:leitungen,projekt:grundkarte</code>)</label>
            <input
              type="text"
              value={layers}
              onChange={(e) => setLayers(e.target.value)}
              placeholder="workspace:layername"
              spellCheck={false}
            />
            <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <input type="checkbox" checked={visible} onChange={(e) => setVisible(e.target.checked)} />
              WMS-Layer anzeigen
            </label>
            <p className="muted" style={{ marginTop: '-0.25rem' }}>
              Konfiguration: Backend-ENV <code>QGIS_WMS_BASE_URL</code> (z. B. <code>https://…/ows</code>).
            </p>
          </div>

          <div style={{ marginTop: '1rem', display: 'grid', gridTemplateColumns: '2fr 1fr', gap: '1rem', alignItems: 'stretch' }}>
            <div style={{ border: '1px solid #e2e8f0', borderRadius: 12, overflow: 'hidden', minHeight: '70vh' }}>
              <div ref={mapElRef} style={{ width: '100%', height: '70vh', background: '#f8fafc' }} />
            </div>
            <div style={{ border: '1px solid #e2e8f0', borderRadius: 12, padding: '0.75rem', background: '#fff', minHeight: '70vh', overflow: 'auto' }}>
              <h2 style={{ marginTop: 0 }}>Feature-Info</h2>
              {error && <p style={{ color: '#dc2626' }} role="alert">{error}</p>}
              {!error && !featureInfo && <p className="muted">In die Karte klicken, um Daten abzufragen.</p>}
              {featureInfo && (
                <pre style={{ whiteSpace: 'pre-wrap', fontSize: '0.85rem', margin: 0 }}>
                  {featureInfo}
                </pre>
              )}
            </div>
          </div>
        </section>
      </main>
    </div>
  )
}

