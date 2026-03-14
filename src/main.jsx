import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import App from './App.jsx'
import './App.css'

class AppErrorBoundary extends React.Component {
  state = { error: null }
  static getDerivedStateFromError(error) {
    return { error }
  }
  componentDidCatch(error, info) {
    console.error('App Error:', error, info)
  }
  render() {
    if (this.state.error) {
      return (
        <div style={{ padding: '2rem', fontFamily: 'system-ui, sans-serif', maxWidth: '600px' }}>
          <h1 style={{ color: '#b91c1c' }}>Fehler beim Laden</h1>
          <pre style={{ background: '#fef2f2', padding: '1rem', overflow: 'auto', fontSize: '0.875rem' }}>
            {this.state.error?.message ?? String(this.state.error)}
          </pre>
          <p className="muted">Bitte Seite neu laden. Server mit <code>npm run server</code> starten, ggf. <code>VITE_API_URL</code> in .env setzen.</p>
        </div>
      )
    }
    return this.props.children
  }
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <AppErrorBoundary>
      <BrowserRouter>
        <Routes>
          <Route path="/*" element={<App />} />
        </Routes>
      </BrowserRouter>
    </AppErrorBoundary>
  </React.StrictMode>,
)

