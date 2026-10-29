import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

@MainActor
protocol FacilityRequestWriting {
    func update(hospitalID: String, requestID: String, fields: [String: Any]) async throws
}

@MainActor
struct FirebaseFacilityRequestWriter: FacilityRequestWriting {
    func update(hospitalID: String, requestID: String, fields: [String: Any]) async throws {
        try await Firestore.firestore().collection("hospitals").document(hospitalID)
            .collection("sosRequests").document(requestID).updateData(fields)
    }
}

@MainActor @Observable
final class FacilityRequestsViewModel {
    private(set) var isLoading = false
    private(set) var isCached = false
    private(set) var requests: [SOSRequest] = []
    private(set) var errorMessage: String?
    private(set) var completedRequestID: String?
    private(set) var savingID: String?
    private(set) var actionRequestID: String?
    private(set) var actionMessage: String?
    private(set) var actionFailed = false
    @ObservationIgnored private let writer: any FacilityRequestWriting
    @ObservationIgnored private let currentUID: () -> String?
    init(writer: (any FacilityRequestWriting)? = nil, currentUID: (() -> String?)? = nil) {
        self.writer = writer ?? FirebaseFacilityRequestWriter()
        self.currentUID = currentUID ?? { Auth.auth().currentUser?.uid }
    }
    private func report(_ message: String, requestID: String, failed: Bool) {
        actionRequestID = requestID; actionMessage = message; actionFailed = failed
    }
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var listener: ListenerRegistration?

    func listen(hospitalID: String) {
        stop()
        requests = []; errorMessage = nil; isLoading = true
        let expectedGeneration = generation
        listener = Firestore.firestore().collection("hospitals").document(hospitalID)
            .collection("sosRequests").whereField("status", in: ["pending", "accepted", "assigned", "patient_arrived", "transporting", "hospital_arrived"])
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.generation == expectedGeneration else { return }
                    self.isLoading = false
                    self.isCached = snapshot?.metadata.isFromCache ?? false
                    if error != nil { self.errorMessage = "Requests could not be loaded. Check your connection."; return }
                    guard snapshot?.metadata.hasPendingWrites != true else { return }
                    self.errorMessage = nil
                    self.requests = (snapshot?.documents ?? []).compactMap { doc in
                        let data = doc.data()
                        guard data["isSimulation"] as? Bool == true, let status = data["status"] as? String else { return nil }
                        return SOSRequest(id: doc.documentID, status: status, createdAt: (data["createdAt"] as? Timestamp)?.dateValue(), assignedAt: (data["assignedAt"] as? Timestamp)?.dateValue(), pickedUpAt: (data["pickedUpAt"] as? Timestamp)?.dateValue())
                    }.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                }
            }
    }
    func stop() { generation = UUID(); listener?.remove(); listener = nil }

    func accept(_ request: SOSRequest, hospitalID: String) async {
        await update(request, hospitalID: hospitalID, status: "accepted")
    }

    func assign(_ request: SOSRequest, hospitalID: String) async {
        await update(request, hospitalID: hospitalID, status: "assigned")
    }

    func advance(_ request: SOSRequest, hospitalID: String) async {
        guard let current = SOSJourneyStatus(rawValue: request.status), let next = current.next else {
            report("This request has no further action. Refresh the inbox.", requestID: request.id, failed: true); return
        }
        if current == .assigned {
            guard let date = request.assignedAt, AmbulanceJourney.progress(assignedAt: date, now: .now) >= 1 else {
                report("Wait until the 90-second pickup journey finishes, then confirm arrival.", requestID: request.id, failed: true); return
            }
        }
        if current == .transporting {
            guard let date = request.pickedUpAt, AmbulanceJourney.progress(assignedAt: date, now: .now) >= 1 else {
                report("Wait until the 90-second hospital journey finishes, then confirm arrival.", requestID: request.id, failed: true); return
            }
        }
        await update(request, hospitalID: hospitalID, status: next.rawValue)
    }

    private func update(_ request: SOSRequest, hospitalID: String, status: String) async {
        guard savingID == nil else { return }
        guard let uid = currentUID() else {
            report("Sign in again with your hospital staff account.", requestID: request.id, failed: true); return
        }
        report("Confirming with Firebase…", requestID: request.id, failed: false)
        savingID = request.id
        defer { savingID = nil }
        do {
            // Rules validate each transition against the current server document.
            var fields: [String: Any] = ["status": status, "updatedAt": FieldValue.serverTimestamp(), "updatedBy": uid]
            if let timestamp = SOSJourneyStatus(rawValue: status)?.timestamp { fields[timestamp] = FieldValue.serverTimestamp() }
            try await writer.update(hospitalID: hospitalID, requestID: request.id, fields: fields)
            if status == "completed" { completedRequestID = request.id }
            errorMessage = nil
            report("Confirmed: \(SOSJourneyStatus(rawValue: status)?.title ?? status)", requestID: request.id, failed: false)
        } catch {
            let code = (error as NSError).code
            let message: String
            switch code {
            case FirestoreErrorCode.permissionDenied.rawValue:
                message = "Firebase rejected this step. Check that the new journey rules were published in cardio-safe and this account still has verified staff access. Refresh the inbox before retrying."
            case FirestoreErrorCode.unauthenticated.rawValue:
                message = "Your staff session expired. Sign out and sign in again."
            case FirestoreErrorCode.unavailable.rawValue:
                message = "Firebase is unavailable. Check the connection and retry."
            default:
                message = "Firebase did not confirm the update (code \(code)). Refresh this request and retry."
            }
            report(message, requestID: request.id, failed: true)
        }
    }
}
