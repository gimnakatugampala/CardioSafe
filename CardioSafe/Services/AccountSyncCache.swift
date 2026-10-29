import Foundation

struct AccountSyncRecord: Codable, Identifiable {
    let kind: String
    let key: String
    var payload: Data
    var version: String
    var baseVersion: String?
    var deleted: Bool
    var pending: Bool
    var id: String { kind + "_" + key }
    func conflicts(with remoteVersion: String, inFlightVersion: String?) -> Bool {
        pending && version != remoteVersion && baseVersion != remoteVersion && inFlightVersion != remoteVersion
    }
}

@MainActor
final class AccountSyncCache {
    static let shared = AccountSyncCache()
    static let kinds: Set<String> = ["profile", "walk", "document", "reminder", "activeSOS", "sosSummary"]
    let root: URL
    init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("AccountSync")) { self.root = root }
    func folder(_ owner: String) -> URL {
        let name = Data(owner.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return root.appendingPathComponent(name)
    }
    func records(_ owner: String) throws -> [AccountSyncRecord] {
        let directory = folder(owner)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(AccountSyncRecord.self, from: Data(contentsOf: $0)) }
    }
    func record(_ owner: String, kind: String, key: String) throws -> AccountSyncRecord? {
        guard Self.kinds.contains(kind), Self.validKey(key) else { throw CocoaError(.fileReadCorruptFile) }
        let url = folder(owner).appendingPathComponent(kind + "_" + key + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(AccountSyncRecord.self, from: Data(contentsOf: url))
    }
    func write(_ record: AccountSyncRecord, owner: String) throws {
        guard Self.kinds.contains(record.kind), Self.validKey(record.key) else { throw CocoaError(.fileWriteInvalidFileName) }
        let directory = folder(owner)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: directory.appendingPathComponent(record.id + ".json"), options: [.atomic, .completeFileProtection])
    }
    static func validKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 128 && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
    func put<T: Encodable>(_ value: T, owner: String, kind: String, key: String, deleted: Bool = false) throws {
        let old = try record(owner, kind: kind, key: key)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        if old?.payload == data && old?.deleted == deleted { return }
        let next = AccountSyncRecord(kind: kind, key: key, payload: data, version: UUID().uuidString,
            baseVersion: old?.pending == true ? old?.baseVersion : old?.version, deleted: deleted, pending: true)
        try write(next, owner: owner)
        NotificationCenter.default.post(name: .accountDataChanged, object: owner)
    }
    func values<T: Decodable>(_ type: T.Type, owner: String, kind: String) throws -> [T] {
        try records(owner).filter { $0.kind == kind && !$0.deleted }.map { try JSONDecoder().decode(type, from: $0.payload) }
    }
    func value<T: Decodable>(_ type: T.Type, owner: String, kind: String, key: String) throws -> T? {
        guard let record = try record(owner, kind: kind, key: key), !record.deleted else { return nil }
        return try JSONDecoder().decode(type, from: record.payload)
    }
}

extension Notification.Name {
    static let accountDataChanged = Notification.Name("CardioSafeAccountDataChanged")
    static let accountDataRestored = Notification.Name("CardioSafeAccountDataRestored")
}

@MainActor enum AccountDataScope {
    static var ownerID: String?
    static func directory(_ name: String) -> URL {
        AccountSyncCache.shared.folder(ownerID ?? "guest").appendingPathComponent(name)
    }
}
