import Foundation

struct SavedSOS: Codable, Equatable {
    let ownerID: String
    let requestID: String
    let destination: DispatchDestination
}

struct RestoredSOS {
    let saved: SavedSOS
    let status: String
    let assignedAt: Date?
    var pickedUpAt: Date? = nil
    var isActive: Bool { SOSJourneyStatus(rawValue: status)?.active == true }
}

@MainActor
protocol SOSJournaling {
    func load(ownerID: String) throws -> SavedSOS?
    func save(_ request: SavedSOS) throws
}

@MainActor
final class FileSOSJournal: SOSJournaling {
    private let directory: URL
    private let syncEnabled: Bool
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("ActiveSOS", isDirectory: true)) {
        self.syncEnabled = directory == URL.applicationSupportDirectory.appendingPathComponent("ActiveSOS", isDirectory: true)
        self.directory = directory
    }
    private func url(ownerID: String) -> URL {
        let name = Data(ownerID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }
    func load(ownerID: String) throws -> SavedSOS? {
        if syncEnabled, let cloud = try AccountSyncCache.shared.value(SavedSOS.self, owner: ownerID, kind: "activeSOS", key: "current") {
            guard cloud.ownerID == ownerID else { throw CocoaError(.fileReadCorruptFile) }
            return cloud
        }
        let path = url(ownerID: ownerID)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let saved = try JSONDecoder().decode(SavedSOS.self, from: Data(contentsOf: path))
        guard saved.ownerID == ownerID, !saved.requestID.isEmpty,
              saved.requestID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              saved.destination.hospitalID == "demo-asiri-central" else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return saved
    }
    func save(_ request: SavedSOS) throws {
        if syncEnabled { try AccountSyncCache.shared.put(request, owner: request.ownerID, kind: "activeSOS", key: "current") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(request)
        #if os(iOS)
        try data.write(to: url(ownerID: request.ownerID), options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: url(ownerID: request.ownerID), options: .atomic)
        #endif
    }
}
