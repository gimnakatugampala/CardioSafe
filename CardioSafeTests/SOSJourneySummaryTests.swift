import Foundation
import Testing
@testable import CardioSafe

@MainActor struct SOSJourneySummaryTests {
    @Test func completedSummaryReopensWithoutDuplicatesAndIsAccountIsolated() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SOSJourneySummaryStore(root: folder)
        let summary = SOSJourneySummary(id: "request123", hospital: "Test hospital", assignedAt: .now, pickedUpAt: .now, completedAt: .now)
        try store.save(summary, ownerID: "patient-one")
        try store.save(summary, ownerID: "patient-one")
        let reopened = try store.load(ownerID: "patient-one")
        #expect(reopened.count == 1 && reopened[0].hospital == "Test hospital")
        #expect(try store.load(ownerID: "patient-two").isEmpty)
    }
    @Test func newJourneyStagesRemainActiveAcrossRestart() {
        let destination = DispatchDestination(hospitalID: "demo-asiri-central", name: "Test hospital", distanceMetres: 100, reportedWaiting: nil, reason: "Test", locationDescription: "Sample location")
        let saved = SavedSOS(ownerID: "patient", requestID: "request123", destination: destination)
        for status in ["patient_arrived", "transporting", "hospital_arrived"] {
            #expect(RestoredSOS(saved: saved, status: status, assignedAt: .now, pickedUpAt: .now).isActive)
        }
        #expect(!RestoredSOS(saved: saved, status: "completed", assignedAt: .now).isActive)
    }
}
