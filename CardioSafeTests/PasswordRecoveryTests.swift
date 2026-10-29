import Foundation
import Testing
@testable import CardioSafe

@MainActor struct PasswordRecoveryTests {
    @MainActor final class Service: PasswordResetServicing {
        var emails: [String] = []
        var error: AccountServiceError?
        var suspend = false
        var continuation: CheckedContinuation<Void, Never>?
        func requestReset(email: String) async throws {
            emails.append(email)
            if suspend { await withCheckedContinuation { continuation = $0 } }
            if let error { throw error }
        }
    }
    @Test func validatesBeforeRequestAndTrimsAddress() async {
        let service = Service(), now = Date.now
        let model = PasswordRecoveryViewModel(service: service)
        for email in ["", "no-at.example.com", "two@@example.com", "a@.com", "a@x..com", "a b@example.com"] {
            await model.send(email: email, now: now)
            #expect(model.errorMessage != nil && service.emails.isEmpty)
        }
        await model.send(email: "  patient@example.com\n", now: now)
        #expect(service.emails == ["patient@example.com"])
        #expect(model.message?.contains("does not confirm inbox delivery") == true)
        #expect(model.errorMessage == nil)
    }
    @Test func cooldownPreventsDuplicateRequestsAndAllowsLaterRetry() async {
        let service = Service(), now = Date.now
        let model = PasswordRecoveryViewModel(service: service)
        await model.send(email: "patient@example.com", now: now)
        await model.send(email: "patient@example.com", now: now.addingTimeInterval(10))
        #expect(service.emails.count == 1)
        await model.send(email: "patient@example.com", now: now.addingTimeInterval(61))
        #expect(service.emails.count == 2)
    }
    @Test func networkFailureAllowsRetryAndDoesNotClaimSuccess() async {
        let service = Service()
        service.error = .network
        let model = PasswordRecoveryViewModel(service: service)
        await model.send(email: "patient@example.com")
        #expect(model.message == nil && model.errorMessage != nil && !model.isSending)
        service.error = nil
        await model.send(email: "patient@example.com")
        #expect(service.emails.count == 2 && model.message != nil && model.errorMessage == nil)
    }
    @Test func simultaneousTapSendsOnlyOneRequest() async {
        let service = Service()
        service.suspend = true
        let model = PasswordRecoveryViewModel(service: service)
        let first = Task { await model.send(email: "patient@example.com") }
        while service.continuation == nil { await Task.yield() }
        await model.send(email: "patient@example.com")
        #expect(service.emails.count == 1 && model.isSending)
        service.continuation?.resume()
        await first.value
        #expect(!model.isSending)
    }
    @Test func rateLimitShowsFailureAndWaitsBeforeRetry() async {
        let service = Service(), now = Date.now
        service.error = .rateLimited
        let model = PasswordRecoveryViewModel(service: service)
        await model.send(email: "patient@example.com", now: now)
        #expect(model.message == nil && model.errorMessage != nil && model.remainingSeconds(at: now) == 60)
        await model.send(email: "patient@example.com", now: now)
        #expect(service.emails.count == 1)
    }
}
