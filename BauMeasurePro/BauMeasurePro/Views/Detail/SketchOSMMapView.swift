import SwiftUI
import MapKit

/// Zeigt die Skizzen-Polylinie auf einer Karte mit OpenStreetMap-Kacheln (oft aktueller als Apple).
struct SketchOSMMapView: UIViewRepresentable {
    var region: MKCoordinateRegion
    var coordinates: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .mutedStandard
        mapView.region = region
        mapView.showsUserLocation = false

        let osmOverlay = OSMTileOverlay()
        osmOverlay.canReplaceMapContent = false
        mapView.addOverlay(osmOverlay, level: .aboveRoads)

        if coordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)

            for i in [0, coordinates.count - 1] {
                let ann = MKPointAnnotation()
                ann.coordinate = coordinates[i]
                ann.title = i < 26 ? String(Unicode.Scalar(65 + i)!) : "\(i + 1)"
                mapView.addAnnotation(ann)
            }
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.region = region
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        let osmOverlay = OSMTileOverlay()
        osmOverlay.canReplaceMapContent = false
        mapView.addOverlay(osmOverlay, level: .aboveRoads)

        if coordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)

            for i in [0, coordinates.count - 1] {
                let ann = MKPointAnnotation()
                ann.coordinate = coordinates[i]
                ann.title = i < 26 ? String(Unicode.Scalar(65 + i)!) : "\(i + 1)"
                mapView.addAnnotation(ann)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "SketchPoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = .systemBlue
            view.glyphText = annotation.title ?? ""
            view.glyphTintColor = .white
            return view
        }
    }
}
