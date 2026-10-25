import Foundation

@MainActor
protocol AccountServicing {
    var isConfigured: Bool { get }
    func currentAccount() async throws -> AppAccount?
    func signIn(email: String, password: String) async throws -> AppAccount
    func register(email: String, password: String) async throws -> AppAccount
    func signOut() throws
    func sendVerification() async throws
}

enum AccountServiceError: LocalizedError {
    case notConfigured, invalidCredentials, emailInUse, weakPassword, network, failed
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Account services aren’t connected on this installation yet."
        case .invalidCredentials: "The email or password could not be verified."
        case .emailInUse: "An account already uses this email. Try signing in."
        case .weakPassword: "Choose a stronger password with at least eight characters."
        case .network: "Check your connection and try again."
        case .failed: "The account request could not be completed. Please try again."
        }
    }
}
