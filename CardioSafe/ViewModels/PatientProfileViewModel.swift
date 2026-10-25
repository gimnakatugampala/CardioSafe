import Foundation
import Observation

@MainActor @Observable
final class PatientProfileViewModel {
    var draft = PatientProfile()
    private(set) var saved = PatientProfile()
    private(set) var isLoaded = false
    private(set) var errorMessage: String?
    private let accountID: String
    private let store: any PatientProfileStoring
    init(accountID: String, store: (any PatientProfileStoring)? = nil) {
        self.accountID = accountID
        self.store = store ?? LocalPatientProfileStore()
    }
    func load() {
        do {
            saved = try store.load(accountID: accountID)
            draft = saved
            isLoaded = true
            errorMessage = nil
        } catch {
            isLoaded = false
            errorMessage = "Your profile couldn’t be loaded. Retry before editing."
        }
    }
    func beginEditing() { draft = saved; errorMessage = nil }
    func save(now: Date = .now) -> Bool {
        guard isLoaded else { return false }
        var profile = draft
        profile.fullName = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.phoneNumber = profile.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.emergencyContactName = profile.emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.emergencyContactPhone = profile.emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.fullName.isEmpty, profile.fullName.count <= 100 else {
            errorMessage = "Enter your name using up to 100 characters."; return false
        }
        if let birth = profile.dateOfBirth, birth > now {
            errorMessage = "Date of birth cannot be in the future."; return false
        }
        for phone in [profile.phoneNumber, profile.emergencyContactPhone] where !phone.isEmpty {
            guard (7...15).contains(phone.filter(\.isNumber).count),
                  phone.allSatisfy({ $0.isNumber || "+ ()-".contains($0) }) else {
                errorMessage = "Use 7–15 digits for phone numbers; spaces, +, brackets and hyphens are allowed."; return false
            }
        }
        guard profile.emergencyContactName.count <= 100,
              profile.emergencyContactName.isEmpty == profile.emergencyContactPhone.isEmpty else {
            errorMessage = "Provide both the emergency contact’s name and phone number, or leave both blank."; return false
        }
        do {
            try store.save(profile, accountID: accountID)
            saved = profile; draft = profile; errorMessage = nil
            return true
        } catch {
            errorMessage = "Your changes couldn’t be saved on this device. Please retry."
            return false
        }
    }
}
