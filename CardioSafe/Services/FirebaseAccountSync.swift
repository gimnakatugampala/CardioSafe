import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

@MainActor @Observable
final class FirebaseAccountSync {
    static let shared = FirebaseAccountSync()
    private(set) var ownerID: String?
    var migrationError: String?
    private(set) var notificationStatus: String?
    private(set) var status = "Sign in to sync your records"
    private(set) var conflicts: [AccountSyncRecord] = []
    private(set) var busy = false
    private var listener: ListenerRegistration?
    private var job: Task<Void, Never>?
    private var generation = UUID()
    private let cache: AccountSyncCache
    init(cache: AccountSyncCache? = nil) { self.cache = cache ?? .shared }
    func suspendForDeletion() async {
        let previous = job
        stop()
        await previous?.value
    }
    func waitForUploads() async { await job?.value }
    func stop() { generation = UUID(); job?.cancel(); job = nil; listener?.remove(); listener = nil; busy = false; ownerID = nil }
    private var inFlightVersions: [String: String] = [:]
    private var observing = false
    private var connectionConfirmed = false
    private let chunkSize = 450_000
    private func collection(_ owner: String) -> CollectionReference { Firestore.firestore().collection("users").document(owner).collection("records") }
    private func chunks(_ owner: String) -> CollectionReference { Firestore.firestore().collection("users").document(owner).collection("recordChunks") }

