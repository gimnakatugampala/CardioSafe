import Foundation
import Testing
@testable import CardioSafe

@MainActor final class Store: DocumentReminderStoring {
    var values: [DocumentReminder] = []
    var fails = false
    func load() throws -> [DocumentReminder] { values }
    func save(_ reminders: [DocumentReminder]) throws {
        if fails { throw CocoaError(.fileWriteUnknown) }
        values = reminders
    }
}
@MainActor final class Scheduler: DocumentReminderScheduling {
    var scheduled: [DocumentReminder] = []
    var cancelled: [UUID] = []
    var fails = false
    func schedule(_ reminder: DocumentReminder) async throws {
        if fails { throw DocumentReminderError.permission }
        scheduled.append(reminder)
    }
    func cancel(_ reminder: DocumentReminder) { cancelled.append(reminder.id) }
}
@MainActor struct ReminderTests {
    @Test func createEditCompleteCancel() async {
        let store = Store(), scheduler = Scheduler(), doc = UUID()
        let model = DocumentRemindersViewModel(store: store, scheduler: scheduler)
        model.load()
        #expect(await model.save(documentID: doc, existing: nil, title: " Follow up ", date: .now.addingTimeInterval(600)))
        let first = model.reminders[0]
        #expect(first.title == "Follow up")
        #expect(model.items(for: UUID()).isEmpty)
        #expect(await model.save(documentID: doc, existing: first, title: "Updated", date: .now.addingTimeInterval(900)))
        #expect(model.reminders.count == 1)
        #expect(model.reminders[0].id == first.id)
        model.finish(model.reminders[0], remove: false)
        #expect(model.reminders[0].completed)
        #expect(scheduler.cancelled == [first.id])
        model.finish(model.reminders[0], remove: true)
        #expect(store.values.isEmpty)
    }
    @Test func permissionFailureRollsBackEdit() async {
        let store = Store(), scheduler = Scheduler(), doc = UUID()
        let original = DocumentReminder(documentID: doc, title: "Original", date: .now.addingTimeInterval(600))
        store.values = [original]; scheduler.fails = true
        let model = DocumentRemindersViewModel(store: store, scheduler: scheduler); model.load()
        #expect(await !model.save(documentID: doc, existing: original, title: "Change", date: .now.addingTimeInterval(900)))
        #expect(store.values == [original]); #expect(model.reminders == [original])
        #expect(model.errorMessage != nil)
    }
    @Test func validationAndWriteFailureNeverSchedule() async {
        let store = Store(), scheduler = Scheduler()
        let model = DocumentRemindersViewModel(store: store, scheduler: scheduler); model.load()
        #expect(await !model.save(documentID: UUID(), existing: nil, title: " ", date: .now.addingTimeInterval(600)))
        #expect(await !model.save(documentID: UUID(), existing: nil, title: "Past", date: .distantPast))
        store.fails = true
        #expect(await !model.save(documentID: UUID(), existing: nil, title: "Valid", date: .now.addingTimeInterval(600)))
        #expect(scheduler.scheduled.isEmpty)
    }
    @Test func fileRoundTripAndCorruption() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalDocumentReminderStore(url: folder.appendingPathComponent("reminders.json"))
        #expect(try store.load().isEmpty)
        let reminder = DocumentReminder(documentID: UUID(), title: "Review report", date: .now)
        try store.save([reminder]); #expect(try store.load() == [reminder])
        try Data("invalid".utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
    }
}
