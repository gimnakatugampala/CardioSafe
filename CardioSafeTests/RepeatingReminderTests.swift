import Foundation
import Testing
@testable import CardioSafe

@MainActor struct RepeatingReminderTests {
    @Test func oldSavedRemindersDecodeAsOnce() throws {
        let reminder = DocumentReminder(documentID: UUID(), title: "Existing", date: .now)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(reminder)) as? [String: Any])
        object.removeValue(forKey: "frequency")
        let decoded = try JSONDecoder().decode(DocumentReminder.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == reminder && decoded.frequency == .once)
    }
    @Test func recurrenceUsesCalendarDayAndTimeRatherThanOriginalDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 8, minute: 30)))
        let now = start.addingTimeInterval(86400 + 60)
        var reminder = DocumentReminder(documentID: UUID(), title: "Review", date: start)
        reminder.frequency = .daily
        let daily = try #require(reminder.nextDate(after: now, calendar: calendar))
        #expect(calendar.component(.day, from: daily) == 28)
        #expect(calendar.component(.hour, from: daily) == 8 && calendar.component(.minute, from: daily) == 30)
        #expect(reminder.triggerComponents(calendar: calendar).year == nil)
        reminder.frequency = .weekly
        let weekly = try #require(reminder.nextDate(after: now, calendar: calendar))
        #expect(calendar.component(.weekday, from: weekly) == calendar.component(.weekday, from: start))
        #expect(weekly > now && weekly > daily)
        reminder.completed = true
        #expect(reminder.nextDate(after: now, calendar: calendar) == nil)
    }
    @Test func recurringEditsPersistAndCompletionStopsTheSchedule() async throws {
        let store = Store(), scheduler = Scheduler(), doc = UUID()
        let model = DocumentRemindersViewModel(store: store, scheduler: scheduler)
        model.load()
        #expect(await model.save(documentID: doc, existing: nil, title: "Daily review", date: .distantPast, frequency: .daily))
        let first = try #require(model.reminders.first)
        #expect(first.frequency == .daily)
        #expect(await model.save(documentID: doc, existing: first, title: "Weekly review", date: .now, frequency: .weekly))
        let weekly = try #require(model.reminders.first)
        #expect(weekly.id == first.id && weekly.frequency == .weekly)
        model.finish(weekly, remove: false)
        #expect(model.reminders.first?.completed == true && scheduler.cancelled == [first.id])
        #expect(model.reminders.first?.nextDate() == nil)
    }
    @Test func repeatChoiceRoundTripsAndTapPayloadRequiresAnOwner() throws {
        var reminder = DocumentReminder(documentID: UUID(), title: "Weekly", date: .now)
        reminder.frequency = .weekly
        #expect(try JSONDecoder().decode(DocumentReminder.self, from: JSONEncoder().encode(reminder)) == reminder)
        let payload: [AnyHashable: Any] = ["type": "document_reminder", "documentID": reminder.documentID.uuidString, "ownerID": "patient-a"]
        #expect(DocumentReminderRoute(payload: payload)?.documentID == reminder.documentID)
        #expect(DocumentReminderRoute(payload: ["type": "document_reminder", "documentID": reminder.documentID.uuidString]) == nil)
        #expect(DocumentReminderRoute(payload: ["type": "hospital_sos", "documentID": reminder.documentID.uuidString, "ownerID": "patient-a"]) == nil)
    }
}
