import Foundation

@MainActor struct AccountAppearanceStore {
    private let cache: AccountSyncCache
    init(cache: AccountSyncCache? = nil) { self.cache = cache ?? .shared }
    func migrateExistingChoice(owner: String, defaults: UserDefaults = .standard) throws {
        let marker = "appearanceSyncFirstOwner"
        guard defaults.string(forKey: marker) == nil else { return }
        if try cache.record(owner, kind: "profile", key: "appearance") == nil,
           let existing = defaults.string(forKey: "appearancePreference"), Self.allowed.contains(existing) {
            try save(existing, owner: owner)
        }
        defaults.set(owner, forKey: marker)
    }
    func load(owner: String?) throws -> String {
        let value = try cache.value(String.self, owner: owner ?? "guest", kind: "profile", key: "appearance") ?? "system"
        guard Self.allowed.contains(value) else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }
    func save(_ value: String, owner: String?) throws {
        guard Self.allowed.contains(value) else { throw CocoaError(.fileWriteInvalidFileName) }
        try cache.put(value, owner: owner ?? "guest", kind: "profile", key: "appearance")
    }
    private static let allowed: Set<String> = ["system", "light", "dark"]
}
