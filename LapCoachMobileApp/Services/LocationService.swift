import CoreLocation
import Foundation

protocol LocationServiceType: AnyObject {
    var onLocationUpdate: ((LocationSnapshot) -> Void)? { get set }
    var onAuthorizationChange: ((GPSAuthorizationState) -> Void)? { get set }
    func requestAuthorization()
    func start()
    func stop()
}

final class LocationService: NSObject, LocationServiceType, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var onLocationUpdate: ((LocationSnapshot) -> Void)?
    var onAuthorizationChange: ((GPSAuthorizationState) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
        locationManagerDidChangeAuthorization(manager)
    }

    func start() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let state: GPSAuthorizationState
        switch manager.authorizationStatus {
        case .authorizedAlways:
            state = .authorizedAlways
        case .authorizedWhenInUse:
            state = .authorizedWhenInUse
        case .denied:
            state = .denied
        case .restricted:
            state = .restricted
        case .notDetermined:
            state = .unknown
        @unknown default:
            state = .unknown
        }
        onAuthorizationChange?(state)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let snapshot = LocationSnapshot(
            timestampMs: Int64(location.timestamp.timeIntervalSince1970 * 1_000.0),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speedMps: max(location.speed, 0.0),
            headingDeg: location.course >= 0 ? location.course : 0.0,
            horizontalAccuracy: location.horizontalAccuracy
        )
        onLocationUpdate?(snapshot)
    }
}
