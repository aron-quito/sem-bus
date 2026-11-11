import Foundation
import CoreLocation
import Combine

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var cachedCoordinate: CLLocationCoordinate2D?

    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var heading: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isAuthorized: Bool = false

    /// Coordenada central de Tacna como punto de referencia
    static let defaultTacnaCoordinate = CLLocationCoordinate2D(latitude: -18.0135, longitude: -70.2519)

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3.0
        self.authorizationStatus = manager.authorizationStatus
        self.isAuthorized = (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways)
    }

    func requestPermissionAndStart() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }

    func startUpdating() {
        if isAuthorized {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// Devuelve la coordenada del usuario si se encuentra en Tacna, o el centro de Tacna como fallback (Thread-safe)
    var effectiveCoordinate: CLLocationCoordinate2D {
        lock.lock()
        let coord = cachedCoordinate
        lock.unlock()

        if let coord = coord, isWithinTacna(coord) {
            return coord
        }
        return coord ?? Self.defaultTacnaCoordinate
    }

    var isUserPhysicallyInTacna: Bool {
        lock.lock()
        let coord = cachedCoordinate
        lock.unlock()
        guard let coord = coord else { return false }
        return isWithinTacna(coord)
    }

    private func isWithinTacna(_ coord: CLLocationCoordinate2D) -> Bool {
        return coord.latitude < -17.5 && coord.latitude > -18.5 && coord.longitude < -70.0 && coord.longitude > -70.6
    }

    // MARK: - CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let authorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
        DispatchQueue.main.async {
            self.authorizationStatus = status
            self.isAuthorized = authorized
        }
        if authorized {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        lock.lock()
        cachedCoordinate = latest.coordinate
        lock.unlock()

        DispatchQueue.main.async {
            self.userCoordinate = latest.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 {
            let val = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
            DispatchQueue.main.async {
                self.heading = val
            }
        }
    }
}
