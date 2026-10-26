import Foundation

struct DocumentReminder: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let documentID: UUID
    var title: String
    var date: Date
    var completed = false
    var notificationID: String { "cardiosafe.document.\(id.uuidString)" }
}

@MainActor
protocol DocumentReminderStoring {
    func load() throws -> [DocumentReminder]
    func save(_ reminders: [DocumentReminder]) throws
}

@MainActor
struct LocalDocumentReminderStore: DocumentReminderStoring {
    var url = URL.applicationSupportDirectory.appendingPathComponent("DocumentReminders.json")
    func load() throws -> [DocumentReminder] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([DocumentReminder].self, from: Data(contentsOf: url))
    }
    func save(_ reminders: [DocumentReminder]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(reminders).write(to: url, options: [.atomic, .completeFileProtection])
    }
}
