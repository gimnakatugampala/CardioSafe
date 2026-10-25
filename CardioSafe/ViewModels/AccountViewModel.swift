import Foundation
import Observation

@MainActor
@Observable
final class AccountViewModel {
    private(set) var account: AppAccount?
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var message: String?
    @ObservationIgnored private let service: any AccountServicing
    init(service: any AccountServicing) { self.service = service }
    var isConfigured: Bool { service.isConfigured }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do { account = try await service.currentAccount(); errorMessage = nil }
        catch { errorMessage = "Your account could not be refreshed. Check your connection." }
    }
    func authenticate(email: String, password: String, registering: Bool) async -> Bool {
        guard !isBusy else { return false }
        errorMessage = nil; message = nil
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), email.contains("."), !email.contains(" ") else {
            errorMessage = "Enter a valid email address."; return false
        }
        guard !password.isEmpty, !registering || password.count >= 8 else {
            errorMessage = registering ? "Use at least eight characters for your password." : "Enter your password."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            account = try await (registering ? service.register(email: email, password: password) : service.signIn(email: email, password: password))
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func signOut() {
        guard !isBusy else { return }
        do { try service.signOut(); account = nil; errorMessage = nil; message = nil }
        catch { errorMessage = "Sign out could not be completed. Please retry." }
    }
    func sendVerification() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await service.sendVerification(); message = "Verification email sent. Follow its link, then refresh your account."; errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
