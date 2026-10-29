import Foundation
import UserNotifications

@MainActor
protocol DocumentReminderScheduling {
    func schedule(_ reminder: DocumentReminder) async throws
    func cancel(_ reminder: DocumentReminder)
    func deliveredIDs() async -> Set<String>
}

extension DocumentReminderScheduling {
    func deliveredIDs() async -> Set<String> { [] }
}

@MainActor
struct DocumentReminderService: DocumentReminderScheduling {
    func schedule(_ reminder: DocumentReminder) async throws {
        let owner = AccountDataScope.ownerID ?? "guest"
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw DocumentReminderError.permission
        }
        guard owner == (AccountDataScope.ownerID ?? "guest") else { throw DocumentReminderError.accountChanged }
        guard reminder.nextDate() != nil else { throw DocumentReminderError.date }
        let content = UNMutableNotificationContent()
        content.title = "Your CardioSafe reminder"
        content.body = "Open Records to review your saved reminder."
        content.sound = .default
        content.userInfo = ["type": "document_reminder", "documentID": reminder.documentID.uuidString,
                            "ownerID": owner]
        let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.triggerComponents(), repeats: reminder.frequency != .once)
        try await center.add(UNNotificationRequest(identifier: reminder.notificationID, content: content, trigger: trigger))
        guard owner == (AccountDataScope.ownerID ?? "guest") else {
            cancel(reminder)
            throw DocumentReminderError.accountChanged
        }
    }
    func deliveredIDs() async -> Set<String> {
        Set(await UNUserNotificationCenter.current().deliveredNotifications().map { $0.request.identifier })
    }
    func cancel(_ reminder: DocumentReminder) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminder.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [reminder.notificationID])
    }
}

enum DocumentReminderError: LocalizedError {
    case permission, date, title, accountChanged
    var errorDescription: String? {
        switch self {
        case .accountChanged: "Your account changed. Reopen reminders before saving."
        case .permission: "Notifications are off. Allow CardioSafe notifications in Settings, then retry."
        case .date: "Choose a reminder time in the future."
        case .title: "Enter a reminder title of 1–100 characters."
        }
    }
}
