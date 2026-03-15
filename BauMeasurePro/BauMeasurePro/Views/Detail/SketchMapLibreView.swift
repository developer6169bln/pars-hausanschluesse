import SwiftUI
import MapLibre
import MapKit

/// Zeigt die Skizzen-Polylinie auf einer MapLibre GL Karte (Open-Source, oft aktuellere Karten).
struct SketchMapLibreView: UIViewRepresentable {
    var region: MKCoordinateRegion
    var coordinates: [CLLocationCoordinate2D]

    /// OpenFreeMap: kostenlose Vektorkarte (Straßen, Gewässer, Flächen). Funktioniert oft zuverlässiger als demotiles.
    private static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/bright")
    private static let polylineSourceId = "sketch-polyline"
    private static let polylineLayerId = "sketch-polyline-layer"

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: Self.styleURL)
        mapView.delegate = context.coordinator
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: region.center.latitude, longitude: region.center.longitude),
            zoomLevel: zoomLevel(for: region),
            animated: false
        )
        context.coordinator.coordinates = coordinates
        context.coordinator.region = region
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.coordinates = coordinates
        context.coordinator.region = region
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: region.center.latitude, longitude: region.center.longitude),
            zoomLevel: zoomLevel(for: region),
            animated: false
        )
        context.coordinator.updateAnnotations(in: mapView)
    }

    private func zoomLevel(for region: MKCoordinateRegion) -> Double {
        let latDelta = max(region.span.latitudeDelta, 0.001)
        return min(20, max(1, Double(log2(360.0 / latDelta))))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var coordinates: [CLLocationCoordinate2D] = []
        var region: MKCoordinateRegion = MKCoordinateRegion()

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            updateAnnotations(in: mapView)
        }

        func updateAnnotations(in mapView: MLNMapView) {
            guard let style = mapView.style, coordinates.count >= 2 else { return }

            if style.source(withIdentifier: SketchMapLibreView.polylineSourceId) != nil {
                if let layer = style.layer(withIdentifier: SketchMapLibreView.polylineLayerId) {
                    style.removeLayer(layer)
                }
                if let source = style.source(withIdentifier: SketchMapLibreView.polylineSourceId) {
                    style.removeSource(source)
                }
            }

            var coords = coordinates
            let polyline = coords.withUnsafeBufferPointer { buf in
                MLNPolylineFeature(coordinates: buf.baseAddress!, count: UInt(buf.count))
            }
            let source = MLNShapeSource(identifier: SketchMapLibreView.polylineSourceId, shape: polyline, options: nil)
            style.addSource(source)

            let layer = MLNLineStyleLayer(identifier: SketchMapLibreView.polylineLayerId, source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
            layer.lineWidth = NSExpression(forConstantValue: 4)
            layer.lineJoin = NSExpression(forConstantValue: "round")
            layer.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(layer)

            mapView.removeAnnotations(mapView.annotations ?? [])
            let labels = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
            for i in [0, coordinates.count - 1] {
                let ann = MLNPointAnnotation()
                ann.coordinate = coordinates[i]
                ann.title = i < labels.count ? labels[i] : "\(i + 1)"
                mapView.addAnnotation(ann)
            }
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let pointAnn = annotation as? MLNPointAnnotation else { return nil }
            let id = "SketchPoint"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
            if view == nil {
                view = MLNAnnotationView(reuseIdentifier: id)
                view?.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
                view?.layer.cornerRadius = 12
                view?.backgroundColor = .systemBlue
                view?.layer.borderWidth = 1
                view?.layer.borderColor = UIColor.white.cgColor
            }
            let label = view?.subviews.compactMap { $0 as? UILabel }.first
            if let label = label {
                label.text = pointAnn.title ?? ""
            } else {
                let lbl = UILabel(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
                lbl.textAlignment = .center
                lbl.font = .systemFont(ofSize: 10, weight: .bold)
                lbl.textColor = .white
                lbl.text = pointAnn.title ?? ""
                view?.addSubview(lbl)
            }
            return view
        }
    }
}
