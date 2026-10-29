import Foundation
import Testing
@testable import CardioSafe

@MainActor struct WalkingPlanAccountTests {
    @MainActor final class Store: WalkingPlanStoring {
        var plans: [String: WalkingPlan] = [:]
        var suspendedOwner: String?
        var loadContinuation: CheckedContinuation<WalkingPlan?, Never>?
        func loadPlan(for ownerID: String) async throws -> WalkingPlan? {
            if ownerID == suspendedOwner {
                return await withCheckedContinuation { loadContinuation = $0 }
            }
            return plans[ownerID]
        }
        func savePlan(_ plan: WalkingPlan, for ownerID: String) async throws { plans[ownerID] = plan }
    }

    @Test func switchingAccountsRestoresOnlyTheirOwnTargetAndRest() async throws {
        let store = CoreDataWalkingPlanStore(inMemory: true)
        let first = WalkingPlan(walkingMinutes: 20, restMinutesPerBreak: 3)
        let second = WalkingPlan(walkingMinutes: 10, restMinutesPerBreak: nil)
        let model = DashboardViewModel(planStore: store, ownerID: "guest")
        await model.useAccount("patient-a")
        #expect(model.snapshot.walkingPlan == nil)
        try await model.saveWalkingPlan(first, for: "patient-a")
        await model.useAccount("patient-b")
        #expect(model.snapshot.walkingPlan == nil)
        try await model.saveWalkingPlan(second, for: "patient-b")
        await model.useAccount("patient-a")
        #expect(model.snapshot.walkingPlan == first)
        await model.useAccount("guest")
        #expect(model.snapshot.walkingPlan == nil)
        await model.useAccount("patient-b")
        #expect(model.snapshot.walkingPlan == second)
    }

    @Test func lateLoadFromPreviousAccountCannotReplaceCurrentPlan() async {
        let store = Store()
        store.suspendedOwner = "patient-a"
        let second = WalkingPlan(walkingMinutes: 15, restMinutesPerBreak: 2)
        store.plans["patient-b"] = second
        let model = DashboardViewModel(planStore: store, ownerID: "guest")
        let firstLoad = Task { await model.useAccount("patient-a") }
        while store.loadContinuation == nil { await Task.yield() }
        await model.useAccount("patient-b")
        store.loadContinuation?.resume(returning: WalkingPlan(walkingMinutes: 50, restMinutesPerBreak: 8))
        await firstLoad.value
        #expect(model.snapshot.walkingPlan == second)
        #expect(model.hasLoadedPlan && !model.isLoadingPlan)
    }

    @Test func oldEditFormCannotWriteIntoAnotherAccount() async throws {
        let store = Store()
        let model = DashboardViewModel(planStore: store, ownerID: "patient-a")
        await model.loadWalkingPlan()
        await model.useAccount("patient-b")
        do {
            try await model.saveWalkingPlan(WalkingPlan(walkingMinutes: 30, restMinutesPerBreak: 5), for: "patient-a")
            Issue.record("An editor from the previous account was accepted")
        } catch WalkingPlanStorageError.accountChanged {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(store.plans.isEmpty)
        #expect(model.snapshot.walkingPlan == nil)
    }

    @Test func sharedLegacyPlanIsNeverLoadedAsPatientOrGuestPlan() async throws {
        let store = CoreDataWalkingPlanStore(inMemory: true)
        try await store.savePlan(WalkingPlan(walkingMinutes: 60, restMinutesPerBreak: 10), for: "local-device")
        let model = DashboardViewModel(planStore: store, ownerID: "guest")
        await model.loadWalkingPlan()
        #expect(model.snapshot.walkingPlan == nil)
        await model.useAccount("unrelated-patient")
        #expect(model.snapshot.walkingPlan == nil)
    }
}
