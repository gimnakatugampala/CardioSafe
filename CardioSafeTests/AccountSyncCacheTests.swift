import Foundation
import Testing
@testable import CardioSafe

@MainActor struct AccountSyncCacheTests {
    struct Value: Codable, Equatable { let name: String }
    @Test func pendingEditsSurviveRestartAndNeverCrossAccounts() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = AccountSyncCache(root: folder)
        try cache.put(Value(name: "Alice"), owner: "alice", kind: "profile", key: "current")
        let reopened = AccountSyncCache(root: folder)
        #expect(try reopened.value(Value.self, owner: "alice", kind: "profile", key: "current") == Value(name: "Alice"))
        #expect(try reopened.value(Value.self, owner: "bob", kind: "profile", key: "current") == nil)
        #expect(try reopened.records("alice").first?.pending == true)
    }
    @Test func consecutiveOfflineEditsKeepTheirOriginalCloudBaseline() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = AccountSyncCache(root: folder)
        let remote = AccountSyncRecord(kind: "profile", key: "current", payload: try JSONEncoder().encode(Value(name: "Original")), version: "server-version", baseVersion: "server-version", deleted: false, pending: false)
        try cache.write(remote, owner: "alice")
        try cache.put(Value(name: "First edit"), owner: "alice", kind: "profile", key: "current")
        let firstValue = try cache.record("alice", kind: "profile", key: "current")
        let first = try #require(firstValue)
        try cache.put(Value(name: "Second edit"), owner: "alice", kind: "profile", key: "current")
        let secondValue = try cache.record("alice", kind: "profile", key: "current")
        let second = try #require(secondValue)
        #expect(first.baseVersion == "server-version" && second.baseVersion == "server-version")
        #expect(first.version != second.version && second.pending)
    }
    @Test func deletionsAreDurableTombstonesAndIdenticalSavesAreNoOps() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = AccountSyncCache(root: folder)
        let value = Value(name: "Test")
        try cache.put(value, owner: "alice", kind: "document", key: "doc1")
        let version = try cache.record("alice", kind: "document", key: "doc1")?.version
        try cache.put(value, owner: "alice", kind: "document", key: "doc1")
        #expect(try cache.record("alice", kind: "document", key: "doc1")?.version == version)
        try cache.put(value, owner: "alice", kind: "document", key: "doc1", deleted: true)
        #expect(try cache.values(Value.self, owner: "alice", kind: "document").isEmpty)
        #expect(try AccountSyncCache(root: folder).records("alice").first?.deleted == true)
    }
    @Test func rejectsUnknownKindsAndUnsafeIdentifiers() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = AccountSyncCache(root: folder)
        #expect(throws: (any Error).self) { try cache.put(Value(name: "Test"), owner: "alice", kind: "other", key: "record") }
        #expect(!AccountSyncCache.validKey("../other"))
    }
    @Test func acknowledgementOfAnEarlierLocalEditIsNotAConflict() {
        let latest = AccountSyncRecord(kind: "profile", key: "current", payload: Data(), version: "new-local-edit", baseVersion: "old-cloud", deleted: false, pending: true)
        #expect(!latest.conflicts(with: "upload-in-progress", inFlightVersion: "upload-in-progress"))
        #expect(!latest.conflicts(with: "old-cloud", inFlightVersion: nil))
        #expect(latest.conflicts(with: "another-phone-edit", inFlightVersion: "upload-in-progress"))
    }

}
