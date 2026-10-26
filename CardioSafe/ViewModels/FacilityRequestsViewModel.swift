import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

@MainActor @Observable
final class FacilityRequestsViewModel {
    private(set) var requests: [SOSRequest] = []
    private(set) var errorMessage: String?
    private(set) var completedRequestID: String?
    private(set) var savingID: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var listener: ListenerRegistration?

    func listen(hospitalID: String) {
        stop()
        let expectedGeneration = generation
        listener = Firestore.firestore().collection("hospitals").document(hospitalID)
            .collection("sosRequests").whereField("status", in: ["pending", "accepted", "assigned"])
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.generation == expectedGeneration else { return }
                    if error != nil { self.errorMessage = "Requests could not be loaded. Check your connection."; return }
                    self.errorMessage = nil
                    self.requests = (snapshot?.documents ?? []).compactMap { doc in
                        let data = doc.data()
                        guard data["isSimulation"] as? Bool == true, let status = data["status"] as? String else { return nil }
                        return SOSRequest(id: doc.documentID, status: status, createdAt: (data["createdAt"] as? Timestamp)?.dateValue(), assignedAt: (data["assignedAt"] as? Timestamp)?.dateValue())
                    }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
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

    func complete(_ request: SOSRequest, hospitalID: String) async {
        guard let assignedAt = request.assignedAt,
              AmbulanceJourney.progress(assignedAt: assignedAt, now: .now) >= 1 else { return }
        await update(request, hospitalID: hospitalID, status: "completed")
    }

    private func update(_ request: SOSRequest, hospitalID: String, status: String) async {
        guard savingID == nil, let uid = Auth.auth().currentUser?.uid else { return }
        savingID = request.id
        defer { savingID = nil }
        let ref = Firestore.firestore().collection("hospitals").document(hospitalID).collection("sosRequests").document(request.id)
        do {
            // Rules validate each transition against the current server document.
            var fields: [String: Any] = ["status": status, "updatedAt": FieldValue.serverTimestamp(), "updatedBy": uid]
            if status == "assigned" { fields["assignedAt"] = FieldValue.serverTimestamp() }
            if status == "completed" { fields["completedAt"] = FieldValue.serverTimestamp() }
            try await ref.updateData(fields)
            if status == "completed" { completedRequestID = request.id }
            errorMessage = nil
        } catch { errorMessage = "The update was not confirmed. The request may have changed or been cancelled. Refresh and try again." }
    }
}
