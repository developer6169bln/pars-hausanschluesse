import SwiftUI
import MapKit

struct ProjectMiniMapView: View {
    let route: [CLLocationCoordinate2D]
    let projectId: UUID
    @EnvironmentObject var viewModel: MapViewModel
    @State private var region: MKCoordinateRegion = .init()
    @State private var snapshotImage: UIImage?
    @State private var isSavingSnapshot = false

    var body: some View {
        VStack(spacing: 8) {
            Map(position: .region(region)) {
                if route.count >= 2 {
                    let polyline = MKPolyline(coordinates: route, count: route.count)
                    MapPolyline(polyline)
                        .stroke(.blue, lineWidth: 3)
                }
                if let first = route.first {
                    Annotation("Start", coordinate: first) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                if let last = route.last {
                    Annotation("Ende", coordinate: last) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear {
                if let first = route.first {
                    region = MKCoordinateRegion(center: first,
                                                span: MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0015))
                }
            }

            HStack {
                Spacer()
                Button {
                    createAndSaveSnapshot()
                } label: {
                    if isSavingSnapshot {
                        ProgressView()
                    } else {
                        Label("Kartenfoto im Projekt speichern", systemImage: "square.and.arrow.down")
                    }
                }
                .font(.footnote)
            }
        }
        .padding([.horizontal, .bottom])
    }

    private func createAndSaveSnapshot() {
        guard !route.isEmpty else { return }
        isSavingSnapshot = true

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 600, height: 400)
        options.showsBuildings = true
        options.showsPointsOfInterest = false

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { result, error in
            DispatchQueue.main.async {
                isSavingSnapshot = false
            }
            guard let snap = result, error == nil else { return }

            let image = snap.image
            let storage = StorageService()
            guard let path = storage.saveImage(image) else { return }

            // Kartenfoto als eigene "Messung" im Projekt ablegen (ohne Punkte, nur Bild).
            DispatchQueue.main.async {
                guard let project = viewModel.project(byId: projectId) else { return }
                let nextIndex = project.measurements.count + 1
                let m = Measurement(
                    id: UUID(),
                    imagePath: path,
                    latitude: route.first?.latitude ?? 0,
                    longitude: route.first?.longitude ?? 0,
                    address: "Kartenübersicht",
                    points: [],
                    totalDistance: 0,
                    referenceMeters: nil,
                    index: nextIndex,
                    startLatitude: route.first?.latitude,
                    startLongitude: route.first?.longitude,
                    endLatitude: route.last?.latitude,
                    endLongitude: route.last?.longitude,
                    date: Date()
                )
                viewModel.addMeasurement(toProjectId: projectId, m)
            }
        }
    }
}

