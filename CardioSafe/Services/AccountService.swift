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
    case notConfigured, invalidCredentials, emailInUse, weakPassword, network, failed, secureStorage, disabled, unavailable, rateLimited
    case serviceFailure(Int)
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Account services aren’t connected on this installation yet."
        case .invalidCredentials: "The email or password could not be verified."
        case .emailInUse: "An account already uses this email. Try signing in."
        case .weakPassword: "Choose a stronger password with at least eight characters."
        case .network: "Check your connection and try again."
        case .secureStorage: "Your account request reached Firebase, but this installation couldn’t save the sign-in securely. Try a correctly signed build."
        case .disabled: "This account is disabled. Contact the administrator."
        case .unavailable: "Email/password authentication is unavailable. Check the Firebase configuration."
        case .rateLimited: "Too many attempts. Wait a while before trying again."
        case .serviceFailure(let code): "Sign-in could not finish (error \(code)). If you just registered, try signing in with the same email."
        case .failed: "The account request could not be completed. Please try again."
        }
    }
}
