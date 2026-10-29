import Foundation
import Testing
import FirebaseFirestore
@testable import CardioSafe

@MainActor private final class RequestWriter: FacilityRequestWriting {
    var fields: [String: Any] = [:]
    var calls = 0
    var failure: Error?
    func update(hospitalID: String, requestID: String, fields: [String: Any]) async throws {
        calls += 1
        if let failure { throw failure }
        self.fields = fields
    }
}
@MainActor struct FacilityRequestActionTests {
    @Test func arrivedAtPatientWritesTheExpectedMilestone() async {
        let writer = RequestWriter()
        let model = FacilityRequestsViewModel(writer: writer, currentUID: { "staff" })
        let request = SOSRequest(id: "request", status: "assigned", createdAt: .now, assignedAt: .now.addingTimeInterval(-100))
        await model.advance(request, hospitalID: "hospital")
        #expect(writer.fields["status"] as? String == "patient_arrived")
        #expect(writer.fields["patientArrivedAt"] != nil)
        #expect(writer.fields["updatedBy"] as? String == "staff")
        #expect(!model.actionFailed && model.actionRequestID == request.id)
        #expect(model.actionMessage == "Confirmed: Arrived at patient")
    }
    @Test func deniedArrivalRemainsVisibleAtTheRequest() async {
        let writer = RequestWriter()
        writer.failure = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.permissionDenied.rawValue)
        let model = FacilityRequestsViewModel(writer: writer, currentUID: { "staff" })
        await model.advance(SOSRequest(id: "request", status: "assigned", createdAt: .now, assignedAt: .now.addingTimeInterval(-100)), hospitalID: "hospital")
        #expect(model.actionFailed)
        #expect(model.actionMessage?.contains("Firebase rejected") == true)
        #expect(model.actionRequestID == "request" && model.savingID == nil)
    }
    @Test func earlyArrivalAndMissingSessionExplainWhyNothingWasWritten() async {
        let writer = RequestWriter()
        let model = FacilityRequestsViewModel(writer: writer, currentUID: { nil })
        await model.advance(SOSRequest(id: "early", status: "assigned", createdAt: .now, assignedAt: .now), hospitalID: "hospital")
        #expect(writer.calls == 0 && model.actionFailed)
        #expect(model.actionMessage?.contains("90-second") == true)
        await model.advance(SOSRequest(id: "signedout", status: "pending", createdAt: .now), hospitalID: "hospital")
        #expect(writer.calls == 0 && model.actionRequestID == "signedout")
        #expect(model.actionMessage?.contains("Sign in again") == true)
    }
}
