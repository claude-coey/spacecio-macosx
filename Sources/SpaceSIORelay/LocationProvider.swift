import CoreLocation
import Foundation

/// One-shot CoreLocation fix for the station. If macOS won't grant location
/// to this build, Settings offers manual coordinates instead.
///
/// PRIVACY: the station only ever attests an APPROXIMATE location — capture
/// uses kilometer accuracy and everything downstream is rounded to ~5 miles
/// (see Station.effectiveCoordinate). We never need or store a precise fix.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var status: String = "Not requested"

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        // Coarse on purpose — the confirmation is rounded to ~5 mi anyway.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        status = "Requesting…"
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    /// Surface the real authorization state — a silently-denied app used to
    /// sit on "Requesting…" forever (each rebuild looks like a new app to
    /// macOS privacy, and a stale decision can stick without re-prompting).
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            switch manager.authorizationStatus {
            case .notDetermined:
                self.status = "Awaiting permission…"
            case .denied, .restricted:
                if self.coordinate == nil {
                    self.status = "Denied — allow in System Settings → Privacy → Location Services, or set manual coordinates"
                }
            default:
                manager.startUpdatingLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        manager.stopUpdatingLocation()
        DispatchQueue.main.async {
            self.coordinate = loc.coordinate
            self.status = "Locked (approx.)"
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
