import CoreLocation
import Foundation

/// One-shot CoreLocation fix for the station. If macOS won't grant location
/// to a command-line build, Settings offers manual coordinates instead.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var status: String = "Not requested"

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        status = "Requesting…"
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        manager.stopUpdatingLocation()
        DispatchQueue.main.async {
            self.coordinate = loc.coordinate
            self.status = "Locked"
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            if self.coordinate == nil {
                self.status = "Unavailable — set manual coordinates in Settings"
            }
        }
    }
}
