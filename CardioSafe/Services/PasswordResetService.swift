import Foundation
import FirebaseAuth

@MainActor protocol PasswordResetServicing {
    func requestReset(email: String) async throws
}

@MainActor struct FirebasePasswordResetService: PasswordResetServicing {
    func requestReset(email: String) async throws {
        guard FirebaseSetup.isConfigured else { throw AccountServiceError.notConfigured }
        do { try await Auth.auth().sendPasswordReset(withEmail: email) }
        catch {
            switch AuthErrorCode(rawValue: (error as NSError).code) {
            case .userNotFound: return // Keep the response private regardless of account existence.
            case .invalidEmail: throw PasswordRecoveryError.invalidEmail
            case .networkError: throw AccountServiceError.network
            case .tooManyRequests: throw AccountServiceError.rateLimited
            case .operationNotAllowed, .invalidAPIKey, .appNotAuthorized: throw AccountServiceError.unavailable
            default: throw PasswordRecoveryError.requestFailed
            }
        }
    }
}

enum PasswordRecoveryError: LocalizedError {
    case invalidEmail, requestFailed
    var errorDescription: String? {
        switch self {
        case .invalidEmail: "Enter a valid email address."
        case .requestFailed: "Reset instructions could not be requested. Please try again."
        }
    }
}
