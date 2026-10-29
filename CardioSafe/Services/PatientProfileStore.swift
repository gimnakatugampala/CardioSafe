import Foundation

protocol PatientProfileStoring {
    func load(accountID: String) throws -> PatientProfile
    func save(_ profile: PatientProfile, accountID: String) throws
}

struct LocalPatientProfileStore: PatientProfileStoring {
    private let directory: URL
    private let syncEnabled: Bool
    init(directory: URL? = nil) {
        self.syncEnabled = directory == nil
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("PatientProfiles", isDirectory: true)
    }
    private func file(for accountID: String) -> URL {
        let name = Data(accountID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }
    func load(accountID: String) throws -> PatientProfile {
        if syncEnabled, let profile = try AccountSyncCache.shared.value(PatientProfile.self, owner: accountID, kind: "profile", key: "current") { return profile }
        let url = file(for: accountID)
        guard FileManager.default.fileExists(atPath: url.path) else { return PatientProfile() }
        return try JSONDecoder().decode(PatientProfile.self, from: Data(contentsOf: url))
    }
    func save(_ profile: PatientProfile, accountID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if syncEnabled { try AccountSyncCache.shared.put(profile, owner: accountID, kind: "profile", key: "current") }
        let data = try JSONEncoder().encode(profile)
        #if os(iOS)
        try data.write(to: file(for: accountID), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file(for: accountID), options: .atomic)
        #endif
    }
}
