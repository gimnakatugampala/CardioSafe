import Foundation
import UserNotifications

@MainActor
protocol DocumentReminderScheduling {
    func schedule(_ reminder: DocumentReminder) async throws
    func cancel(_ reminder: DocumentReminder)
}

@MainActor
struct DocumentReminderService: DocumentReminderScheduling {
    func schedule(_ reminder: DocumentReminder) async throws {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw DocumentReminderError.permission
        }
        guard reminder.date > .now else { throw DocumentReminderError.date }
        let content = UNMutableNotificationContent()
        content.title = "Your CardioSafe reminder"
        content.body = "Open Records to review your saved reminder."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: reminder.date), repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.notificationID, content: content, trigger: trigger))
    }
    func cancel(_ reminder: DocumentReminder) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminder.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [reminder.notificationID])
    }
}

enum DocumentReminderError: LocalizedError {
    case permission, date, title
    var errorDescription: String? {
        switch self {
        case .permission: "Notifications are off. Allow CardioSafe notifications in Settings, then retry."
        case .date: "Choose a reminder time in the future."
        case .title: "Enter a reminder title of 1–100 characters."
        }
    }
}
