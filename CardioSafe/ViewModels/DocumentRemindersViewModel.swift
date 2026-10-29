import Foundation
import Observation

@MainActor @Observable
final class DocumentRemindersViewModel {
    private(set) var reminders: [DocumentReminder] = []
    private(set) var deliveredIDs: Set<String> = []
    private(set) var busy = false
    private(set) var loaded = false
    var errorMessage: String?
    private let store: any DocumentReminderStoring
    private let scheduler: any DocumentReminderScheduling
    init(store: (any DocumentReminderStoring)? = nil, scheduler: (any DocumentReminderScheduling)? = nil) {
        self.store = store ?? LocalDocumentReminderStore()
        self.scheduler = scheduler ?? DocumentReminderService()
    }
    func refreshDelivery() async { deliveredIDs = await scheduler.deliveredIDs() }
    func load() {
        do { reminders = try store.load(); loaded = true; errorMessage = nil }
        catch { loaded = false; errorMessage = "Reminders couldn’t be loaded. Please retry." }
    }
    func items(for documentID: UUID) -> [DocumentReminder] {
        reminders.filter { $0.documentID == documentID }.sorted { $0.date < $1.date }
    }
    func save(documentID: UUID, existing: DocumentReminder?, title: String, date: Date, frequency: ReminderFrequency = .once) async -> Bool {
        guard loaded, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let currentReminders = try store.load()
            if let existing, currentReminders.first(where: { $0.id == existing.id }) != existing {
                errorMessage = "This reminder changed on another phone. Close this form and reopen it before editing."; return false
            }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 100 else { throw DocumentReminderError.title }
            guard frequency != .once || date > .now else { throw DocumentReminderError.date }
            var reminder = existing ?? DocumentReminder(documentID: documentID, title: trimmed, date: date)
            reminder.title = trimmed; reminder.date = date; reminder.completed = false; reminder.frequency = frequency
            // Persist first so an app restart can always show what was scheduled.
            let previous = currentReminders
            var updated = currentReminders.filter { $0.id != reminder.id }; updated.append(reminder)
            try store.save(updated)
            do { try await scheduler.schedule(reminder) }
            catch {
                try store.save(previous)
                throw error
            }
            reminders = try store.load(); errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The reminder couldn’t be saved. Please retry."
            return false
        }
    }
    func finish(_ reminder: DocumentReminder, remove: Bool) {
        guard loaded, !busy else { return }
        do {
            let currentReminders = try store.load()
            guard currentReminders.first(where: { $0.id == reminder.id }) == reminder else {
                errorMessage = "This reminder changed on another phone. Reopen reminders and retry."; return
            }
            var updated = currentReminders
            if remove { updated.removeAll { $0.id == reminder.id } }
            else if let index = updated.firstIndex(where: { $0.id == reminder.id }) { updated[index].completed = true }
            try store.save(updated)
            scheduler.cancel(reminder)
            deliveredIDs.remove(reminder.notificationID)
            reminders = try store.load(); errorMessage = nil
        } catch { errorMessage = "The reminder couldn’t be updated. Please retry." }
    }
}
