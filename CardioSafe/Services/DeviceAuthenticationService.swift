import LocalAuthentication

@MainActor
protocol DeviceAuthenticating {
    func authenticate(reason: String) async throws
    func cancel()
}

@MainActor
final class DeviceAuthenticationService: DeviceAuthenticating {
    private var context: LAContext?
    func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        self.context = context
        defer { if self.context === context { self.context = nil } }
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? LAError(.passcodeNotSet)
        }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
            throw LAError(.authenticationFailed)
        }
    }
    func cancel() { context?.invalidate(); context = nil }
}
