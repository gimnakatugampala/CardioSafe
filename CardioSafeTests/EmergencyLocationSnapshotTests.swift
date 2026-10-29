import CoreLocation
import Foundation
import Testing
@testable import CardioSafe

struct EmergencyLocationSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fix(age: TimeInterval, accuracy: Double = 18) -> CLLocation {
        CLLocation(coordinate: .init(latitude: 6.9271, longitude: 79.8612), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-age))
    }
    @Test func locationBecomesStaleWithoutChangingCoordinates() throws {
        let recent = try #require(EmergencyLocationSnapshot(location: fix(age: 10), now: now))
        let stale = try #require(EmergencyLocationSnapshot(location: fix(age: 10), now: now.addingTimeInterval(25)))
        #expect(recent.isFresh && recent.accuracyMetres == 18)
        #expect(!stale.isFresh && stale.ageSeconds == 35)
        #expect(recent.latitude == stale.latitude && recent.longitude == stale.longitude)
    }
    @Test func rejectsInvalidAccuracyAndFutureFixes() {
        #expect(EmergencyLocationSnapshot(location: fix(age: 0, accuracy: -1), now: now) == nil)
        #expect(EmergencyLocationSnapshot(location: fix(age: 0, accuracy: .infinity), now: now) == nil)
        #expect(EmergencyLocationSnapshot(location: fix(age: -60), now: now) == nil)
    }
    @Test func toleratesSmallClockSkewWithoutNegativeAge() throws {
        let snapshot = try #require(EmergencyLocationSnapshot(location: fix(age: -2), now: now))
        #expect(snapshot.ageSeconds == 0 && snapshot.isFresh)
    }
}
