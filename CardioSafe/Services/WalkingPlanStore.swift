import CoreData
import Foundation

@MainActor
protocol WalkingPlanStoring {
    func loadPlan(for ownerID: String) async throws -> WalkingPlan?
    func savePlan(_ plan: WalkingPlan, for ownerID: String) async throws
}

enum WalkingPlanStorageError: Error {
    case invalidOwner
    case invalidPlan
    case unreadablePlan
    case planNotLoaded
    case saveInProgress
    case accountChanged
}

@MainActor
final class CoreDataWalkingPlanStore: WalkingPlanStoring {
    private let container: NSPersistentContainer
    private let directory: URL?
    private var loadingTask: Task<Void, Error>?
    private var isReady = false

    init(storeURL: URL? = nil, inMemory: Bool = false) {
        container = NSPersistentContainer(name: "CardioSafePlans", managedObjectModel: WalkingPlanStoreModel.makeModel())
        let description = NSPersistentStoreDescription()
        if inMemory {
            description.type = NSInMemoryStoreType
            directory = nil
        } else {
            let url = storeURL ?? NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("CardioSafePlans.sqlite")
            description.type = NSSQLiteStoreType
            description.url = url
            directory = url.deletingLastPathComponent()
            #if os(iOS)
            description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                                  forKey: NSPersistentStoreFileProtectionKey)
            #endif
        }
        description.shouldAddStoreAsynchronously = true
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
    }

    func loadPlan(for ownerID: String) async throws -> WalkingPlan? {
        try validateOwner(ownerID)
        try await prepareStore()
        guard let record = try fetchRecord(for: ownerID) else { return nil }
        guard let walkingNumber = record.value(forKey: "walkingMinutes") as? NSNumber,
              let walking = Int(exactly: walkingNumber.int64Value) else {
            throw WalkingPlanStorageError.unreadablePlan
        }
        var rest: Int?
        if let restNumber = record.value(forKey: "restMinutesPerBreak") as? NSNumber {
            guard let minutes = Int(exactly: restNumber.int64Value) else {
                throw WalkingPlanStorageError.unreadablePlan
            }
            rest = minutes
        }
        let plan = WalkingPlan(walkingMinutes: walking, restMinutesPerBreak: rest)
        try validatePlan(plan)
        return plan
    }

    func savePlan(_ plan: WalkingPlan, for ownerID: String) async throws {
        try validateOwner(ownerID)
        try validatePlan(plan)
        try await prepareStore()
        let context = container.viewContext
        do {
            let record = try fetchRecord(for: ownerID)
                ?? NSEntityDescription.insertNewObject(forEntityName: "WalkingPlanRecord", into: context)
            record.setValue(ownerID, forKey: "ownerID")
            record.setValue(NSNumber(value: plan.walkingMinutes), forKey: "walkingMinutes")
            record.setValue(plan.restMinutesPerBreak.map { NSNumber(value: $0) }, forKey: "restMinutesPerBreak")
            record.setValue(Date(), forKey: "updatedAt")
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deletePlan(for ownerID: String) async throws {
        try validateOwner(ownerID); try await prepareStore()
        if let record = try fetchRecord(for: ownerID) { container.viewContext.delete(record); try container.viewContext.save() }
    }

    private func prepareStore() async throws {
        if isReady { return }
        if let loadingTask { try await loadingTask.value; return }
        let container = container
        let directory = directory
        let task = Task<Void, Error> { @MainActor in
            if let directory {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                container.loadPersistentStores { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
            container.viewContext.undoManager = nil
        }
        loadingTask = task
        do {
            try await task.value
            isReady = true
            loadingTask = nil
        } catch {
            loadingTask = nil
            throw error
        }
    }

    private func fetchRecord(for ownerID: String) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "WalkingPlanRecord")
        request.predicate = NSPredicate(format: "ownerID == %@", ownerID)
        request.fetchLimit = 1
        return try container.viewContext.fetch(request).first
    }

    private func validateOwner(_ ownerID: String) throws {
        if ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WalkingPlanStorageError.invalidOwner
        }
    }

    private func validatePlan(_ plan: WalkingPlan) throws {
        guard plan.walkingMinutes > 0, plan.walkingMinutes <= Int.max / 60 else {
            throw WalkingPlanStorageError.invalidPlan
        }
        if let rest = plan.restMinutesPerBreak, rest <= 0 || rest > Int.max / 60 {
            throw WalkingPlanStorageError.invalidPlan
        }
    }
}
