import Foundation
import LocalAuthentication
import Observation

@MainActor @Observable
final class AppLockViewModel {
    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isBusy = false
    private(set) var isActive = true
    private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let authentication: any DeviceAuthenticating
    private var generation = UUID()
    var needsShield: Bool { isEnabled && (isLocked || !isActive) }
    init(defaults: UserDefaults = .standard, authentication: (any DeviceAuthenticating)? = nil) {
        self.defaults = defaults
        self.authentication = authentication ?? DeviceAuthenticationService()
        let enabled = defaults.bool(forKey: "appLockEnabled")
        isEnabled = enabled
        isLocked = enabled
    }
    func becameInactive() { isActive = false }
    func becameActive() { isActive = true }
    func enteredBackground() {
        isActive = false
        generation = UUID()
        authentication.cancel()
        isBusy = false
        if isEnabled { isLocked = true }
        errorMessage = nil
    }
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled, isActive, !isBusy else { return }
        let success = await verify(reason: enabled ? "Enable CardioSafe app lock." : "Turn off CardioSafe app lock.")
        guard success else { return }
        isEnabled = enabled
        isLocked = false
        defaults.set(enabled, forKey: "appLockEnabled")
    }
    func unlock() async {
        guard isEnabled, isLocked, isActive, !isBusy else { return }
        if await verify(reason: "Unlock your CardioSafe profile and health records.") { isLocked = false }
    }
    private func verify(reason: String) async -> Bool {
        let request = UUID()
        generation = request
        isBusy = true
        errorMessage = nil
        do {
            try await authentication.authenticate(reason: reason)
            guard generation == request else { return false }
            isBusy = false
            return true
        } catch {
            guard generation == request else { return false }
            isBusy = false
            switch (error as? LAError)?.code {
            case .passcodeNotSet: errorMessage = "Set a device passcode in iOS Settings before enabling app lock."
            case .userCancel, .systemCancel, .appCancel: errorMessage = "Authentication cancelled. You can try again."
            case .biometryNotAvailable, .biometryNotEnrolled: errorMessage = "Use your device passcode to authenticate. Check Face ID or Touch ID in iOS Settings."
            default: errorMessage = "Authentication didn’t complete. Try again using Face ID, Touch ID or your device passcode."
            }
            return false
        }
    }
}
