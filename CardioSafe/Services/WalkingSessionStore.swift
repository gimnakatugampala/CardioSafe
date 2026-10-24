import CoreData
import CoreLocation
import Foundation

@MainActor
protocol WalkingSessionStoring {
    func loadSessions(for ownerID: String) async throws -> [WalkingSession]
    func saveSession(_ session: WalkingSession, for ownerID: String) async throws
}

enum WalkingSessionStorageError: Error { case invalidRecord }

@MainActor
final class CoreDataWalkingSessionStore: WalkingSessionStoring {
    private let container: NSPersistentContainer
    private let directory: URL?
    private var loadingTask: Task<Void, Error>?
    private var isReady = false

    init(storeURL: URL? = nil, inMemory: Bool = false) {
        let entity = NSEntityDescription()
        entity.name = "WalkingSessionRecord"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [Self.attribute("ownerID", .stringAttributeType),
                             Self.attribute("sessionID", .UUIDAttributeType),
                             Self.attribute("startedAt", .dateAttributeType),
                             Self.attribute("payload", .binaryDataAttributeType)]
        entity.uniquenessConstraints = [["ownerID", "sessionID"]]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        container = NSPersistentContainer(name: "CardioSafeWalks", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        if inMemory {
            description.type = NSInMemoryStoreType
            directory = nil
        } else {
            let url = storeURL ?? NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("CardioSafeWalks.sqlite")
            description.url = url
            directory = url.deletingLastPathComponent()
            #if os(iOS)
            description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                                  forKey: NSPersistentStoreFileProtectionKey)
            #endif
        }
        description.shouldAddStoreAsynchronously = true
        container.persistentStoreDescriptions = [description]
    }

    func loadSessions(for ownerID: String) async throws -> [WalkingSession] {
        guard !ownerID.isEmpty else { throw WalkingSessionStorageError.invalidRecord }
        try await prepareStore()
        let request = NSFetchRequest<NSManagedObject>(entityName: "WalkingSessionRecord")
        request.predicate = NSPredicate(format: "ownerID == %@", ownerID)
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return try container.viewContext.fetch(request).map { record in
            guard let data = record.value(forKey: "payload") as? Data else { throw WalkingSessionStorageError.invalidRecord }
            let session = try JSONDecoder().decode(WalkingSession.self, from: data)
            try validate(session)
            guard record.value(forKey: "sessionID") as? UUID == session.id else { throw WalkingSessionStorageError.invalidRecord }
            return session
        }
    }

    func saveSession(_ session: WalkingSession, for ownerID: String) async throws {
        guard !ownerID.isEmpty else { throw WalkingSessionStorageError.invalidRecord }
        try validate(session)
        let data = try JSONEncoder().encode(session)
        try await prepareStore()
        let context = container.viewContext
        do {
            let request = NSFetchRequest<NSManagedObject>(entityName: "WalkingSessionRecord")
            request.predicate = NSPredicate(format: "ownerID == %@ AND sessionID == %@", ownerID, session.id as NSUUID)
            request.fetchLimit = 1
            let record = try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(forEntityName: "WalkingSessionRecord", into: context)
            record.setValue(ownerID, forKey: "ownerID")
            record.setValue(session.id, forKey: "sessionID")
            record.setValue(session.startedAt, forKey: "startedAt")
            record.setValue(data, forKey: "payload")
            try context.save()
        } catch { context.rollback(); throw error }
    }

    private func validate(_ session: WalkingSession) throws {
        guard session.endedAt != nil, !session.intervals.isEmpty,
              session.intervals.allSatisfy({ $0.durationSeconds.isFinite && $0.durationSeconds >= 0 }) else {
            throw WalkingSessionStorageError.invalidRecord
        }
        if let health = session.healthSnapshot, !health.isValid {
            throw WalkingSessionStorageError.invalidRecord
        }
        for segment in session.routeSegments ?? [] {
            guard segment.points.allSatisfy({
                CLLocationCoordinate2DIsValid($0.coordinate) && $0.accuracyMetres.isFinite
                    && $0.accuracyMetres >= 0 && $0.accuracyMetres <= 50
            }) else { throw WalkingSessionStorageError.invalidRecord }
        }
        if let plan = session.plan, plan.walkingMinutes <= 0 || plan.walkingMinutes > Int.max / 60 {
            throw WalkingSessionStorageError.invalidRecord
        }
        if let rest = session.plan?.restMinutesPerBreak, rest <= 0 || rest > Int.max / 60 {
            throw WalkingSessionStorageError.invalidRecord
        }
    }

    private static func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        return attribute
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

}
