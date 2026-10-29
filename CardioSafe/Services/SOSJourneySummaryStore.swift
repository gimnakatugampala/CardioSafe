import Foundation

struct SOSJourneySummary: Identifiable, Codable {
    let id: String
    let hospital: String
    let assignedAt: Date?
    let pickedUpAt: Date?
    let completedAt: Date
}

@MainActor
struct SOSJourneySummaryStore {
    var root = URL.applicationSupportDirectory.appendingPathComponent("SOSHistory")
    var syncEnabled = true
    private func directory(ownerID: String) -> URL {
        let name = Data(ownerID.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return root.appendingPathComponent(name)
    }
    func save(_ summary: SOSJourneySummary, ownerID: String) throws {
        guard !summary.id.isEmpty, summary.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw CocoaError(.fileWriteInvalidFileName) }
        if syncEnabled && root == URL.applicationSupportDirectory.appendingPathComponent("SOSHistory") {
            try AccountSyncCache.shared.put(summary, owner: ownerID, kind: "sosSummary", key: summary.id)
        }
        let folder = directory(ownerID: ownerID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(summary).write(to: folder.appendingPathComponent(summary.id + ".json"), options: [.atomic, .completeFileProtection])
    }
    func load(ownerID: String) throws -> [SOSJourneySummary] {
        if syncEnabled && root == URL.applicationSupportDirectory.appendingPathComponent("SOSHistory") {
            let cloud = try AccountSyncCache.shared.values(SOSJourneySummary.self, owner: ownerID, kind: "sosSummary")
            if !cloud.isEmpty { return cloud.sorted { $0.completedAt > $1.completedAt } }
        }
        let folder = directory(ownerID: ownerID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(SOSJourneySummary.self, from: Data(contentsOf: $0)) }
            .sorted { $0.completedAt > $1.completedAt }
    }
}
