import Testing
@testable import CardioSafe

struct SOSJourneyStatusTests {
    @Test func crewMustFollowTheWholeJourney() {
        var stage = SOSJourneyStatus.pending
        var path: [SOSJourneyStatus] = [stage]
        while let next = stage.next { path.append(next); stage = next }
        #expect(path == [.pending, .accepted, .assigned, .patientArrived, .transporting, .hospitalArrived, .completed])
        #expect(SOSJourneyStatus.cancelled.next == nil)
    }
    @Test func eachMilestoneHasItsOwnTimestamp() {
        #expect(SOSJourneyStatus.patientArrived.timestamp == "patientArrivedAt")
        #expect(SOSJourneyStatus.transporting.timestamp == "pickedUpAt")
        #expect(SOSJourneyStatus.hospitalArrived.timestamp == "hospitalArrivedAt")
        #expect(SOSJourneyStatus.completed.timestamp == "completedAt")
        #expect(SOSJourneyStatus.hospitalArrived.active)
        #expect(!SOSJourneyStatus.completed.active)
    }
}
