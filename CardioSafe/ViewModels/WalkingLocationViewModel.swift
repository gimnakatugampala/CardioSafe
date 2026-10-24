import CoreLocation
import Observation

@MainActor
@Observable
final class WalkingLocationViewModel: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var errorMessage: String?
    @ObservationIgnored var onLocation: ((CLLocation) -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var wantsUpdates = false

    init(backgroundUpdates: Bool = false) {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        if backgroundUpdates, (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") == true {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.pausesLocationUpdatesAutomatically = false
        }
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
            errorMessage = "Location access is off. You can continue using the map."
            manager.stopUpdatingLocation()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsUpdates, let latest = locations.last, latest.horizontalAccuracy >= 0,
              abs(latest.timestamp.timeIntervalSinceNow) < 30 else { return }
        location = latest
        errorMessage = nil
        for fix in locations { onLocation?(fix) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { return }
        errorMessage = "Your location is unavailable. You can continue using the map."
    }
}
