import Foundation
import Observation

@MainActor @Observable final class AccountDeletionViewModel {
    static let shared = AccountDeletionViewModel()
    static let pendingKey = "accountDeletionPendingOwner"
    private(set) var pendingOwner: String?
    private(set) var completed = false
    private(set) var busy = false
    private(set) var error: String?
    private(set) var message: String?
    var blocksDataAccess: Bool { pendingOwner != nil || completed }
    private let backend: any AccountDeleting
    private let defaults: UserDefaults
    private let suspendSync: () async -> Void
    init(backend: (any AccountDeleting)? = nil, defaults: UserDefaults = .standard, suspendSync: (() async -> Void)? = nil) {
        self.backend = backend ?? FirebaseAccountDeletionService(); self.defaults = defaults
        self.suspendSync = suspendSync ?? { await FirebaseAccountSync.shared.suspendForDeletion() }
        pendingOwner = defaults.string(forKey: Self.pendingKey)
    }
    func erase(password: String) async {
        guard !busy, !completed else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let owner = try await backend.verify(password: password)
            guard pendingOwner == nil || pendingOwner == owner else { throw AccountDeletionError.ownerChanged }
            try await backend.checkSOS(owner: owner)
            pendingOwner = owner; defaults.set(owner, forKey: Self.pendingKey)
            await suspendSync()
            message = "Deleting private account records…"
            try await backend.deleteCloud(owner: owner)
            try await backend.deleteLocal(owner: owner)
            try await backend.deleteIdentity(owner: owner)
            pendingOwner = nil; defaults.removeObject(forKey: Self.pendingKey)
            completed = true
            message = await backend.clearDatabaseCache() ?? "Account and private backups deleted. Close and reopen CardioSafe before using it again."
        } catch {
            self.error = pendingOwner == nil ? error.localizedDescription
                : "Deletion is incomplete and syncing is paused. Re-enter your password to continue. \(error.localizedDescription)"
        }
    }
}
