import Foundation
import Testing
import UserNotifications
@testable import CardioSafe

@MainActor
struct DocumentReminderNotificationTests {
    @Test func completionAndCancellationRemoveSystemRequests() async throws {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        try #require(status == .authorized || status == .provisional || status == .ephemeral,
                     "Enable notifications in this simulator before running the system-queue check.")
        let scheduler = DocumentReminderService()
        let store = Store()
        let model = DocumentRemindersViewModel(store: store, scheduler: scheduler)
        model.load()
        let doc = UUID()
        let saved = await model.save(documentID: doc, existing: nil, title: "Notification queue check", date: .now.addingTimeInterval(3600))
        #expect(saved)
        let first = try #require(model.reminders.first)
        defer { scheduler.cancel(first) }
        var pending = await center.pendingNotificationRequests()
        #expect(pending.contains { $0.identifier == first.notificationID })
        let edited = await model.save(documentID: doc, existing: first, title: "Updated queue check", date: .now.addingTimeInterval(7200), frequency: .daily)
        #expect(edited)
        pending = await center.pendingNotificationRequests()
        #expect(pending.filter { $0.identifier == first.notificationID }.count == 1)
        let dailyTrigger = try #require(pending.first { $0.identifier == first.notificationID }?.trigger as? UNCalendarNotificationTrigger)
        #expect(dailyTrigger.repeats && dailyTrigger.dateComponents.weekday == nil && dailyTrigger.dateComponents.year == nil)
        let daily = try #require(model.reminders.first)
        #expect(await model.save(documentID: doc, existing: daily, title: "Weekly queue check", date: .now, frequency: .weekly))
        pending = await center.pendingNotificationRequests()
        let weeklyTrigger = try #require(pending.first { $0.identifier == first.notificationID }?.trigger as? UNCalendarNotificationTrigger)
        #expect(weeklyTrigger.repeats && weeklyTrigger.dateComponents.weekday != nil && weeklyTrigger.dateComponents.year == nil)
        #expect(pending.filter { $0.identifier == first.notificationID }.count == 1)
        model.finish(model.reminders[0], remove: false)
        pending = await center.pendingNotificationRequests()
        #expect(!pending.contains { $0.identifier == first.notificationID })
        let secondSaved = await model.save(documentID: doc, existing: nil, title: "Cancellation queue check", date: .now.addingTimeInterval(3600))
        #expect(secondSaved)
        let second = try #require(model.reminders.first { !$0.completed })
        defer { scheduler.cancel(second) }
        model.finish(second, remove: true)
        pending = await center.pendingNotificationRequests()
        #expect(!pending.contains { $0.identifier == second.notificationID })
    }
}
