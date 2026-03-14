import SwiftUI
import WebKit
import CoreLocation

/// Zeigt den Projektstandort auf OpenStreetMap (eingebettet) und bietet Link „In OpenStreetMap öffnen“.
struct OpenStreetMapView: View {
    let coordinate: CLLocationCoordinate2D?
    var height: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let coord = coordinate {
                OpenStreetMapWebView(coordinate: coord)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button {
                    openInOpenStreetMap(coord)
                } label: {
                    Label("In OpenStreetMap öffnen", systemImage: "safari")
                }
                .font(.subheadline)
            } else {
                Text("Kein Standort verfügbar (z. B. aus AR-Messung oder Projektadresse).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openInOpenStreetMap(_ coord: CLLocationCoordinate2D) {
        let lat = coord.latitude
        let lon = coord.longitude
        // OSM-URL mit Marker und Zoom
        let urlStr = "https://www.openstreetmap.org/?mlat=\(lat)&mlon=\(lon)#map=18/\(lat)/\(lon)"
        guard let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - WKWebView mit Leaflet + OSM-Tiles

private struct OpenStreetMapWebView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = WKProcessPool()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemGray6
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
            <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
            <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        </head>
        <body style="margin:0;">
        <div id="map" style="width:100%;height:100%;min-height:180px;"></div>
        <script>
        var map = L.map('map').setView([\(lat), \(lon)], 17);
        L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        }).addTo(map);
        L.marker([\(lat), \(lon)]).addTo(map);
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.openstreetmap.org"))
    }
}