    func start(owner: String?) async {
        guard UserDefaults.standard.string(forKey: AccountDeletionViewModel.pendingKey) == nil else {
            stop(); status = "Account deletion incomplete · Sync paused"; return
        }
        generation = UUID(); let expected = generation; job?.cancel(); job = nil; listener?.remove(); listener = nil
        ownerID = owner; AccountDataScope.ownerID = owner; conflicts = []; inFlightVersions = [:]; busy = false; connectionConfirmed = false
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("cardiosafe.document.") }
        guard generation == expected else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
        guard let owner, FirebaseSetup.isConfigured else { status = "Sign in to sync your records"; return }
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(forName: .accountDataChanged, object: nil, queue: .main) { [weak self] notification in
                let changedOwner = notification.object as? String
                Task { @MainActor [weak self] in if changedOwner == self?.ownerID { self?.sync() } }
            }
        }
        status = "Checking cloud records…"
        do {
            let snapshot = try await collection(owner).getDocuments(source: .server)
            for doc in snapshot.documents { try await receive(doc, owner: owner, expected: expected) }
            if generation == expected { connectionConfirmed = true }
        } catch { if generation == expected { status = "Offline or cloud access unavailable · Local changes are kept for retry" } }
        guard generation == expected else { return }
        listener = collection(owner).addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, self.generation == expected else { return }
                if error != nil { self.status = "Cloud sync unavailable · Check your connection and private-data rules"; return }
                guard let snapshot else { return }
                if snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites {
                    self.connectionConfirmed = false
                    self.status = snapshot.metadata.hasPendingWrites
                        ? "Sync pending · Local changes are kept until the cloud confirms them"
                        : "Cloud connection unconfirmed · Local records remain available"
                    return
                }
                do {
                    for doc in snapshot.documents { try await self.receive(doc, owner: owner, expected: expected) }
                    guard self.generation == expected else { return }
                    self.connectionConfirmed = true
                    await self.restoreReminders(owner: owner, expected: expected)
                    guard self.generation == expected else { return }
                    if !self.busy {
                        self.status = self.conflicts.isEmpty
                            ? "Records synced to your account · PDF files stay on this phone"
                            : "Conflicting edits need your choice"
                    }
                    NotificationCenter.default.post(name: .accountDataRestored, object: owner)
                } catch { self.status = "Some cloud records could not be restored · Retry sync" }
            }
        }
        sync()
    }
    private func receive(_ doc: QueryDocumentSnapshot, owner: String, expected: UUID) async throws {
        guard generation == expected, ownerID == owner else { return }
        let fields = doc.data()
        guard let kind = fields["kind"] as? String, AccountSyncCache.kinds.contains(kind),
              let key = fields["key"] as? String, AccountSyncCache.validKey(key), doc.documentID == kind + "_" + key,
              let version = fields["version"] as? String, UUID(uuidString: version) != nil,
              let count = fields["parts"] as? Int, (0...64).contains(count), let deleted = fields["deleted"] as? Bool else { throw CocoaError(.fileReadCorruptFile) }
        let local = try cache.record(owner, kind: kind, key: key)
        if local?.version == version {
            if var local, local.pending { local.pending = false; try cache.write(local, owner: owner) }
            return
        }
        if let local, local.pending {
            if local.conflicts(with: version, inFlightVersion: inFlightVersions[local.id]) && !conflicts.contains(where: { $0.id == local.id }) { conflicts.append(local); status = "Conflicting edits need your choice" }
            return
        }
        var data = Data()
        if !deleted {
            for index in 0..<count {
                let part = try await chunks(owner).document(version + "_" + String(index)).getDocument(source: .server)
                guard let bytes = part.data()?["bytes"] as? Data, bytes.count <= chunkSize else { throw CocoaError(.fileReadCorruptFile) }
                data.append(bytes)
            }
        }
        guard generation == expected, ownerID == owner else { return }
        try cache.write(AccountSyncRecord(kind: kind, key: key, payload: data, version: version, baseVersion: version, deleted: deleted, pending: false), owner: owner)
    }
    func sync() {
        guard job == nil, let owner = ownerID else { return }
        let expected = generation
        job = Task { [weak self] in
            guard let self else { return }
            self.busy = true
            var failed = false
            defer {
                if self.generation == expected {
                    self.busy = false; self.job = nil
                    if !failed, (try? self.cache.records(owner).contains(where: { candidate in candidate.pending && !self.conflicts.contains(where: { $0.id == candidate.id }) })) == true { self.sync() }
                }
            }
            do {
                while self.generation == expected, !Task.isCancelled {
                    guard let record = try self.cache.records(owner).first(where: { candidate in candidate.pending && !self.conflicts.contains(where: { $0.id == candidate.id }) }) else { break }
                    try await self.upload(record, owner: owner, expected: expected)
                }
                guard self.generation == expected else { return }
                await self.restoreReminders(owner: owner, expected: expected)
                self.status = !self.conflicts.isEmpty ? "Conflicting edits need your choice" : self.connectionConfirmed ? "Records synced to your account · PDF files stay on this phone" : "Cloud restore not confirmed · Check connection and private-data rules, then retry"
                NotificationCenter.default.post(name: .accountDataRestored, object: owner)
            } catch {
                failed = true
                if (error as NSError).domain == "CardioSafeSyncConflict", self.generation == expected {
                    self.status = "Conflicting edits detected · Retry sync to review the cloud version"
                } else if self.generation == expected { self.status = "Sync pending · Local changes are safe. Check connection or private-data rules, then retry." }
            }
        }
    }
    private func upload(_ record: AccountSyncRecord, owner: String, expected: UUID) async throws {
        guard Auth.auth().currentUser?.uid == owner, generation == expected else { throw CocoaError(.userCancelled) }
        inFlightVersions[record.id] = record.version
        defer { if inFlightVersions[record.id] == record.version { inFlightVersions.removeValue(forKey: record.id) } }
        let data = record.deleted ? Data() : record.payload
        let count = (data.count + chunkSize - 1) / chunkSize
        guard count <= 64 else { throw CocoaError(.fileWriteOutOfSpace) }
        for start in stride(from: 0, to: count, by: 8) {
            let batch = Firestore.firestore().batch()
            for index in start..<min(start + 8, count) {
                let bytes = data.subdata(in: index * chunkSize..<min((index + 1) * chunkSize, data.count))
                batch.setData(["bytes": bytes, "version": record.version], forDocument: chunks(owner).document(record.version + "_" + String(index)))
            }
            try await batch.commit()
            guard generation == expected else { throw CocoaError(.userCancelled) }
        }
        let ref = collection(owner).document(record.id)
        let fields: [String: Any] = ["kind": record.kind, "key": record.key, "version": record.version, "parts": count,
                                     "deleted": record.deleted, "updatedAt": FieldValue.serverTimestamp()]
        _ = try await Firestore.firestore().runTransaction { transaction, errorPointer -> Any? in
            do {
                let old = try transaction.getDocument(ref)
                let remoteVersion = old.data()?["version"] as? String
                guard remoteVersion == record.baseVersion || remoteVersion == record.version else {
                    errorPointer?.pointee = NSError(domain: "CardioSafeSyncConflict", code: 409); return nil
                }
                transaction.setData(fields, forDocument: ref)
                return nil
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        guard generation == expected else { return }
        if var latest = try cache.record(owner, kind: record.kind, key: record.key) {
            if latest.version == record.version { latest.pending = false; latest.baseVersion = record.version }
            else { latest.baseVersion = record.version }
            try cache.write(latest, owner: owner)
        }
    }
    private func restoreReminders(owner: String, expected: UUID) async {
        guard generation == expected else { return }
        let center = UNUserNotificationCenter.current()
        let permission = await center.notificationSettings().authorizationStatus
        guard generation == expected else { return }
        guard [.authorized, .provisional, .ephemeral].contains(permission) else {
            notificationStatus = "Reminders restore with your account. Allow notifications on this phone to receive alerts."
            return
        }
        do {
            let reminders = try cache.values(DocumentReminder.self, owner: owner, kind: "reminder").filter { $0.nextDate() != nil }
            let pending = await center.pendingNotificationRequests()
            guard generation == expected else { return }
            let obsolete = pending.filter { request in request.identifier.hasPrefix("cardiosafe.document.") && !reminders.contains(where: { $0.notificationID == request.identifier }) }
            center.removePendingNotificationRequests(withIdentifiers: obsolete.map(\.identifier))
            for reminder in reminders {
                guard generation == expected else { return }
                if let existing = pending.first(where: { $0.identifier == reminder.notificationID }),
                   existing.content.userInfo["ownerID"] as? String == owner,
                   existing.content.userInfo["documentID"] as? String == reminder.documentID.uuidString,
                   let trigger = existing.trigger as? UNCalendarNotificationTrigger,
                   trigger.repeats == (reminder.frequency != .once), trigger.dateComponents == reminder.triggerComponents() { continue }
                try await DocumentReminderService().schedule(reminder)
            }
            notificationStatus = nil
        } catch { notificationStatus = "Reminder details are restored, but some alerts could not be scheduled on this phone." }
    }
    func resolve(_ record: AccountSyncRecord, keepLocal: Bool) async {
        guard let owner = ownerID else { return }
        do {
            let remote = try await collection(owner).document(record.id).getDocument(source: .server)
            let version = remote.data()?["version"] as? String
            if keepLocal {
                guard var current = try cache.record(owner, kind: record.kind, key: record.key) else { return }
                current.baseVersion = version; try cache.write(current, owner: owner)
            } else {
                // Preserve the local edit in a protected backup before choosing the cloud copy.
                let backup = cache.folder(owner).appendingPathComponent("ConflictBackups")
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                try JSONEncoder().encode(record).write(to: backup.appendingPathComponent(record.version + ".json"), options: [.atomic, .completeFileProtection])
                guard let latest = try cache.record(owner, kind: record.kind, key: record.key) else { return }
                try JSONEncoder().encode(latest).write(to: backup.appendingPathComponent(latest.version + ".json"), options: [.atomic, .completeFileProtection])
                var current = latest; current.pending = false; current.version = "restore"; try cache.write(current, owner: owner)
            }
            conflicts.removeAll { $0.id == record.id }
            let currentOwner = ownerID
            await start(owner: currentOwner)
        } catch { status = "Conflict could not be resolved. Local data is preserved." }
    }
}
