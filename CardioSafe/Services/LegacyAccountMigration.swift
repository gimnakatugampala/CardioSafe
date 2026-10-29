import Foundation

@MainActor enum LegacyAccountMigration {
    static var hasClaimedRecords: Bool { FileManager.default.fileExists(atPath: URL.applicationSupportDirectory.appendingPathComponent("LegacyRecordsOwner.txt").path) }
    static func approve(owner: String) { UserDefaults.standard.set(owner, forKey: "LegacyMigrationApprovedOwner") }
    // Only the patient who already claimed this device's records may inherit its old plan.
    static func claimWalkingPlan(for owner: String) async throws {
        let marker = URL.applicationSupportDirectory.appendingPathComponent("LegacyRecordsOwner.txt")
        guard FileManager.default.fileExists(atPath: marker.path),
              try String(contentsOf: marker, encoding: .utf8) == owner else { return }
        let store = CoreDataWalkingPlanStore()
        guard try await store.loadPlan(for: owner) == nil,
              let oldPlan = try await store.loadPlan(for: "local-device") else { return }
        try Task.checkCancellation()
        try await store.savePlan(oldPlan, for: owner)
    }

    static func claim(for owner: String) async throws {
        let root = URL.applicationSupportDirectory
        let marker = root.appendingPathComponent("LegacyRecordsOwner.txt")
        if FileManager.default.fileExists(atPath: marker.path) {
            guard try String(contentsOf: marker, encoding: .utf8) == owner else { return }
            return
        }
        guard UserDefaults.standard.string(forKey: "LegacyMigrationApprovedOwner") == owner else { return }
        let cache = AccountSyncCache.shared
        let profile = try LocalPatientProfileStore(directory: root.appendingPathComponent("PatientProfiles")).load(accountID: owner)
        if !profile.fullName.isEmpty { try cache.put(profile, owner: owner, kind: "profile", key: "current") }
        let legacyWalks = CoreDataWalkingSessionStore()
        let originalWalks = try await legacyWalks.loadSessions(for: "local-device")
        let guestWalks = try await legacyWalks.loadSessions(for: "guest")
        let walks = originalWalks + guestWalks
        let accountWalks = AccountWalkingSessionStore()
        for walk in walks { try await accountWalks.saveSession(walk, for: owner) }
        let docFolders = [root.appendingPathComponent("ScannedDocuments"), cache.folder("guest").appendingPathComponent("ScannedDocuments")]
        for folder in docFolders {
            let legacyDocs = LocalScannedDocumentStore(directory: folder)
            for document in try legacyDocs.load() {
                let target = cache.folder(owner).appendingPathComponent("ScannedDocuments").appendingPathComponent(document.id.uuidString + ".pdf")
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: target.path) {
                    try Data(contentsOf: legacyDocs.url(for: document)).write(to: target, options: [.atomic, .completeFileProtection])
                }
                try cache.put(document, owner: owner, kind: "document", key: document.id.uuidString)
            }
        }
        let reminderURLs = [root.appendingPathComponent("DocumentReminders.json"), cache.folder("guest").appendingPathComponent("Reminders/DocumentReminders.json")]
        for url in reminderURLs {
            for reminder in try LocalDocumentReminderStore(url: url).load() {
                try cache.put(reminder, owner: owner, kind: "reminder", key: reminder.id.uuidString)
            }
        }
        let legacyOwner = Data(owner.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        let legacySOS = root.appendingPathComponent("ActiveSOS").appendingPathComponent(legacyOwner + ".json")
        if FileManager.default.fileExists(atPath: legacySOS.path) {
            let saved = try JSONDecoder().decode(SavedSOS.self, from: Data(contentsOf: legacySOS))
            guard saved.ownerID == owner else { throw CocoaError(.fileReadCorruptFile) }
            try cache.put(saved, owner: owner, kind: "activeSOS", key: "current")
        }
        for summary in try SOSJourneySummaryStore(syncEnabled: false).load(ownerID: owner) {
            try cache.put(summary, owner: owner, kind: "sosSummary", key: summary.id)
        }
        try Task.checkCancellation()
        try owner.write(to: marker, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: marker.path)
    }
}
