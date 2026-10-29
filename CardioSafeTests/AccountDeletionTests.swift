import Foundation
import Testing
@testable import CardioSafe

@MainActor struct AccountDeletionTests {
    @MainActor final class Backend: AccountDeleting {
        var events: [String] = []
        var active = false, fails = false
        var owner = "alice"
        func verify(password: String) async throws -> String { events.append("verify"); return owner }
        func checkSOS(owner: String) async throws { events.append("check"); if active { throw AccountDeletionError.activeSOS } }
        func deleteCloud(owner: String) async throws { events.append("cloud"); if fails { throw CocoaError(.fileWriteUnknown) } }
        func deleteLocal(owner: String) async throws { events.append("local") }
        func deleteIdentity(owner: String) async throws { events.append("identity") }
        func clearDatabaseCache() async -> String? { events.append("cache"); return nil }
    }
    @Test func deletionOrdersOperationsAndRetriesWithoutSyncingAfterFailure() async throws {
        let suite = "delete-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = Backend()
        let model = AccountDeletionViewModel(backend: backend, defaults: defaults, suspendSync: { backend.events.append("suspend") })
        backend.fails = true
        await model.erase(password: "fictional")
        #expect(model.pendingOwner == "alice" && !model.completed)
        #expect(backend.events == ["verify", "check", "suspend", "cloud"])
        #expect(defaults.string(forKey: AccountDeletionViewModel.pendingKey) == "alice")
        backend.events = []; backend.fails = false
        await model.erase(password: "fictional")
        #expect(backend.events == ["verify", "check", "suspend", "cloud", "local", "identity", "cache"])
        #expect(model.completed && model.pendingOwner == nil)
        #expect(defaults.string(forKey: AccountDeletionViewModel.pendingKey) == nil)
        let completedEvents = backend.events
        await model.erase(password: "fictional")
        #expect(backend.events == completedEvents)
    }
    @Test func activeSOSAndAccountSwitchBlockDestruction() async throws {
        let suite = "delete-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = Backend(); backend.active = true
        let model = AccountDeletionViewModel(backend: backend, defaults: defaults, suspendSync: {})
        await model.erase(password: "fictional")
        #expect(backend.events == ["verify", "check"] && model.pendingOwner == nil)
        defaults.set("alice", forKey: AccountDeletionViewModel.pendingKey)
        backend.events = []; backend.owner = "bob"
        let restored = AccountDeletionViewModel(backend: backend, defaults: defaults, suspendSync: {})
        await restored.erase(password: "fictional")
        #expect(backend.events == ["verify"] && restored.pendingOwner == "alice")
    }
    @Test func fileCleanupIsOwnerScopedAndPDFRemovalKeepsMetadata() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AccountSyncCache(root: root.appendingPathComponent("AccountSync"))
        for owner in ["alice", "bob"] {
            let folder = cache.folder(owner).appendingPathComponent("ScannedDocuments")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("fictional".utf8).write(to: folder.appendingPathComponent("sample.pdf"))
            try Data("metadata".utf8).write(to: folder.appendingPathComponent("metadata.json"))
        }
        #expect(try AccountLocalDataCleaner.removePDFs(owner: "alice", cache: cache) == 1)
        #expect(FileManager.default.fileExists(atPath: cache.folder("alice").appendingPathComponent("ScannedDocuments/metadata.json").path))
        #expect(FileManager.default.fileExists(atPath: cache.folder("bob").appendingPathComponent("ScannedDocuments/sample.pdf").path))
        try AccountLocalDataCleaner.clear(owner: "alice", root: root)
        #expect(!FileManager.default.fileExists(atPath: cache.folder("alice").path))
        #expect(FileManager.default.fileExists(atPath: cache.folder("bob").path))
        #expect(throws: (any Error).self) { try AccountLocalDataCleaner.clear(owner: "guest", root: root) }
    }
    @Test func coreDataPurgeLeavesOtherAccountPlansAndWalks() async throws {
        let plans = CoreDataWalkingPlanStore(inMemory: true)
        let walks = CoreDataWalkingSessionStore(inMemory: true)
        let date = Date.now
        let session = WalkingSession(id: UUID(), plan: nil, startedAt: date, endedAt: date.addingTimeInterval(10),
            intervals: [.init(kind: .walking, startedAt: date, endedAt: date.addingTimeInterval(10), durationSeconds: 10)])
        for owner in ["alice", "bob"] {
            try await plans.savePlan(.init(walkingMinutes: 20, restMinutesPerBreak: 3), for: owner)
            try await walks.saveSession(session, for: owner)
        }
        try await plans.deletePlan(for: "alice"); try await walks.deleteSessions(for: "alice")
        #expect(try await plans.loadPlan(for: "alice") == nil)
        #expect(try await walks.loadSessions(for: "alice").isEmpty)
        #expect(try await plans.loadPlan(for: "bob")?.walkingMinutes == 20)
        #expect(try await walks.loadSessions(for: "bob").count == 1)
    }
}
