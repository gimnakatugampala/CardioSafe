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
    var isActive: Bool { ["pending", "accepted", "assigned"].contains(status) }
}

@MainActor
protocol SOSJournaling {
    func load(ownerID: String) throws -> SavedSOS?
    func save(_ request: SavedSOS) throws
}

@MainActor
final class FileSOSJournal: SOSJournaling {
    private let directory: URL
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("ActiveSOS", isDirectory: true)) {
        self.directory = directory
    }
    private func url(ownerID: String) -> URL {
        let name = Data(ownerID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }
    func load(ownerID: String) throws -> SavedSOS? {
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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(request)
        #if os(iOS)
        try data.write(to: url(ownerID: request.ownerID), options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: url(ownerID: request.ownerID), options: .atomic)
        #endif
    }
}
