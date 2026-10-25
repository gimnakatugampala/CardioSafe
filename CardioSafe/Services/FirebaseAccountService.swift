import Foundation
import FirebaseCore
import FirebaseAuth

@MainActor
enum FirebaseSetup {
    static func configure() {
        guard FirebaseApp.app() == nil,
              let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path),
              options.bundleID == Bundle.main.bundleIdentifier,
              options.projectID == "cardio-safe",
              options.apiKey?.isEmpty == false else { return }
        FirebaseApp.configure(options: options)
    }
    static var isConfigured: Bool { FirebaseApp.app() != nil }
}

@MainActor
final class FirebaseAccountService: AccountServicing {
    var isConfigured: Bool { FirebaseSetup.isConfigured }
    func currentAccount() async throws -> AppAccount? {
        guard isConfigured else { return nil }
        guard let user = Auth.auth().currentUser else { return nil }
        try await user.reload()
        return try await account(user)
    }
    func signIn(email: String, password: String) async throws -> AppAccount {
        guard isConfigured else { throw AccountServiceError.notConfigured }
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return try await account(result.user)
        } catch { throw mapped(error) }
    }
    func register(email: String, password: String) async throws -> AppAccount {
        guard isConfigured else { throw AccountServiceError.notConfigured }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            return try await account(result.user)
        } catch { throw mapped(error) }
    }
    func signOut() throws {
        guard isConfigured else { return }
        try Auth.auth().signOut()
    }
    func sendVerification() async throws {
        guard isConfigured, let user = Auth.auth().currentUser else { throw AccountServiceError.notConfigured }
        do { try await user.sendEmailVerification() } catch { throw mapped(error) }
    }
    private func account(_ user: User) async throws -> AppAccount {
        let token = try await user.getIDTokenResult(forcingRefresh: true)
        let role: AppAccount.Role = token.claims["role"] as? String == "staff" ? .staff : .patient
        let hospitals = role == .staff ? (token.claims["hospitalIDs"] as? [String] ?? []) : []
        return AppAccount(id: user.uid, email: user.email ?? "", isEmailVerified: user.isEmailVerified,
                          role: role, hospitalIDs: hospitals)
    }
    private func mapped(_ error: Error) -> AccountServiceError {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .wrongPassword, .invalidEmail, .userNotFound, .invalidCredential: .invalidCredentials
        case .emailAlreadyInUse: .emailInUse
        case .weakPassword: .weakPassword
        case .networkError: .network
        case .keychainError: .secureStorage
        case .userDisabled: .disabled
        case .operationNotAllowed, .appNotAuthorized, .invalidAPIKey: .unavailable
        case .tooManyRequests: .rateLimited
        default: .serviceFailure((error as NSError).code)
        }
    }
}
