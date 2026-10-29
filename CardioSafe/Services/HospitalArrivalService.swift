import Foundation
import CoreLocation
import UserNotifications

@MainActor final class CoreLocationArrivalService: NSObject, ArrivalMonitoring, CLLocationManagerDelegate {
    var onEvent: ((ArrivalEvent) -> Void)?
    private let manager = CLLocationManager()
    private let prefix: String

    var access: ArrivalAccess {
        let permission: ArrivalLocationPermission
        switch manager.authorizationStatus {
        case .authorizedAlways: permission = .always
        case .authorizedWhenInUse: permission = .whenInUse
        case .notDetermined: permission = .notDetermined
        default: permission = .denied
        }
        return ArrivalAccess(permission: permission, precise: manager.accuracyAuthorization == .fullAccuracy,
                             supported: CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self))
    }
    init(prefix: String = "cardiosafe.arrival.") { self.prefix = prefix; super.init(); manager.delegate = self }
    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    func requestAlways() { manager.requestAlwaysAuthorization() }
    func start(_ reminder: HospitalArrivalReminder) {
        guard access.canMonitor, manager.maximumRegionMonitoringDistance >= HospitalArrivalReminder.radiusMetres else {
            onEvent?(.failed(reminder.regionID)); return
        }
        let owned = manager.monitoredRegions.filter { $0.identifier.hasPrefix(prefix) }
        for region in owned where region.identifier != reminder.regionID { manager.stopMonitoring(for: region) }
        if let existing = owned.first(where: { $0.identifier == reminder.regionID }) {
            onEvent?(.started(existing.identifier))
            manager.requestState(for: existing)
            return
        }
        let region = CLCircularRegion(center: .init(latitude: reminder.place.latitude, longitude: reminder.place.longitude),
                                      radius: HospitalArrivalReminder.radiusMetres, identifier: reminder.regionID)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
    }
    func stop() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix("cardiosafe.arrival.") {
            manager.stopMonitoring(for: region)
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { onEvent?(.accessChanged) }
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        onEvent?(.started(region.identifier)); manager.requestState(for: region)
    }
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if state != .unknown { onEvent?(.state(region.identifier, inside: state == .inside)) }
    }
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) { onEvent?(.entered(region.identifier)) }
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) { onEvent?(.exited(region.identifier)) }
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        onEvent?(.failed(region?.identifier))
    }
}

@MainActor final class ArrivalNotificationService: ArrivalNotifying {
    private let center = UNUserNotificationCenter.current()
    func authorize() async throws -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return try await center.requestAuthorization(options: [.alert, .sound])
        default: return false
        }
    }
    func schedule(id: String) async throws {
        let status = await center.notificationSettings().authorizationStatus
        guard [.authorized, .provisional, .ephemeral].contains(status) else { throw CocoaError(.userCancelled) }
        let content = UNMutableNotificationContent()
        content.title = "Hospital arrival reminder"
        content.body = "You may be near your saved hospital. Open CardioSafe to review your visit details."
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: id, content: content,
                                                  trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
    func scheduleExit(id: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Hospital departure reminder"
        content.body = "You may have left your saved hospital area. Review your visit notes and any follow-up reminders in CardioSafe."
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
