import CoreLocation
import Foundation

struct EmergencyLocationSnapshot {
    let latitude: Double
    let longitude: Double
    let accuracyMetres: Double
    let ageSeconds: Int
    var isFresh: Bool { ageSeconds <= 30 }

    init?(location: CLLocation, now: Date) {
        let age = now.timeIntervalSince(location.timestamp)
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy.isFinite, location.horizontalAccuracy >= 0,
              age.isFinite, age >= -5, age < Double(Int.max) else { return nil }
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        accuracyMetres = location.horizontalAccuracy
        ageSeconds = Int(max(0, age).rounded(.up))
    }
}
