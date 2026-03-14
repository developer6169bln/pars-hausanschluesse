import SwiftUI
import MapKit

struct MapView: View {
    @EnvironmentObject var viewModel: MapViewModel

    var body: some View {
        Map {
            ForEach(viewModel.allMeasurements) { m in
                Annotation(m.address,
                           coordinate: CLLocationCoordinate2D(
                            latitude: m.latitude,
                            longitude: m.longitude)) {
                    NavigationLink {
                        MeasurementDetailView(projectId: nil, measurement: m)
                            .environmentObject(viewModel)
                    } label: {
                        Image(systemName: "camera.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        MapView()
            .environmentObject(MapViewModel())
    }
}
