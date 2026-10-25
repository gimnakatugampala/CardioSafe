import Foundation

struct DepartmentQueue: Identifiable, Equatable {
    let id: String
    let name: String
    let waitingCount: Int
    let updatedAt: Date?
    let isCached: Bool
    var isValid: Bool { !name.isEmpty && (0...9999).contains(waitingCount) }
}
