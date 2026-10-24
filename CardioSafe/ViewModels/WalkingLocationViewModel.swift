import CoreLocation
import Observation

@MainActor
@Observable
final class WalkingLocationViewModel: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var errorMessage: String?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var wantsUpdates = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        authorization = manager.authorizationStatus
    }

    func start() {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        wantsUpdates = true
        authorization = manager.authorizationStatus
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { updateAuthorization() }
    }

    func stop() {
        wantsUpdates = false
        manager.stopUpdatingLocation()
        location = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        updateAuthorization()
    }

    private func updateAuthorization() {
        switch authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            if wantsUpdates { manager.startUpdatingLocation() }
        case .denied, .restricted:
            location = nil
            errorMessage = "Location access is off. Your walking timer still works."
            manager.stopUpdatingLocation()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0,
              abs(latest.timestamp.timeIntervalSinceNow) < 30 else { return }
        location = latest
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { return }
        errorMessage = "Your location is unavailable. The walking timer is still running."
    }
}
