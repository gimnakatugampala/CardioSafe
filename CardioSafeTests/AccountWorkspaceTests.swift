import Testing
@testable import CardioSafe

@MainActor struct AccountWorkspaceTests {
    @Test func patientUsesPatientInterface() {
        let account = AppAccount(id: "patient", email: "patient@example.com", isEmailVerified: true, role: .patient, hospitalIDs: [])
        #expect(!account.usesHospitalWorkspace)
        #expect(!account.canManageQueues)
    }
    @Test func assignedStaffUsesHospitalInterface() {
        let account = AppAccount(id: "staff", email: "staff@example.com", isEmailVerified: true, role: .staff, hospitalIDs: ["hospital"])
        #expect(account.usesHospitalWorkspace)
        #expect(account.canManageQueues)
    }
    @Test func unverifiedOrUnassignedStaffNeverFallsBackToPatientInterface() {
        for verified in [true, false] {
            let account = AppAccount(id: "staff", email: "staff@example.com", isEmailVerified: verified, role: .staff, hospitalIDs: [])
            #expect(account.usesHospitalWorkspace)
            #expect(!account.canManageQueues)
        }
        let unverified = AppAccount(id: "staff", email: "staff@example.com", isEmailVerified: false, role: .staff, hospitalIDs: ["hospital"])
        #expect(unverified.usesHospitalWorkspace)
        #expect(!unverified.canManageQueues)
    }
}
