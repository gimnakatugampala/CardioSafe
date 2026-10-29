import Foundation
import CoreLocation
import MapKit
import Testing
@testable import CardioSafe

@MainActor struct VoiceAndGeofenceTests {
    @MainActor final class Monitor: ArrivalMonitoring {
        var onEvent: ((ArrivalEvent) -> Void)?
        var access = ArrivalAccess(permission: .always, precise: true, supported: true)
        var started: HospitalArrivalReminder?
        func start(_ reminder: HospitalArrivalReminder) { started = reminder }
        func stop() { started = nil }
        func requestAlways() {}
        func requestWhenInUse() {}
    }
    @MainActor final class Alerts: ArrivalNotifying {
        var arrivals: [String] = [], exits: [String] = []
        func authorize() async throws -> Bool { true }
        func schedule(id: String) async throws { arrivals.append(id) }
        func scheduleExit(id: String) async throws { exits.append(id) }
        func cancel(id: String) {}
    }
    @MainActor final class Store: ArrivalReminderStoring {
        var value: HospitalArrivalReminder?
        func load() throws -> HospitalArrivalReminder? { value }
        func save(_ reminder: HospitalArrivalReminder?) throws { value = reminder }
    }
    @Test func departureRequiresArrivalAndDeliversOnlyOnce() async throws {
        let monitor = Monitor(), alerts = Alerts(), store = Store()
        let model = HospitalArrivalViewModel(service: monitor, notifications: alerts, store: store)
        await model.enable(for: ArrivalPlace(id: "hospital", name: "Test", latitude: 6.9, longitude: 79.8), exitFollowUp: true)
        let reminder = try #require(model.reminder)
        monitor.onEvent?(.exited(reminder.regionID))
        #expect(alerts.exits.isEmpty)
        monitor.onEvent?(.entered(reminder.regionID))
        while model.isBusy { await Task.yield() }
        #expect(alerts.arrivals.count == 1 && model.reminder?.arrivalNotified == true)
        monitor.onEvent?(.entered(reminder.regionID))
        #expect(alerts.arrivals.count == 1)
        monitor.onEvent?(.exited(reminder.regionID))
        while model.isBusy { await Task.yield() }
        #expect(alerts.exits == [reminder.regionID + ".exit"] && model.reminder == nil)
        monitor.onEvent?(.exited(reminder.regionID))
        #expect(alerts.exits.count == 1)
    }
    @Test func restStopRejectsStaleInaccurateAndOldRegionEvents() async throws {
        let monitor = Monitor(), alerts = Alerts()
        let model = WalkingRestStopViewModel(service: monitor, notifications: alerts)
        let item = MKMapItem(location: CLLocation(latitude: 6.9271, longitude: 79.8612), address: nil)
        item.name = "Test park"
        model.isWalking = true
        model.select(MapPlace(item: item, category: .parks))
        let reminder = try #require(model.reminder)
        #expect(reminder.regionID.hasPrefix("cardiosafe.reststop."))
        monitor.onEvent?(.entered("old-region"))
        let now = Date.now
        model.update(CLLocation(coordinate: item.location.coordinate, altitude: 0, horizontalAccuracy: 200, verticalAccuracy: -1, timestamp: now), now: now)
        model.update(CLLocation(coordinate: item.location.coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-60)), now: now)
        #expect(!model.isNearby)
        monitor.onEvent?(.entered(reminder.regionID))
        while alerts.arrivals.isEmpty { await Task.yield() }
        monitor.onEvent?(.entered(reminder.regionID))
        #expect(model.isNearby && alerts.arrivals.count == 1)
        monitor.onEvent?(.exited(reminder.regionID))
        #expect(!model.isNearby)
        monitor.onEvent?(.entered(reminder.regionID))
        #expect(model.isNearby && alerts.arrivals.count == 1)
        model.clear(); monitor.onEvent?(.entered(reminder.regionID))
        #expect(model.reminder == nil && !model.isNearby && alerts.arrivals.count == 1)
    }
    @Test func voiceRequestsExpireAndCannotCrossAccounts() throws {
        let suite = "voice-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("alice", forKey: "walkingVoiceOwner")
        let now = Date.now
        try WalkingVoiceQueue.submit(.rest, defaults: defaults, now: now)
        #expect(WalkingVoiceQueue.take(owner: "bob", defaults: defaults, now: now) == nil)
        try WalkingVoiceQueue.submit(.resume, defaults: defaults, now: now)
        #expect(WalkingVoiceQueue.take(owner: "alice", defaults: defaults, now: now.addingTimeInterval(61)) == nil)
        try WalkingVoiceQueue.submit(.start, defaults: defaults, now: now)
        #expect(WalkingVoiceQueue.take(owner: "alice", defaults: defaults, now: now) == .start)
        #expect(WalkingVoiceQueue.take(owner: "alice", defaults: defaults, now: now) == nil)
    }
    @Test func voiceCommandsKeepOneWalkAndRespectSessionPhase() {
        let session = WalkingSessionViewModel()
        #expect(!WalkingVoiceExecutor.apply(.rest, session: session, plan: nil))
        #expect(WalkingVoiceExecutor.apply(.start, session: session, plan: nil))
        let id = session.session?.id
        #expect(WalkingVoiceExecutor.apply(.start, session: session, plan: nil))
        #expect(session.session?.id == id)
        #expect(WalkingVoiceExecutor.apply(.rest, session: session, plan: nil))
        #expect(session.phase == .resting)
        #expect(!WalkingVoiceExecutor.apply(.rest, session: session, plan: nil))
        #expect(WalkingVoiceExecutor.apply(.resume, session: session, plan: nil))
        #expect(session.phase == .walking && session.session?.id == id)
        _ = session.finish()
    }
}
