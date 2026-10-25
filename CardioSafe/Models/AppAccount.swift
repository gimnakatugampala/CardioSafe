import Foundation

struct AppAccount: Equatable {
    let id: String
    let email: String
    let isEmailVerified: Bool
    let role: Role
    let hospitalIDs: [String]
    enum Role: String { case patient, staff }
    var canManageQueues: Bool { role == .staff && isEmailVerified && !hospitalIDs.isEmpty }
}
