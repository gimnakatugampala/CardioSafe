import Foundation
import Testing
@testable import CardioSafe

@MainActor struct SOSArrivalTrackerTests {
    @Test func newFirebaseRequestAlertsOnlyOnce() {
        let start = Date.now
        var tracker = SOSArrivalTracker(startedAt: start)
        let result1 = tracker.shouldAlert(id: "new", createdAt: start.addingTimeInterval(1))
        #expect(result1)
        let result2 = !tracker.shouldAlert(id: "new", createdAt: start.addingTimeInterval(1))
        #expect(result2)
        let result3 = tracker.shouldAlert(id: "another", createdAt: start.addingTimeInterval(2))
        #expect(result3)
    }
    @Test func ignoresBacklogAndWaitsForServerTimestamp() {
        let start = Date.now
        var tracker = SOSArrivalTracker(startedAt: start)
        let result4 = !tracker.shouldAlert(id: "old", createdAt: start.addingTimeInterval(-60))
        #expect(result4)
        let result5 = !tracker.shouldAlert(id: "new", createdAt: nil)
        #expect(result5)
        let result6 = tracker.shouldAlert(id: "new", createdAt: start.addingTimeInterval(1))
        #expect(result6)
    }
}
