import Foundation

@MainActor
final class AccountWalkingSessionStore: WalkingSessionStoring {
    let local: any WalkingSessionStoring
    init(local: (any WalkingSessionStoring)? = nil) { self.local = local ?? CoreDataWalkingSessionStore() }
    func loadSessions(for ownerID: String) async throws -> [WalkingSession] {
        var result = Dictionary(uniqueKeysWithValues: try await local.loadSessions(for: ownerID).map { ($0.id, $0) })
        for session in try AccountSyncCache.shared.values(WalkingSession.self, owner: ownerID, kind: "walk") { result[session.id] = session }
        return result.values.sorted { $0.startedAt > $1.startedAt }
    }
    func saveSession(_ session: WalkingSession, for ownerID: String) async throws {
        try await local.saveSession(session, for: ownerID)
        if ownerID != "guest", ownerID != "local-device" {
            try AccountSyncCache.shared.put(session, owner: ownerID, kind: "walk", key: session.id.uuidString)
        }
    }
}
