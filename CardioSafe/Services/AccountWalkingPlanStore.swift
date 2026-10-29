import Foundation

/// Core Data keeps the local plan; the private account cache is authoritative once present.
@MainActor final class AccountWalkingPlanStore: WalkingPlanStoring {
    private let local: any WalkingPlanStoring
    private let cache: AccountSyncCache
    init(local: (any WalkingPlanStoring)? = nil, cache: AccountSyncCache? = nil) {
        self.local = local ?? CoreDataWalkingPlanStore()
        self.cache = cache ?? .shared
    }
    func loadPlan(for ownerID: String) async throws -> WalkingPlan? {
        if ownerID != "guest", ownerID != "local-device" {
            if let record = try cache.record(ownerID, kind: "profile", key: "walking-plan") {
                if record.deleted { return nil }
                let plan = try JSONDecoder().decode(WalkingPlan.self, from: record.payload)
                try validate(plan)
                return plan
            }
        }
        let plan = try await local.loadPlan(for: ownerID)
        if let plan, ownerID != "guest", ownerID != "local-device" {
            try validate(plan)
            try cache.put(plan, owner: ownerID, kind: "profile", key: "walking-plan")
        }
        return plan
    }
    func savePlan(_ plan: WalkingPlan, for ownerID: String) async throws {
        try validate(plan)
        try await local.savePlan(plan, for: ownerID)
        if ownerID != "guest", ownerID != "local-device" {
            try cache.put(plan, owner: ownerID, kind: "profile", key: "walking-plan")
        }
    }
    private func validate(_ plan: WalkingPlan) throws {
        guard plan.walkingMinutes > 0, plan.walkingMinutes <= Int.max / 60,
              plan.restMinutesPerBreak.map({ $0 > 0 && $0 <= Int.max / 60 }) ?? true else {
            throw WalkingPlanStorageError.invalidPlan
        }
    }
}
