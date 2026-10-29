import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
struct CloudSOSRecovery {
    private func reference(_ owner: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(owner).collection("activeSOS").document("current")
    }
    func load(owner: String) async throws -> SavedSOS? {
        guard Auth.auth().currentUser?.uid == owner else { throw DispatchSelectionError.signIn }
        let snapshot = try await reference(owner).getDocument(source: .server)
        guard snapshot.exists else { return nil }
        guard let payload = snapshot.data()?["payload"] as? Data else { throw DispatchSelectionError.unavailable }
        let saved = try JSONDecoder().decode(SavedSOS.self, from: payload)
        guard saved.ownerID == owner, saved.destination.hospitalID == "demo-asiri-central",
              !saved.requestID.isEmpty, saved.requestID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw DispatchSelectionError.unavailable }
        return saved
    }
    func reserve(_ saved: SavedSOS) async throws {
        guard Auth.auth().currentUser?.uid == saved.ownerID else { throw DispatchSelectionError.signIn }
        let ref = reference(saved.ownerID)
        let payload = try JSONEncoder().encode(saved)
        _ = try await Firestore.firestore().runTransaction { transaction, errorPointer -> Any? in
            do {
                let existing = try transaction.getDocument(ref)
                if let bytes = existing.data()?["payload"] as? Data {
                    let previous = try JSONDecoder().decode(SavedSOS.self, from: bytes)
                    if previous.requestID == saved.requestID { return nil }
                    let request = Firestore.firestore().collection("hospitals").document(previous.destination.hospitalID)
                        .collection("sosRequests").document(previous.requestID)
                    let previousState = try transaction.getDocument(request).data()?["status"] as? String
                    guard previousState == "completed" || previousState == "cancelled" else {
                        errorPointer?.pointee = NSError(domain: "CardioSafeActiveSOS", code: 409,
                            userInfo: [NSLocalizedDescriptionKey: "An SOS is already active on your account. Reopen SOS to restore it."])
                        return nil
                    }
                }
                transaction.setData(["payload": payload, "updatedAt": FieldValue.serverTimestamp()], forDocument: ref)
                return nil
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
    }
}
