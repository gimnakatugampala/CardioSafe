import Foundation
import Testing
import FirebaseAuth
import FirebaseFirestore
@testable import CardioSafe

@MainActor struct AccountSyncIntegrationTests {
    struct Sample: Codable, Equatable { let text: String }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CARDIOSAFE_RUN_SYNC_INTEGRATION"] == "1",
                   "Opt-in live Firebase check: TEST_RUNNER_CARDIOSAFE_RUN_SYNC_INTEGRATION=1"))
    func twoPhoneRestoreConflictAndDeletionWithPrivateRules() async throws {
        let owner = try #require(Auth.auth().currentUser?.uid, "Sign in on the test simulator before the live check.")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let firstCache = AccountSyncCache(root: folder.appendingPathComponent("first"))
        let secondCache = AccountSyncCache(root: folder.appendingPathComponent("second"))
        let first = FirebaseAccountSync(cache: firstCache), second = FirebaseAccountSync(cache: secondCache)
        defer { first.stop(); second.stop() }
        let key = "sync-check-" + UUID().uuidString
        let original = Sample(text: String(repeating: "Fictional route check. ", count: 55_000))
        try firstCache.put(original, owner: owner, kind: "profile", key: key)
        let planKey = "plan-check-" + UUID().uuidString
        let appearanceKey = "appearance-check-" + UUID().uuidString
        let plan = WalkingPlan(walkingMinutes: 25, restMinutesPerBreak: 4)
        try firstCache.put(plan, owner: owner, kind: "profile", key: planKey)
        try firstCache.put("dark", owner: owner, kind: "profile", key: appearanceKey)
        await first.start(owner: owner); await first.waitForUploads()
        let uploadedValue = try firstCache.record(owner, kind: "profile", key: key)
        let uploaded = try #require(uploadedValue)
        #expect(!uploaded.pending, "Upload must finish before restore")
        await second.start(owner: owner); await second.waitForUploads()
        #expect(try secondCache.value(Sample.self, owner: owner, kind: "profile", key: key) == original)
        #expect(try secondCache.value(WalkingPlan.self, owner: owner, kind: "profile", key: planKey) == plan)
        #expect(try secondCache.value(String.self, owner: owner, kind: "profile", key: appearanceKey) == "dark")
        first.stop(); second.stop()
        try firstCache.put(Sample(text: "First phone offline edit"), owner: owner, kind: "profile", key: key)
        try secondCache.put(Sample(text: "Second phone edit"), owner: owner, kind: "profile", key: key)
        await second.start(owner: owner); await second.waitForUploads()
        await first.start(owner: owner); await first.waitForUploads()
        let conflict = try #require(first.conflicts.first(where: { $0.key == key }))
        await first.resolve(conflict, keepLocal: false); await first.waitForUploads()
        #expect(try firstCache.value(Sample.self, owner: owner, kind: "profile", key: key)?.text == "Second phone edit")
        try firstCache.put(plan, owner: owner, kind: "profile", key: planKey, deleted: true)
        try firstCache.put("dark", owner: owner, kind: "profile", key: appearanceKey, deleted: true)
        try firstCache.put(Sample(text: ""), owner: owner, kind: "profile", key: key, deleted: true)
        first.sync(); await first.waitForUploads()
        await second.start(owner: owner); await second.waitForUploads()
        let deletedValue = try secondCache.record(owner, kind: "profile", key: key)
        let deleted = try #require(deletedValue)
        #expect(deleted.deleted)
        let unrelated = Firestore.firestore().collection("users").document("unrelated-" + UUID().uuidString).collection("records").document("profile_current")
        do {
            _ = try await unrelated.getDocument(source: .server)
            Issue.record("Another account’s private record path was readable")
        } catch {
            #expect((error as NSError).code == FirestoreErrorCode.permissionDenied.rawValue)
        }
    }
}
