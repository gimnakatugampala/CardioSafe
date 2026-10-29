import Foundation
import Observation

@MainActor @Observable final class PasswordRecoveryViewModel {
    private(set) var isSending = false
    private(set) var message: String?
    private(set) var errorMessage: String?
    private(set) var retryAfter: Date?
    @ObservationIgnored private let service: any PasswordResetServicing
    init(service: (any PasswordResetServicing)? = nil) { self.service = service ?? FirebasePasswordResetService() }

    static func validEmail(_ value: String) -> Bool {
        guard value.count <= 254, !value.contains(where: { $0.isWhitespace }),
              let separator = value.firstIndex(of: "@"), separator == value.lastIndex(of: "@") else { return false }
        let local = value[..<separator], domain = value[value.index(after: separator)...]
        return !local.isEmpty && local.count <= 64
            && local.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "!#$%&' *+-/=?^_`{|}~.".replacingOccurrences(of: " ", with: "").contains($0)) } && !local.hasPrefix(".") && !local.hasSuffix(".")
            && !local.contains("..") && domain.split(separator: ".", omittingEmptySubsequences: false).count >= 2
            && domain.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-")
                    && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            }
    }
    func remainingSeconds(at date: Date) -> Int { max(0, Int(ceil(retryAfter?.timeIntervalSince(date) ?? 0))) }
    func send(email: String, now: Date = .now) async {
        guard !isSending, remainingSeconds(at: now) == 0 else { return }
        message = nil; errorMessage = nil
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validEmail(email) else { errorMessage = PasswordRecoveryError.invalidEmail.localizedDescription; return }
        isSending = true
        defer { isSending = false }
        do {
            try await service.requestReset(email: email)
            retryAfter = now.addingTimeInterval(60)
            message = "If this email belongs to an email/password account, reset instructions have been requested. Check Inbox and Spam. This does not confirm inbox delivery."
        } catch {
            errorMessage = error.localizedDescription
            if case AccountServiceError.rateLimited = error { retryAfter = now.addingTimeInterval(60) }
        }
    }
}
