import Foundation
import Testing
@testable import CardioSafe

@MainActor struct WalkingPlanSyncTests {
    @MainActor final class Local: WalkingPlanStoring {
        var plans: [String: WalkingPlan] = [:]
        func loadPlan(for ownerID: String) async throws -> WalkingPlan? { plans[ownerID] }
        func savePlan(_ plan: WalkingPlan, for ownerID: String) async throws { plans[ownerID] = plan }
    }
    func cache() -> AccountSyncCache { AccountSyncCache(root: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)) }
    @Test func offlineEditsQueueAndCleanDeviceRestoresPlanWithAccountIsolation() async throws {
        let first = cache(), second = cache()
        defer { try? FileManager.default.removeItem(at: first.root); try? FileManager.default.removeItem(at: second.root) }
        let store = AccountWalkingPlanStore(local: Local(), cache: first)
        let plan = WalkingPlan(walkingMinutes: 25, restMinutesPerBreak: 4)
        try await store.savePlan(plan, for: "alice")
        let cachedRecord = try first.record("alice", kind: "profile", key: "walking-plan")
        var record = try #require(cachedRecord)
        #expect(record.pending && record.baseVersion == nil)
        record.pending = false; record.baseVersion = record.version
        try second.write(record, owner: "alice")
        let clean = AccountWalkingPlanStore(local: Local(), cache: second)
        #expect(try await clean.loadPlan(for: "alice") == plan)
        #expect(try await clean.loadPlan(for: "bob") == nil)
        #expect(try await clean.loadPlan(for: "guest") == nil)
        try await clean.savePlan(WalkingPlan(walkingMinutes: 30, restMinutesPerBreak: nil), for: "alice")
        #expect(try second.record("alice", kind: "profile", key: "walking-plan")?.baseVersion == record.version)
    }
    @Test func importsExistingAccountPlanButNeverGuestPlan() async throws {
        let cache = cache(), local = Local()
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let plan = WalkingPlan(walkingMinutes: 15, restMinutesPerBreak: nil)
        local.plans = ["alice": plan, "guest": plan]
        let store = AccountWalkingPlanStore(local: local, cache: cache)
        #expect(try await store.loadPlan(for: "alice") == plan)
        #expect(try cache.record("alice", kind: "profile", key: "walking-plan")?.pending == true)
        #expect(try await store.loadPlan(for: "guest") == plan)
        #expect(try cache.records("guest").isEmpty)
        try cache.put(WalkingPlan(walkingMinutes: -1, restMinutesPerBreak: 0), owner: "bob", kind: "profile", key: "walking-plan")
        await #expect(throws: (any Error).self) { try await store.loadPlan(for: "bob") }
    }
    @Test func appearanceIsScopedAndGuestChoiceIsNotClaimedByPatient() throws {
        let cache = cache()
        defer { try? FileManager.default.removeItem(at: cache.root) }
        let scoped = AccountAppearanceStore(cache: cache)
        try scoped.save("dark", owner: nil)
        try scoped.save("light", owner: "alice")
        #expect(try scoped.load(owner: nil) == "dark")
        #expect(try scoped.load(owner: "alice") == "light")
        #expect(try scoped.load(owner: "bob") == "system")
        #expect(throws: (any Error).self) { try scoped.save("invalid", owner: "alice") }
    }
}
