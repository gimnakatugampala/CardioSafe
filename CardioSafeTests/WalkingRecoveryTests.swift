import Foundation
import CoreLocation
import Testing
@testable import CardioSafe

@MainActor struct WalkingRecoveryTests {
    @MainActor final class Clock: WalkingSessionClock {
        var seconds: Double = 0
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func read() -> WalkingSessionInstant { .init(date: start.addingTimeInterval(seconds), monotonicSeconds: seconds) }
    }
    @MainActor final class Sessions: WalkingSessionStoring {
        var records: [String: [UUID: WalkingSession]] = [:]
        var fails = false
        func loadSessions(for ownerID: String) async throws -> [WalkingSession] { Array(records[ownerID, default: [:]].values) }
        func saveSession(_ session: WalkingSession, for ownerID: String) async throws {
            if fails { throw CocoaError(.fileWriteUnknown) }
            records[ownerID, default: [:]][session.id] = session
        }
    }
    private func storage() -> FileWalkingRecoveryStore {
        FileWalkingRecoveryStore(root: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
    @Test func restartKeepsWalkingAndRestButExcludesUntrackedGap() async throws {
        let disk = storage(), clock = Clock()
        defer { try? FileManager.default.removeItem(at: disk.root) }
        let first = WalkingSessionViewModel(clock: clock, recoveryStore: disk, ownerID: "alice")
        #expect(first.start(plan: WalkingPlan(walkingMinutes: 20, restMinutesPerBreak: 3)))
        clock.seconds = 40; #expect(first.beginRest())
        clock.seconds = 55; first.checkpoint()
        clock.seconds = 500
        let restored = WalkingSessionViewModel(clock: clock, recoveryStore: disk, ownerID: "alice")
        await restored.useAccount("alice")
        #expect(restored.needsRecoveryDecision && !restored.isActive)
        #expect(restored.timing().walkingSeconds == 40 && restored.timing().restingSeconds == 15)
        #expect(!restored.start())
        #expect(restored.resumeRecoveredWalk())
        clock.seconds = 520
        #expect(restored.timing().walkingSeconds == 60 && restored.timing().restingSeconds == 15)
        #expect(restored.session?.untrackedGaps?.first?.from == clock.start.addingTimeInterval(55))
        #expect(restored.finish())
    }
    @Test func finishWithoutResumingUsesCheckpointAndClearsOnlyAfterSave() async throws {
        let disk = storage(), clock = Clock(), sessions = Sessions()
        defer { try? FileManager.default.removeItem(at: disk.root) }
        let first = WalkingSessionViewModel(clock: clock, recoveryStore: disk, ownerID: "alice")
        #expect(first.start()); clock.seconds = 12; first.checkpoint()
        let id = try #require(first.session?.id)
        clock.seconds = 100
        sessions.fails = true
        let restored = WalkingSessionViewModel(clock: clock, recoveryStore: disk, sessionStore: sessions, ownerID: "alice")
        await restored.useAccount("alice")
        #expect(restored.finishRecoveredWalk())
        await restored.savePendingSessions()
        #expect(restored.session?.walkingSeconds == 12)
        #expect(restored.session?.endedAt == clock.start.addingTimeInterval(12))
        #expect(try disk.load(owner: "alice")?.session.id == id)
        sessions.fails = false
        await restored.savePendingSessions()
        #expect(try disk.load(owner: "alice") == nil)
        #expect(sessions.records["alice"]?.count == 1)
        let reopened = WalkingSessionViewModel(clock: clock, recoveryStore: disk, sessionStore: sessions, ownerID: "alice")
        await reopened.useAccount("alice")
        #expect(!reopened.needsRecoveryDecision && reopened.completedSessions.count == 1)
    }
    @Test func recoveryIsIsolatedByOwnerAndRouteDoesNotBridgeRestart() async throws {
        let disk = storage(), clock = Clock()
        defer { try? FileManager.default.removeItem(at: disk.root) }
        let first = WalkingSessionViewModel(clock: clock, recoveryStore: disk, ownerID: "alice")
        #expect(first.start())
        clock.seconds = 1
        let fix = CLLocation(coordinate: .init(latitude: 6.9271, longitude: 79.8612), altitude: 0,
                             horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: clock.read().date)
        first.recordLocation(fix, receivedAt: clock.read().date)
        first.checkpoint()
        let bob = WalkingSessionViewModel(clock: clock, recoveryStore: disk, ownerID: "bob")
        await bob.useAccount("bob")
        #expect(bob.session == nil && !bob.needsRecoveryDecision)
        clock.seconds = 100
        let restored = WalkingSessionViewModel(clock: clock, recoveryStore: disk, ownerID: "alice")
        await restored.useAccount("alice")
        #expect(restored.resumeRecoveredWalk())
        clock.seconds = 101
        let second = CLLocation(coordinate: .init(latitude: 6.9300, longitude: 79.8612), altitude: 0,
                                horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: clock.read().date)
        restored.recordLocation(second, receivedAt: clock.read().date)
        #expect(restored.session?.routeSegments?.count == 2)
        #expect(restored.session?.routeDistanceMetres == 0)
        #expect(restored.finish())
    }
}
