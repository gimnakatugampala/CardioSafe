import Foundation
import UserNotifications

@MainActor
protocol WalkingReminderServicing {
    func authorization() async -> ReminderAuthorization
    func requestPermission() async throws -> Bool
    func hasDailyReminder() async -> Bool
    func scheduleDaily(hour: Int, minute: Int) async throws
    func testDeliveryDate() async -> Date?
    func scheduleTest() async throws
    func cancelDaily()
}

enum ReminderAuthorization { case notDetermined, allowed, denied }

@MainActor
final class WalkingReminderService: WalkingReminderServicing {
    private let center = UNUserNotificationCenter.current()
    private let dailyID = "cardiosafe.walking.daily"
    func authorization() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorized, .provisional, .ephemeral: .allowed
        default: .denied
        }
    }
    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }
    func hasDailyReminder() async -> Bool {
        await center.pendingNotificationRequests().contains { $0.identifier == dailyID }
    }
    func scheduleDaily(hour: Int, minute: Int) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Your walking reminder"
        content.body = "Open CardioSafe to review your walking plan when you’re ready."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        try await center.add(UNNotificationRequest(identifier: dailyID, content: content, trigger: trigger))
    }
    func testDeliveryDate() async -> Date? {
        await center.deliveredNotifications()
            .filter { $0.request.identifier == "cardiosafe.walking.test" }
            .map(\.date).max()
    }
    func scheduleTest() async throws {
        let content = UNMutableNotificationContent()
        content.title = "CardioSafe test reminder"
        content.body = "Notifications are working. This is a demonstration reminder."
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: "cardiosafe.walking.test", content: content,
                                                  trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }
    func cancelDaily() {
        center.removePendingNotificationRequests(withIdentifiers: [dailyID])
        center.removeDeliveredNotifications(withIdentifiers: [dailyID])
    }
}

@MainActor
final class WalkingNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WalkingNotificationDelegate()
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let payload = response.notification.request.content.userInfo
        if let route = SOSNotificationRoute(payload: payload) {
            await MainActor.run { SOSNotificationRouter.shared.pending = route }
        } else if let route = DocumentReminderRoute(payload: payload) {
            await MainActor.run { DocumentReminderRouter.shared.pending = route }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
