import Foundation
import FirebaseAuth
import FirebaseFirestore

struct SOSRequest: Identifiable {
    let id: String
    let status: String
    let createdAt: Date?
    var assignedAt: Date? = nil
    var pickedUpAt: Date? = nil
}

@MainActor
protocol SOSRequestServicing {
    var assignedAt: Date? { get }
    var pickedUpAt: Date? { get }
    var summaryWarning: String? { get }
    func create(destination: DispatchDestination) async throws
    func restore() async throws -> RestoredSOS?
    func observe(_ receive: @escaping (Result<String, Error>) -> Void)
    func cancel() async throws
    func stop()
}

extension SOSRequestServicing {
    var pickedUpAt: Date? { nil }
    var summaryWarning: String? { nil }
}

@MainActor
final class SOSRequestService: SOSRequestServicing {
    private(set) var summaryWarning: String?
    private(set) var pickedUpAt: Date?
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
        try await CloudSOSRecovery().reserve(saved)
        // Persist the ID before submitting: a crash or lost acknowledgement retries this same ID.
        try journal.save(saved)
        confirmedTerminalID = nil
        reference = ref
        try await ref.setData(payload(ownerID: user.uid))
        guard Auth.auth().currentUser?.uid == saved.ownerID else { throw DispatchSelectionError.signIn }
    }

    func restore() async throws -> RestoredSOS? {
        guard let user = Auth.auth().currentUser else { throw DispatchSelectionError.signIn }
        let cloud = try await CloudSOSRecovery().load(owner: user.uid)
        if let cloud { try journal.save(cloud) }
        guard let saved = try cloud ?? journal.load(ownerID: user.uid) else { return nil }
        if cloud == nil { try await CloudSOSRecovery().reserve(saved) }
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
              SOSJourneyStatus(rawValue: status) != nil else {
            throw DispatchSelectionError.unavailable
        }
        pickedUpAt = (data["pickedUpAt"] as? Timestamp)?.dateValue()
        assignedAt = (data["assignedAt"] as? Timestamp)?.dateValue()
        if status == "completed" { archive(data: data, ownerID: saved.ownerID) }
        confirmedTerminalID = ["cancelled", "completed"].contains(status) ? saved.requestID : nil
        return RestoredSOS(saved: saved, status: status, assignedAt: assignedAt, pickedUpAt: pickedUpAt)
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
                self?.pickedUpAt = (snapshot.data()?["pickedUpAt"] as? Timestamp)?.dateValue()
                self?.assignedAt = (snapshot.data()?["assignedAt"] as? Timestamp)?.dateValue()
                if status == "completed", let owner, let data = snapshot.data() { self?.archive(data: data, ownerID: owner) }
                receive(.success(status))
            }
        }
    }

    private func archive(data: [String: Any], ownerID: String) {
        do {
            guard let saved = try journal.load(ownerID: ownerID),
                  let completedAt = (data["completedAt"] as? Timestamp)?.dateValue() else { return }
            try SOSJourneySummaryStore().save(SOSJourneySummary(id: saved.requestID, hospital: saved.destination.name,
                assignedAt: (data["assignedAt"] as? Timestamp)?.dateValue(), pickedUpAt: (data["pickedUpAt"] as? Timestamp)?.dateValue(),
                completedAt: completedAt), ownerID: ownerID)
            summaryWarning = nil
        } catch { summaryWarning = "Handover is complete, but the local summary couldn’t be saved. Reopen this request to retry." }
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
