import Foundation
import Observation

@MainActor @Observable
final class DocumentRemindersViewModel {
    private(set) var reminders: [DocumentReminder] = []
    private(set) var busy = false
    private(set) var loaded = false
    var errorMessage: String?
    private let store: any DocumentReminderStoring
    private let scheduler: any DocumentReminderScheduling
    init(store: (any DocumentReminderStoring)? = nil, scheduler: (any DocumentReminderScheduling)? = nil) {
        self.store = store ?? LocalDocumentReminderStore()
        self.scheduler = scheduler ?? DocumentReminderService()
    }
    func load() {
        do { reminders = try store.load(); loaded = true; errorMessage = nil }
        catch { loaded = false; errorMessage = "Reminders couldn’t be loaded. Please retry." }
    }
    func items(for documentID: UUID) -> [DocumentReminder] {
        reminders.filter { $0.documentID == documentID }.sorted { $0.date < $1.date }
    }
    func save(documentID: UUID, existing: DocumentReminder?, title: String, date: Date) async -> Bool {
        guard loaded, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 100 else { throw DocumentReminderError.title }
            guard date > .now else { throw DocumentReminderError.date }
            var reminder = existing ?? DocumentReminder(documentID: documentID, title: trimmed, date: date)
            reminder.title = trimmed; reminder.date = date; reminder.completed = false
            // Persist first so an app restart can always show what was scheduled.
            let previous = reminders
            var updated = reminders.filter { $0.id != reminder.id }; updated.append(reminder)
            try store.save(updated)
            do { try await scheduler.schedule(reminder) }
            catch {
                try store.save(previous)
                throw error
            }
            reminders = updated; errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The reminder couldn’t be saved. Please retry."
            return false
        }
    }
    func finish(_ reminder: DocumentReminder, remove: Bool) {
        guard loaded, !busy else { return }
        do {
            var updated = reminders
            if remove { updated.removeAll { $0.id == reminder.id } }
            else if let index = updated.firstIndex(where: { $0.id == reminder.id }) { updated[index].completed = true }
            try store.save(updated)
            scheduler.cancel(reminder)
            reminders = updated; errorMessage = nil
        } catch { errorMessage = "The reminder couldn’t be updated. Please retry." }
    }
}
