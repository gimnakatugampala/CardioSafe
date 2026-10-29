import Foundation
import CoreLocation
import Testing
@testable import CardioSafe

@MainActor struct WalkingReturnToStartTests {
    @MainActor final class Clock: WalkingSessionClock {
        let start = Date.now
        var seconds = 0.0
        func read() -> WalkingSessionInstant { .init(date: start.addingTimeInterval(seconds), monotonicSeconds: seconds) }
    }
    func record(_ model: WalkingSessionViewModel, clock: Clock, latitude: Double, accuracy: Double = 5) {
        let date = clock.read().date
        model.recordLocation(CLLocation(coordinate: .init(latitude: latitude, longitude: 79.8612), altitude: 0,
            horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: date), receivedAt: date)
    }
    @Test func startIsFirstAcceptedFixAndSurvivesRestWithoutChangingTimer() throws {
        let clock = Clock(), model = WalkingSessionViewModel(clock: clock)
        #expect(model.start())
        #expect(model.returnToStartPlace == nil)
        record(model, clock: clock, latitude: 6.9271, accuracy: 200)
        #expect(model.returnToStartPlace == nil)
        clock.seconds = 1
        record(model, clock: clock, latitude: 6.9271)
        clock.seconds = 11
        record(model, clock: clock, latitude: 6.9272)
        #expect(model.beginRest())
        let start = try #require(model.returnToStartPlace)
        #expect(start.coordinate.latitude == 6.9271 && start.name == "Walk starting point")
        #expect(model.timing().walkingSeconds == 11)
        clock.seconds = 16
        #expect(model.resume())
        record(model, clock: clock, latitude: 6.9273)
        #expect(model.returnToStartPlace?.coordinate.latitude == 6.9271)
        #expect(model.finish())
        #expect(model.returnToStartPlace == nil)
        #expect(model.start())
        #expect(model.returnToStartPlace == nil)
    }
    @Test func recoveryKeepsOriginalStartInsteadOfUsingResumeLocation() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileWalkingRecoveryStore(root: root), clock = Clock()
        let first = WalkingSessionViewModel(clock: clock, recoveryStore: store, ownerID: "return-test")
        #expect(first.start())
        clock.seconds = 1; record(first, clock: clock, latitude: 6.9271)
        clock.seconds = 10; first.checkpoint()
        let restored = WalkingSessionViewModel(clock: clock, recoveryStore: store, ownerID: "return-test")
        await restored.useAccount("return-test")
        #expect(restored.returnToStartPlace == nil)
        #expect(restored.resumeRecoveredWalk())
        clock.seconds = 20; record(restored, clock: clock, latitude: 6.928)
        #expect(restored.returnToStartPlace?.coordinate.latitude == 6.9271)
    }
}
