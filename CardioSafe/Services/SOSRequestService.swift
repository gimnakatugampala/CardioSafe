import Foundation
import FirebaseAuth
import FirebaseFirestore

struct SOSRequest: Identifiable {
    let id: String
    let status: String
    let createdAt: Date?
    var assignedAt: Date? = nil
}

@MainActor
protocol SOSRequestServicing {
    var assignedAt: Date? { get }
    func create(hospitalID: String) async throws
    func observe(_ receive: @escaping (Result<String, Error>) -> Void)
    func cancel() async throws
    func stop()
}

@MainActor
final class SOSRequestService: SOSRequestServicing {
    private(set) var assignedAt: Date?
    private var listener: ListenerRegistration?
    private var reference: DocumentReference?
    private var generation = UUID()
    private var authListener: AuthStateDidChangeListenerHandle?

    func create(hospitalID: String) async throws {
        guard let user = Auth.auth().currentUser else { throw DispatchSelectionError.signIn }
        let ref = Firestore.firestore().collection("hospitals").document(hospitalID)
            .collection("sosRequests").document()
        reference = ref
        try await ref.setData([
            "patientID": user.uid, "status": "pending", "isSimulation": true,
            "createdAt": FieldValue.serverTimestamp(), "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": user.uid
        ])
    }

    func observe(_ receive: @escaping (Result<String, Error>) -> Void) {
        stop()
        guard let reference else { return }
        let expectedGeneration = generation
        let owner = Auth.auth().currentUser?.uid
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard user?.uid != owner else { return }
            Task { @MainActor in
                guard self?.generation == expectedGeneration else { return }
                self?.stop()
                receive(.failure(DispatchSelectionError.signIn))
            }
        }
        listener = reference.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            Task { @MainActor in
                guard self?.generation == expectedGeneration else { return }
                if let error { receive(.failure(error)); return }
                guard let snapshot, !snapshot.metadata.hasPendingWrites else { return }
                guard snapshot.exists, let status = snapshot.data()?["status"] as? String else {
                    receive(.failure(DispatchSelectionError.unavailable)); return
                }
                self?.assignedAt = (snapshot.data()?["assignedAt"] as? Timestamp)?.dateValue()
                receive(.success(status))
            }
        }
    }

    func cancel() async throws {
        guard let reference else { return }
        try await reference.updateData(["status": "cancelled", "updatedAt": FieldValue.serverTimestamp(),
                                       "updatedBy": Auth.auth().currentUser?.uid ?? ""])
    }

    func stop() {
        generation = UUID()
        listener?.remove(); listener = nil
        if let authListener { Auth.auth().removeStateDidChangeListener(authListener) }
        authListener = nil
    }
}
