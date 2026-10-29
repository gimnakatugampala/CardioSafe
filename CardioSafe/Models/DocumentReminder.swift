import Foundation

struct DocumentReminder: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let documentID: UUID
    var title: String
    var date: Date
    var completed = false
    var frequency: ReminderFrequency = .once
    private enum CodingKeys: String, CodingKey { case id, documentID, title, date, completed, frequency }
    var notificationID: String { "cardiosafe.document.\(id.uuidString)" }
}

enum ReminderFrequency: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekly
    var id: String { rawValue }
    var title: String { switch self { case .once: "Once"; case .daily: "Daily"; case .weekly: "Weekly" } }
}

extension DocumentReminder {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        documentID = try values.decode(UUID.self, forKey: .documentID)
        title = try values.decode(String.self, forKey: .title)
        date = try values.decode(Date.self, forKey: .date)
        completed = try values.decode(Bool.self, forKey: .completed)
        frequency = try values.decodeIfPresent(ReminderFrequency.self, forKey: .frequency) ?? .once
    }
    func triggerComponents(calendar: Calendar = .current) -> DateComponents {
        switch frequency {
        case .once: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        case .daily: calendar.dateComponents([.hour, .minute], from: date)
        case .weekly: calendar.dateComponents([.weekday, .hour, .minute], from: date)
        }
    }
    func nextDate(after now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard !completed else { return nil }
        if frequency == .once { return date > now ? date : nil }
        return calendar.nextDate(after: now, matching: triggerComponents(calendar: calendar), matchingPolicy: .nextTime)
    }
}

@MainActor
protocol DocumentReminderStoring {
    func load() throws -> [DocumentReminder]
    func save(_ reminders: [DocumentReminder]) throws
}

@MainActor
final class LocalDocumentReminderStore: DocumentReminderStoring {
    var url: URL
    private let ownerID: String?
    private let syncEnabled: Bool
    private var knownIDs: Set<UUID> = []
    init(url: URL? = nil) {
        self.ownerID = AccountDataScope.ownerID
        self.syncEnabled = url == nil
        self.url = url ?? AccountDataScope.directory("Reminders").appendingPathComponent("DocumentReminders.json")
    }
    func load() throws -> [DocumentReminder] {
        if syncEnabled, let ownerID {
            let values = try AccountSyncCache.shared.values(DocumentReminder.self, owner: ownerID, kind: "reminder")
            knownIDs = Set(values.map(\.id)); return values
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([DocumentReminder].self, from: Data(contentsOf: url))
    }
    func save(_ reminders: [DocumentReminder]) throws {
        if syncEnabled, let ownerID {
            let existing = try AccountSyncCache.shared.values(DocumentReminder.self, owner: ownerID, kind: "reminder")
            for reminder in existing where knownIDs.contains(reminder.id) && !reminders.contains(where: { $0.id == reminder.id }) {
                try AccountSyncCache.shared.put(reminder, owner: ownerID, kind: "reminder", key: reminder.id.uuidString, deleted: true)
            }
            for reminder in reminders { try AccountSyncCache.shared.put(reminder, owner: ownerID, kind: "reminder", key: reminder.id.uuidString) }
            knownIDs = Set(reminders.map(\.id))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(reminders).write(to: url, options: [.atomic, .completeFileProtection])
    }
}
