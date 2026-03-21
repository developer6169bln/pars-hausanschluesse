import SwiftUI
import MapLibre
import MapKit

enum MapLibreEditTool: String, CaseIterable {
    case select = "Punkt auswählen"
    case add = "Neuen Punkt setzen"
}

/// Zeigt die Skizzen-Polylinie auf einer MapLibre GL Karte (Open-Source, oft aktuellere Karten).
struct SketchMapLibreView: UIViewRepresentable {
    var region: MKCoordinateRegion
    var coordinates: [CLLocationCoordinate2D]
    var isEditMode: Bool = false
    var hideIntermediatePoints: Bool = false
    var lineColor: UIColor = .systemBlue
    var showSegmentMeasures: Bool = false
    var segmentMeters: [Double] = []
    var segmentLabelFontSizePx: Double = 12
    var pointMarkerStyle: PointMarkerStyle = .standard
    var onTapAddPoint: ((CLLocationCoordinate2D) -> Void)? = nil
    var selectedIndex: Int? = nil
    var onSelectPoint: ((Int?) -> Void)? = nil
    var onMovePoint: ((Int, CLLocationCoordinate2D) -> Void)? = nil
    var tool: MapLibreEditTool = .add

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
        context.coordinator.isEditMode = isEditMode
        context.coordinator.hideIntermediatePoints = hideIntermediatePoints
        context.coordinator.lineColor = lineColor
        context.coordinator.showSegmentMeasures = showSegmentMeasures
        context.coordinator.segmentMeters = segmentMeters
        context.coordinator.segmentLabelFontSizePx = segmentLabelFontSizePx
        context.coordinator.pointMarkerStyle = pointMarkerStyle
        context.coordinator.onTapAddPoint = onTapAddPoint
        context.coordinator.selectedIndex = selectedIndex
        context.coordinator.onSelectPoint = onSelectPoint
        context.coordinator.onMovePoint = onMovePoint
        context.coordinator.tool = tool
        context.coordinator.mapViewRef = mapView

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.coordinates = coordinates
        context.coordinator.region = region
        context.coordinator.isEditMode = isEditMode
        context.coordinator.hideIntermediatePoints = hideIntermediatePoints
        context.coordinator.lineColor = lineColor
        context.coordinator.showSegmentMeasures = showSegmentMeasures
        context.coordinator.segmentMeters = segmentMeters
        context.coordinator.segmentLabelFontSizePx = segmentLabelFontSizePx
        context.coordinator.pointMarkerStyle = pointMarkerStyle
        context.coordinator.onTapAddPoint = onTapAddPoint
        context.coordinator.selectedIndex = selectedIndex
        context.coordinator.onSelectPoint = onSelectPoint
        context.coordinator.onMovePoint = onMovePoint
        context.coordinator.tool = tool
        // Wichtig: Im Edit-Modus (Vollbild / Punkte bearbeiten) NICHT ständig Kamera zurücksetzen,
        // sonst springt Zoom/Pan nach jeder Änderung wieder zurück.
        if !isEditMode {
            mapView.setCenter(
                CLLocationCoordinate2D(latitude: region.center.latitude, longitude: region.center.longitude),
                zoomLevel: zoomLevel(for: region),
                animated: false
            )
        }
        context.coordinator.updateAnnotations(in: mapView)
    }

    private func zoomLevel(for region: MKCoordinateRegion) -> Double {
        let latDelta = max(region.span.latitudeDelta, 0.001)
        return min(20, max(1, Double(log2(360.0 / latDelta))))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        var coordinates: [CLLocationCoordinate2D] = []
        var region: MKCoordinateRegion = MKCoordinateRegion()
        var isEditMode: Bool = false
        var hideIntermediatePoints: Bool = false
        var onTapAddPoint: ((CLLocationCoordinate2D) -> Void)?
        var selectedIndex: Int?
        var onSelectPoint: ((Int?) -> Void)?
        var onMovePoint: ((Int, CLLocationCoordinate2D) -> Void)?
        var tool: MapLibreEditTool = .add
        var lineColor: UIColor = .systemBlue
        var showSegmentMeasures: Bool = false
        var segmentMeters: [Double] = []
        var segmentLabelFontSizePx: Double = 12
        var pointMarkerStyle: PointMarkerStyle = .standard
        weak var mapViewRef: MLNMapView?

        private final class IndexedPointAnnotation: MLNPointAnnotation {
            var index: Int = 0
        }
        private final class SegmentLabelAnnotation: MLNPointAnnotation {}

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            mapViewRef = mapView
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
            layer.lineColor = NSExpression(forConstantValue: lineColor)
            layer.lineWidth = NSExpression(forConstantValue: 4)
            layer.lineJoin = NSExpression(forConstantValue: "round")
            layer.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(layer)

            mapView.removeAnnotations(mapView.annotations ?? [])
            let labels = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
            if isEditMode {
                let count = coordinates.count
                let last = max(0, count - 1)
                let indicesToShow: [Int]
                if hideIntermediatePoints, count > 2 {
                    var set: Set<Int> = [0, last]
                    if let sel = selectedIndex, sel >= 0, sel < count {
                        set.insert(sel)
                    }
                    indicesToShow = Array(set).sorted()
                } else {
                    indicesToShow = Array(0..<count)
                }
                for i in indicesToShow {
                    let ann = IndexedPointAnnotation()
                    ann.index = i
                    ann.coordinate = coordinates[i]
                    ann.title = i < labels.count ? labels[i] : "\(i + 1)"
                    mapView.addAnnotation(ann)
                }
            } else {
                // Normal: alle Messpunkte markieren
                for i in 0..<coordinates.count {
                    let ann = IndexedPointAnnotation()
                    ann.index = i
                    ann.coordinate = coordinates[i]
                    ann.title = i < labels.count ? labels[i] : "\(i + 1)"
                    mapView.addAnnotation(ann)
                }
            }

            // Segment-Maße als Labels zwischen den Punkten
            if showSegmentMeasures, coordinates.count >= 2 {
                for i in 0..<(coordinates.count - 1) {
                    guard i < segmentMeters.count else { break }
                    let a = coordinates[i]
                    let b = coordinates[i + 1]
                    let mid = CLLocationCoordinate2D(
                        latitude: (a.latitude + b.latitude) / 2,
                        longitude: (a.longitude + b.longitude) / 2
                    )
                    let ann = SegmentLabelAnnotation()
                    ann.coordinate = mid
                    ann.title = String(format: "%.2f m", segmentMeters[i])
                    mapView.addAnnotation(ann)
                }
            }
        }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard isEditMode, let mapView = gr.view as? MLNMapView else { return }
            let pt = gr.location(in: mapView)
            // Selektions-HitTest direkt gegen die Koordinatenliste (robuster als Annotation-APIs).
            let hitRadius: CGFloat = 40
            if coordinates.count >= 1 {
                let count = coordinates.count
                let last = max(0, count - 1)
                let indicesToCheck: [Int]
                if hideIntermediatePoints, count > 2 {
                    var set: Set<Int> = [0, last]
                    if let sel = selectedIndex, sel >= 0, sel < count {
                        set.insert(sel)
                    }
                    indicesToCheck = Array(set).sorted()
                } else {
                    indicesToCheck = Array(0..<count)
                }
                var bestIdx: Int?
                var bestD: CGFloat = .greatestFiniteMagnitude
                for i in indicesToCheck {
                    let p = mapView.convert(coordinates[i], toPointTo: mapView)
                    let d = hypot(p.x - pt.x, p.y - pt.y)
                    if d < bestD {
                        bestD = d
                        bestIdx = i
                    }
                }
                if let bestIdx, bestD <= hitRadius {
                    onSelectPoint?(bestIdx)
                    // Annotation optional selektieren, falls vorhanden (nur für visuelles Feedback).
                    if let ann = (mapView.annotations ?? []).compactMap({ $0 as? IndexedPointAnnotation }).first(where: { $0.index == bestIdx }) {
                        mapView.selectAnnotation(ann, animated: true, completionHandler: nil)
                    }
                    return
                }
            }

            // Im Select-Tool: niemals neue Punkte setzen.
            guard tool == .add else { return }

            let coord = mapView.convert(pt, toCoordinateFrom: mapView)
            onTapAddPoint?(coord)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            guard isEditMode else { return }
            if let a = annotation as? IndexedPointAnnotation {
                onSelectPoint?(a.index)
            } else {
                onSelectPoint?(nil)
            }
        }

        func mapView(_ mapView: MLNMapView, didDeselect annotation: MLNAnnotation) {
            guard isEditMode else { return }
            onSelectPoint?(nil)
        }

        func mapView(_ mapView: MLNMapView, annotationCanMove annotation: MLNAnnotation) -> Bool {
            isEditMode
        }

        func mapView(_ mapView: MLNMapView, annotation: MLNAnnotation, didChangeDragState newState: MLNAnnotationViewDragState, fromOldState oldState: MLNAnnotationViewDragState) {
            guard isEditMode, newState == .ending else { return }
            guard let a = annotation as? IndexedPointAnnotation else { return }
            onMovePoint?(a.index, annotation.coordinate)
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let pointAnn = annotation as? MLNPointAnnotation else { return nil }
            if annotation is SegmentLabelAnnotation {
                let id = "SegLabel"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                if view == nil {
                    view = MLNAnnotationView(reuseIdentifier: id)
                    view?.frame = CGRect(x: 0, y: 0, width: 70, height: 24)
                    view?.layer.cornerRadius = 8
                    view?.backgroundColor = UIColor.black.withAlphaComponent(0.55)
                }
                view?.isDraggable = false
                let label = view?.subviews.compactMap { $0 as? UILabel }.first
                if let label = label {
                    label.text = pointAnn.title ?? ""
                    label.font = .systemFont(ofSize: max(6, CGFloat(segmentLabelFontSizePx)), weight: .bold)
                } else {
                    let lbl = UILabel(frame: CGRect(x: 0, y: 0, width: 70, height: 24))
                    lbl.textAlignment = .center
                    lbl.font = .systemFont(ofSize: max(6, CGFloat(segmentLabelFontSizePx)), weight: .bold)
                    lbl.textColor = .white
                    lbl.text = pointAnn.title ?? ""
                    view?.addSubview(lbl)
                }
                return view
            }

            let id = "SketchPoint"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
            let markerSize = max(18, min(36, CGFloat(segmentLabelFontSizePx) + 8))
            let labelSize = min(max(6, CGFloat(segmentLabelFontSizePx)), markerSize * 0.58)
            if view == nil {
                view = MLNAnnotationView(reuseIdentifier: id)
                view?.frame = CGRect(x: 0, y: 0, width: markerSize, height: markerSize)
                view?.layer.cornerRadius = markerSize / 2
                view?.backgroundColor = pointMarkerStyle.fillColor
                view?.layer.borderWidth = 1
                view?.layer.borderColor = pointMarkerStyle.borderColor.cgColor
            } else {
                view?.frame = CGRect(x: 0, y: 0, width: markerSize, height: markerSize)
                view?.layer.cornerRadius = markerSize / 2
            }
            view?.isDraggable = isEditMode
            let label = view?.subviews.compactMap { $0 as? UILabel }.first
            if let label = label {
                label.text = pointAnn.title ?? ""
                label.frame = CGRect(x: 0, y: 0, width: markerSize, height: markerSize)
                label.font = .systemFont(ofSize: labelSize, weight: .bold)
                label.textColor = pointMarkerStyle.textColor
                label.layer.shadowColor = pointMarkerStyle.textStrokeColor.cgColor
                label.layer.shadowOpacity = 0.95
                label.layer.shadowRadius = 1
                label.layer.shadowOffset = .zero
            } else {
                let lbl = UILabel(frame: CGRect(x: 0, y: 0, width: markerSize, height: markerSize))
                lbl.textAlignment = .center
                lbl.font = .systemFont(ofSize: labelSize, weight: .bold)
                lbl.textColor = pointMarkerStyle.textColor
                lbl.text = pointAnn.title ?? ""
                lbl.layer.shadowColor = pointMarkerStyle.textStrokeColor.cgColor
                lbl.layer.shadowOpacity = 0.95
                lbl.layer.shadowRadius = 1
                lbl.layer.shadowOffset = .zero
                view?.addSubview(lbl)
            }
            // Selektions-Hervorhebung: ausgewählter Punkt grün.
            if let idxAnn = annotation as? IndexedPointAnnotation, let selectedIndex, idxAnn.index == selectedIndex {
                view?.backgroundColor = .systemGreen
                view?.layer.borderWidth = 2
                view?.layer.borderColor = UIColor.white.cgColor
            } else {
                view?.backgroundColor = pointMarkerStyle.fillColor
                view?.layer.borderWidth = 1
                view?.layer.borderColor = pointMarkerStyle.borderColor.cgColor
            }
            return view
        }
    }
}
