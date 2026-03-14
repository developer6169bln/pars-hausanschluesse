import CoreLocation

class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var location: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func getAddress(from location: CLLocation,
                    completion: @escaping (String) -> Void) {
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            if let p = placemarks?.first {
                let street = p.thoroughfare ?? ""
                let number = p.subThoroughfare ?? ""
                let city = p.locality ?? ""
                completion("\(street) \(number), \(city)")
            } else {
                completion("")
            }
        }
    }
}
