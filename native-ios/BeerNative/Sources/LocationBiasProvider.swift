import CoreLocation
import Foundation

/// Fournit un biais de proximité (lat/lon approx.) pour la recherche de lieu
/// OSM/Photon — best-effort : jamais bloquant si refusé/indisponible.
final class LocationBiasProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationBiasProvider()

    @Published private(set) var coordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()
    private var requested = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestOnce() {
        guard !requested else { return }
        requested = true
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Refusé/indisponible : recherche sans biais de proximité, pas bloquant.
    }
}
