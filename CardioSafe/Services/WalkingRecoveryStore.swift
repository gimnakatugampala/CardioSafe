import Foundation

struct WalkingRecoveryRecord: Codable {
    let session: WalkingSession
    let checkpointAt: Date
}

@MainActor protocol WalkingRecoveryStoring {
    func load(owner: String) throws -> WalkingRecoveryRecord?
    func save(_ record: WalkingRecoveryRecord, owner: String) throws
    func clear(owner: String, sessionID: UUID) throws
}

@MainActor struct FileWalkingRecoveryStore: WalkingRecoveryStoring {
    var root = URL.applicationSupportDirectory.appendingPathComponent("WalkingRecovery")
    private func url(_ owner: String) -> URL {
        let name = Data(owner.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return root.appendingPathComponent(name + ".json")
    }
    func load(owner: String) throws -> WalkingRecoveryRecord? {
        let path = url(owner)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let record = try JSONDecoder().decode(WalkingRecoveryRecord.self, from: Data(contentsOf: path))
        guard record.session.startedAt <= record.checkpointAt,
              record.session.intervals.allSatisfy({ $0.durationSeconds.isFinite && $0.durationSeconds >= 0 }),
              record.session.healthSnapshot?.isValid != false else { throw CocoaError(.fileReadCorruptFile) }
        return record
    }
    func save(_ record: WalkingRecoveryRecord, owner: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: url(owner), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func clear(owner: String, sessionID: UUID) throws {
        guard try load(owner: owner)?.session.id == sessionID else { return }
        try FileManager.default.removeItem(at: url(owner))
    }
}
