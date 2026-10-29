import Foundation
import CoreLocation
import MapKit
import Observation
import UserNotifications

@MainActor final class RestStopNotificationService: ArrivalNotifying {
    func authorize() async throws -> Bool {
        [.authorized, .provisional, .ephemeral].contains(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }
    func schedule(id: String) async throws {
        guard try await authorize() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Saved rest stop nearby"
        content.body = "You may be near your selected stop. Open CardioSafe to decide whether to take a rest."
        content.sound = .default
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
    func cancel(id: String) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]) }
}

@MainActor @Observable final class WalkingRestStopViewModel {
    private(set) var reminder: HospitalArrivalReminder?
    private(set) var isNearby = false
    private(set) var message: String?
    var isWalking = false
    var canMonitorBackground: Bool { service.access.canMonitor }
    private let service: any ArrivalMonitoring
    private let notifications: any ArrivalNotifying
    private var alerted = false
    init(service: (any ArrivalMonitoring)? = nil, notifications: (any ArrivalNotifying)? = nil) {
        self.service = service ?? CoreLocationArrivalService(prefix: "cardiosafe.reststop.")
        self.notifications = notifications ?? RestStopNotificationService()
        self.service.stop()
        self.service.onEvent = { [weak self] event in
            guard let self, let reminder = self.reminder else { return }
            switch event {
            case .entered(let id) where id == reminder.regionID: self.approach()
            case .state(let id, let inside) where id == reminder.regionID && inside: self.approach()
            case .exited(let id) where id == reminder.regionID: self.leave()
            case .state(let id, let inside) where id == reminder.regionID && !inside: self.leave()
            case .accessChanged: if self.canMonitorBackground { self.service.start(reminder) }
            case .failed: self.message = "Background monitoring unavailable. Keep the walking map open for proximity alerts."
            default: break
            }
        }
    }
    func select(_ place: MapPlace) {
        clear()
        let selected = ArrivalPlace(id: place.id, name: place.name, latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        guard selected.isValid else { return }
        let reminder = HospitalArrivalReminder(id: UUID(), place: selected, hasBeenOutside: false, isRestStop: true)
        self.reminder = reminder
        if canMonitorBackground { service.start(reminder) }
        message = "Remind near this stop’s 200 m area. Seating and access are not verified."
    }
    func enableBackground() {
        if service.access.permission == .notDetermined { service.requestWhenInUse() }
        else if service.access.permission == .whenInUse { service.requestAlways() }
        else if let reminder, canMonitorBackground { service.start(reminder) }
        else { message = "Background alerts need Always and Precise Location in iOS Settings." }
    }
    func update(_ location: CLLocation, now: Date = .now) {
        guard let reminder, CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
              (-2...15).contains(now.timeIntervalSince(location.timestamp)) else { return }
        if location.distance(from: CLLocation(latitude: reminder.place.latitude, longitude: reminder.place.longitude)) <= 200 { approach() }
        else { leave() }
    }
    private func leave() {
        isNearby = false
        message = "Outside the saved rest stop’s reminder area."
    }
    private func approach() {
        guard isWalking, let reminder else { return }
        isNearby = true
        message = "You may be near your selected rest stop. Rest only if the location is suitable."
        guard !alerted else { return }
        alerted = true
        Task {
            do { try await notifications.schedule(id: reminder.regionID) }
            catch { if self.reminder?.id == reminder.id { message = "Nearby stop detected. Notification unavailable; use the map reminder." } }
            if self.reminder?.id != reminder.id { notifications.cancel(id: reminder.regionID) }
        }
    }
    func clear() {
        if let reminder { notifications.cancel(id: reminder.regionID) }
        service.stop(); reminder = nil; alerted = false; isNearby = false; message = nil
    }
}
