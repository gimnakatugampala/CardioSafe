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
    func create(destination: DispatchDestination) async throws
    func restore() async throws -> RestoredSOS?
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

    private let journal: any SOSJournaling
    private var confirmedTerminalID: String?
    init(journal: (any SOSJournaling)? = nil) { self.journal = journal ?? FileSOSJournal() }

    private func document(for saved: SavedSOS) -> DocumentReference {
        Firestore.firestore().collection("hospitals").document(saved.destination.hospitalID)
            .collection("sosRequests").document(saved.requestID)
    }
    private func payload(ownerID: String) -> [String: Any] {
        ["patientID": ownerID, "status": "pending", "isSimulation": true,
         "createdAt": FieldValue.serverTimestamp(), "updatedAt": FieldValue.serverTimestamp(), "updatedBy": ownerID]
    }
    func create(destination: DispatchDestination) async throws {
        guard let user = Auth.auth().currentUser else { throw DispatchSelectionError.signIn }
        if let previous = try journal.load(ownerID: user.uid), previous.requestID != confirmedTerminalID {
            throw DispatchSelectionError.unavailable
        }
        let ref = Firestore.firestore().collection("hospitals").document(destination.hospitalID)
            .collection("sosRequests").document()
        let saved = SavedSOS(ownerID: user.uid, requestID: ref.documentID, destination: destination)
        // Persist the ID before submitting: a crash or lost acknowledgement retries this same ID.
        try journal.save(saved)
        confirmedTerminalID = nil
        reference = ref
        try await ref.setData(payload(ownerID: user.uid))
        guard Auth.auth().currentUser?.uid == saved.ownerID else { throw DispatchSelectionError.signIn }
    }

    func restore() async throws -> RestoredSOS? {
        guard let user = Auth.auth().currentUser else { throw DispatchSelectionError.signIn }
        guard let saved = try journal.load(ownerID: user.uid) else { return nil }
        let ref = document(for: saved)
        reference = ref
        var snapshot: DocumentSnapshot
        do {
            snapshot = try await ref.getDocument(source: .server)
        } catch {
            // A saved submission intent may have died before the create reached Firebase.
            // Reusing its ID is safe: existing documents cannot have createdAt overwritten.
            guard (error as NSError).code == FirestoreErrorCode.permissionDenied.rawValue else { throw error }
            try await ref.setData(payload(ownerID: saved.ownerID))
            snapshot = try await ref.getDocument(source: .server)
        }
        if !snapshot.exists {
            try await ref.setData(payload(ownerID: saved.ownerID))
            snapshot = try await ref.getDocument(source: .server)
        }
        guard !snapshot.metadata.isFromCache, !snapshot.metadata.hasPendingWrites,
              Auth.auth().currentUser?.uid == saved.ownerID,
              let data = snapshot.data(), data["patientID"] as? String == saved.ownerID,
              data["isSimulation"] as? Bool == true, let status = data["status"] as? String,
              ["pending", "accepted", "assigned", "cancelled", "completed"].contains(status) else {
            throw DispatchSelectionError.unavailable
        }
        assignedAt = (data["assignedAt"] as? Timestamp)?.dateValue()
        confirmedTerminalID = ["cancelled", "completed"].contains(status) ? saved.requestID : nil
        return RestoredSOS(saved: saved, status: status, assignedAt: assignedAt)
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
                if ["cancelled", "completed"].contains(status) { self?.confirmedTerminalID = reference.documentID }
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
