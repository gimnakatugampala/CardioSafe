import Foundation
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

enum AccountDeletionError: LocalizedError {
    case signIn, staff, activeSOS, ownerChanged
    var errorDescription: String? {
        switch self {
        case .signIn: "Sign in again with your patient account before deleting it."
        case .staff: "Hospital staff accounts require administrator-managed removal."
        case .activeSOS: "Complete or cancel your active SOS before deleting this account."
        case .ownerChanged: "The signed-in account changed. Deletion was stopped."
        }
    }
}
@MainActor protocol AccountDeleting {
    func verify(password: String) async throws -> String
    func checkSOS(owner: String) async throws
    func deleteCloud(owner: String) async throws
    func deleteLocal(owner: String) async throws
    func deleteIdentity(owner: String) async throws
    func clearDatabaseCache() async -> String?
}
@MainActor struct FirebaseAccountDeletionService: AccountDeleting {
    private func user(_ owner: String? = nil) throws -> User {
        guard let user = Auth.auth().currentUser else { throw AccountDeletionError.signIn }
        if let owner, user.uid != owner { throw AccountDeletionError.ownerChanged }
        return user
    }
    func verify(password: String) async throws -> String {
        let current = try user()
        let token = try await current.getIDTokenResult(forcingRefresh: true)
        guard token.claims["role"] as? String != "staff" else { throw AccountDeletionError.staff }
        guard let email = current.email, !password.isEmpty else { throw AccountDeletionError.signIn }
        try await current.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: password))
        _ = try user(current.uid)
        return current.uid
    }
    func checkSOS(owner: String) async throws {
        _ = try user(owner)
        if let saved = try await CloudSOSRecovery().load(owner: owner) {
            let snapshot = try await Firestore.firestore().collection("hospitals").document(saved.destination.hospitalID)
                .collection("sosRequests").document(saved.requestID).getDocument(source: .server)
            guard !snapshot.exists || ["cancelled", "completed"].contains(snapshot.data()?["status"] as? String ?? "") else {
                throw AccountDeletionError.activeSOS
            }
        }
    }
    func deleteCloud(owner: String) async throws {
        let db = Firestore.firestore()
        let marker = db.collection("users").document(owner).collection("deletion").document("status")
        let active = db.collection("users").document(owner).collection("activeSOS").document("current")
        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                if try transaction.getDocument(marker).exists { return nil }
                let recovery = try transaction.getDocument(active)
                if let bytes = recovery.data()?["payload"] as? Data {
                    let saved = try JSONDecoder().decode(SavedSOS.self, from: bytes)
                    let request = db.collection("hospitals").document(saved.destination.hospitalID).collection("sosRequests").document(saved.requestID)
                    let status = try transaction.getDocument(request)
                    if status.exists && !["cancelled", "completed"].contains(status.data()?["status"] as? String ?? "") {
                        errorPointer?.pointee = NSError(domain: "CardioSafeActiveSOS", code: 409, userInfo: [NSLocalizedDescriptionKey: "Complete or cancel your SOS before deleting the account."])
                        return nil
                    }
                }
                transaction.setData(["startedAt": FieldValue.serverTimestamp()], forDocument: marker)
                return nil
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        for name in ["records", "recordChunks", "activeSOS"] {
            let collection = db.collection("users").document(owner).collection(name)
            while true {
                _ = try user(owner)
                let snapshot = try await collection.limit(to: 200).getDocuments(source: .server)
                if snapshot.documents.isEmpty { break }
                let batch = db.batch()
                for document in snapshot.documents { batch.deleteDocument(document.reference) }
                try await batch.commit()
            }
        }
    }
    func deleteLocal(owner: String) async throws {
        _ = try user(owner)
        try await CoreDataWalkingPlanStore().deletePlan(for: owner)
        try await CoreDataWalkingSessionStore().deleteSessions(for: owner)
        try AccountLocalDataCleaner.clear(owner: owner)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().filter { $0.content.userInfo["ownerID"] as? String == owner }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
        let delivered = await center.deliveredNotifications().filter { $0.request.content.userInfo["ownerID"] as? String == owner }
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier })
    }
    func deleteIdentity(owner: String) async throws { try await user(owner).delete() }
    func clearDatabaseCache() async -> String? {
        UserDefaults.standard.set(true, forKey: "clearFirestoreAfterDeletion")
        do {
            try await Firestore.firestore().terminate()
            try await Firestore.firestore().clearPersistence()
            UserDefaults.standard.removeObject(forKey: "clearFirestoreAfterDeletion")
            return nil
        } catch { return "Account deleted. Device database cleanup will retry when CardioSafe restarts." }
    }
}

@MainActor enum AccountLocalDataCleaner {
    static func clear(owner: String, root: URL = .applicationSupportDirectory) throws {
        guard !owner.isEmpty, owner != "guest", owner != "local-device" else { throw AccountDeletionError.signIn }
        let name = Data(owner.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        let paths = ["AccountSync/\(name)", "PatientProfiles/\(name).json", "ActiveSOS/\(name).json", "WalkingRecovery/\(name).json", "SOSHistory/\(name)"]
        for path in paths {
            let url = root.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
    static func removePDFs(owner: String, cache suppliedCache: AccountSyncCache? = nil) throws -> Int {
        let cache = suppliedCache ?? .shared
        let directory = cache.folder(owner).appendingPathComponent("ScannedDocuments")
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "pdf" }
        for file in files { try FileManager.default.removeItem(at: file) }
        return files.count
    }
}
