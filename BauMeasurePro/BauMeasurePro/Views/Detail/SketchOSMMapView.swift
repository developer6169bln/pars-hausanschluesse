import SwiftUI
import MapKit

/// Zeigt die Skizzen-Polylinie auf einer Karte mit OpenStreetMap-Kacheln (oft aktueller als Apple).
struct SketchOSMMapView: UIViewRepresentable {
    var region: MKCoordinateRegion
    var coordinates: [CLLocationCoordinate2D]
    var lineColor: UIColor = .systemBlue
    var pointLabelFontSizePx: Double = 12
    var pointMarkerStyle: PointMarkerStyle = .standard

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.pointLabelFontSizePx = pointLabelFontSizePx
        context.coordinator.pointMarkerStyle = pointMarkerStyle
        mapView.mapType = .mutedStandard
        mapView.region = region
        mapView.showsUserLocation = false

        let osmOverlay = OSMTileOverlay()
        osmOverlay.canReplaceMapContent = false
        mapView.addOverlay(osmOverlay, level: .aboveRoads)

        if coordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)

            for i in 0..<coordinates.count {
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
        context.coordinator.lineColor = lineColor
        context.coordinator.pointLabelFontSizePx = pointLabelFontSizePx
        context.coordinator.pointMarkerStyle = pointMarkerStyle

        let osmOverlay = OSMTileOverlay()
        osmOverlay.canReplaceMapContent = false
        mapView.addOverlay(osmOverlay, level: .aboveRoads)

        if coordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)

            for i in 0..<coordinates.count {
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
        var lineColor: UIColor = .systemBlue
        var pointLabelFontSizePx: Double = 12
        var pointMarkerStyle: PointMarkerStyle = .standard

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = lineColor
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "SketchPoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.backgroundColor = .clear

            let markerSize = max(18, min(36, CGFloat(pointLabelFontSizePx) + 8))
            let labelSize = min(max(6, CGFloat(pointLabelFontSizePx)), markerSize * 0.58)
            view.frame = CGRect(x: 0, y: 0, width: markerSize, height: markerSize)

            let circleTag = 101
            let labelTag = 102
            let circle: UIView
            let label: UILabel
            if let existing = view.viewWithTag(circleTag) {
                circle = existing
            } else {
                let v = UIView(frame: view.bounds)
                v.tag = circleTag
                v.layer.borderColor = UIColor.white.cgColor
                v.layer.borderWidth = 1
                v.clipsToBounds = true
                view.addSubview(v)
                circle = v
            }
            circle.frame = view.bounds
            circle.layer.cornerRadius = markerSize / 2
            circle.backgroundColor = pointMarkerStyle.fillColor
            circle.layer.borderColor = pointMarkerStyle.borderColor.cgColor

            if let existing = view.viewWithTag(labelTag) as? UILabel {
                label = existing
            } else {
                let l = UILabel(frame: view.bounds)
                l.tag = labelTag
                l.textAlignment = .center
                l.textColor = pointMarkerStyle.textColor
                l.layer.shadowColor = pointMarkerStyle.textStrokeColor.cgColor
                l.layer.shadowOpacity = 0.95
                l.layer.shadowRadius = 1
                l.layer.shadowOffset = .zero
                view.addSubview(l)
                label = l
            }
            label.frame = view.bounds
            label.font = .systemFont(ofSize: labelSize, weight: .bold)
            label.textColor = pointMarkerStyle.textColor
            label.layer.shadowColor = pointMarkerStyle.textStrokeColor.cgColor
            label.text = annotation.title ?? ""
            return view
        }
    }
}
