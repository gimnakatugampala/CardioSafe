import Foundation
import Testing
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
@testable import CardioSafe

@MainActor struct DisposableAccountDeletionTests {
    @MainActor final class ObservedBackend: AccountDeleting {
        let service: FirebaseAccountDeletionService
        let database: Firestore
        var verifiedEmpty = false
        init(auth: Auth, database: Firestore) {
            self.database = database
            service = FirebaseAccountDeletionService(auth: auth, database: database)
        }
        func verify(password: String) async throws -> String { try await service.verify(password: password) }
        func checkSOS(owner: String) async throws { try await service.checkSOS(owner: owner) }
        func deleteCloud(owner: String) async throws { try await service.deleteCloud(owner: owner) }
        func deleteLocal(owner: String) async throws { try await service.deleteLocal(owner: owner) }
        func deleteIdentity(owner: String) async throws {
            for name in ["records", "recordChunks"] {
                let records = try await database.collection("users").document(owner).collection(name).getDocuments(source: .server)
                #expect(records.documents.isEmpty)
                guard records.documents.isEmpty else { throw CocoaError(.fileWriteUnknown) }
            }
            let recovery = try await database.collection("users").document(owner).collection("activeSOS").document("current").getDocument(source: .server)
            #expect(!recovery.exists)
            guard !recovery.exists else { throw CocoaError(.fileWriteUnknown) }
            let marker = try await database.collection("users").document(owner).collection("deletion").document("status").getDocument(source: .server)
            #expect(marker.exists)
            let version = UUID().uuidString
            let chunk = database.collection("users").document(owner).collection("recordChunks").document(version + "_0")
            do {
                try await chunk.setData(["bytes": Data("fictional blocked rewrite".utf8), "version": version])
                Issue.record("Deletion marker did not block a new backup chunk")
                throw CocoaError(.fileWriteUnknown)
            } catch {
                #expect((error as NSError).code == FirestoreErrorCode.permissionDenied.rawValue)
                guard (error as NSError).code == FirestoreErrorCode.permissionDenied.rawValue else { throw error }
            }
            verifiedEmpty = true
            try await service.deleteIdentity(owner: owner)
        }
        func clearDatabaseCache() async -> String? { await service.clearDatabaseCache() }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CARDIOSAFE_RUN_DELETE_INTEGRATION"] == "1",
                   "Opt-in: creates and deletes only a uniquely named disposable Firebase account using an isolated Firebase app."))
    func disposablePatientDeletesPrivateDataAndIdentityWithoutChangingExistingSignIn() async throws {
        let originalOwner = Auth.auth().currentUser?.uid
        let options = try #require(FirebaseApp.app()?.options)
        let name = "DeletionCheck-" + UUID().uuidString
        FirebaseApp.configure(name: name, options: options)
        let app = try #require(FirebaseApp.app(name: name))
        let auth = Auth.auth(app: app), database = Firestore.firestore(app: app)
        let email = "cardiosafe-delete-test-" + UUID().uuidString.lowercased() + "@example.invalid"
        let password = UUID().uuidString + "Aa9!"
        let created = try await auth.createUser(withEmail: email, password: password)
        let owner = created.user.uid
        let backend = ObservedBackend(auth: auth, database: database)
        let suite = "deletion-live-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        do {
            let version = UUID().uuidString
            let user = database.collection("users").document(owner)
            let batch = database.batch()
            batch.setData(["bytes": Data("fictional backup".utf8), "version": version],
                          forDocument: user.collection("recordChunks").document(version + "_0"))
            batch.setData(["kind": "profile", "key": "current", "version": version, "parts": 1,
                           "deleted": false, "updatedAt": FieldValue.serverTimestamp()],
                          forDocument: user.collection("records").document("profile_current"))
            try await batch.commit()
            try await verifyDisconnectedClientRecovers(database: database, owner: owner, version: version)
            let folder = AccountSyncCache.shared.folder(owner).appendingPathComponent("ScannedDocuments")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("fictional local PDF".utf8).write(to: folder.appendingPathComponent("test.pdf"))
            let model = AccountDeletionViewModel(backend: backend, defaults: defaults, suspendSync: {})
            await model.erase(password: password)
            #expect(model.completed, "Disposable deletion must finish: \(model.error ?? "unknown error")")
            #expect(backend.verifiedEmpty && auth.currentUser == nil)
            #expect(!FileManager.default.fileExists(atPath: AccountSyncCache.shared.folder(owner).path))
            #expect(Auth.auth().currentUser?.uid == originalOwner)
            guard model.completed else { throw CocoaError(.fileWriteUnknown) }
            do {
                _ = try await auth.signIn(withEmail: email, password: password)
                Issue.record("Deleted disposable account still signs in")
            } catch {
                let code = AuthErrorCode(rawValue: (error as NSError).code)
                #expect(code == .userNotFound || code == .invalidCredential || code == .wrongPassword)
            }
            if let unexpected = auth.currentUser, unexpected.uid == owner, unexpected.email == email { try await unexpected.delete() }
        } catch {
            try? await database.enableNetwork()
            if let remaining = auth.currentUser, remaining.uid == owner, remaining.email == email {
                _ = try? await backend.verify(password: password)
                try? await backend.deleteCloud(owner: owner)
                try? await backend.deleteLocal(owner: owner)
                try? await remaining.delete()
            }
            _ = await backend.clearDatabaseCache()
            throw error
        }
    }

    private func verifyDisconnectedClientRecovers(database: Firestore, owner: String, version: String) async throws {
        let chunk = database.collection("users").document(owner).collection("recordChunks").document(version + "_0")
        _ = try await chunk.getDocument(source: .server)
        try await database.disableNetwork()
        do {
            let cached = try await chunk.getDocument(source: .cache)
            #expect(cached.exists && cached.metadata.isFromCache)
            do {
                _ = try await chunk.getDocument(source: .server)
                Issue.record("Disconnected Firestore client unexpectedly returned a server read")
            } catch {
                #expect((error as NSError).code == FirestoreErrorCode.unavailable.rawValue)
            }
            let payload = Data("fictional edit made while disconnected".utf8)
            let offlineVersion = UUID().uuidString
            let offlineChunk = chunk.parent.document(offlineVersion + "_0")
            let queued = Task { try await offlineChunk.setData(["bytes": payload, "version": offlineVersion]) }
            var hasPendingWrite = false
            for _ in 0..<100 {
                if let local = try? await offlineChunk.getDocument(source: .cache),
                   local.metadata.hasPendingWrites && local.data()?["bytes"] as? Data == payload {
                    hasPendingWrite = true
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(hasPendingWrite, "Offline edit must remain locally queued")
            try await database.enableNetwork()
            try await queued.value
            let restored = try await offlineChunk.getDocument(source: .server)
            #expect(restored.data()?["bytes"] as? Data == payload)
            #expect(!restored.metadata.hasPendingWrites && !restored.metadata.isFromCache)
        } catch {
            try? await database.enableNetwork()
            throw error
        }
    }
}
