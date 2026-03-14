import Foundation
import CoreLocation

class MeasurementViewModel: ObservableObject {
    @Published var currentMeasurement: Measurement?
    @Published var points: [PhotoPoint] = []
    @Published var totalDistance: Double = 0

    func addPoint(x: Double, y: Double, distance: Double) {
        let point = PhotoPoint(x: x, y: y, distance: distance)
        points.append(point)
        totalDistance += distance
    }

    func createMeasurement(imagePath: String, latitude: Double, longitude: Double, address: String) -> Measurement {
        Measurement(
            imagePath: imagePath,
            latitude: latitude,
            longitude: longitude,
            address: address,
            points: points,
            totalDistance: totalDistance,
            referenceMeters: nil,
            date: Date()
        )
    }

    func reset() {
        points = []
        totalDistance = 0
        currentMeasurement = nil
    }
}
