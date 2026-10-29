import Testing
@testable import CardioSafe

@MainActor struct SOSNotificationRouteTests {
    let payload: [AnyHashable: Any] = ["type": "hospital_sos", "simulation": "true", "hospitalID": "demo-asiri-central", "staffID": "staff-one"]
    @Test func acceptsOnlyAssignedVerifiedRecipient() throws {
        let route = try #require(SOSNotificationRoute(payload: payload))
        func account(id: String = "staff-one", verified: Bool = true, role: AppAccount.Role = .staff, hospitals: [String] = ["demo-asiri-central"]) -> AppAccount {
            AppAccount(id: id, email: "test@example.com", isEmailVerified: verified, role: role, hospitalIDs: hospitals)
        }
        #expect(route.isAllowed(for: account()))
        #expect(!route.isAllowed(for: nil))
        #expect(!route.isAllowed(for: account(id: "other-staff")))
        #expect(!route.isAllowed(for: account(verified: false)))
        #expect(!route.isAllowed(for: account(role: .patient)))
        #expect(!route.isAllowed(for: account(hospitals: [])))
    }
    @Test func rejectsUnrelatedAndMalformedPayloads() {
        #expect(SOSNotificationRoute(payload: [:]) == nil)
        var wrong = payload; wrong["type"] = "walking"
        #expect(SOSNotificationRoute(payload: wrong) == nil)
        wrong = payload; wrong["hospitalID"] = "hospital/other"
        #expect(SOSNotificationRoute(payload: wrong) == nil)
        wrong = payload; wrong.removeValue(forKey: "staffID")
        #expect(SOSNotificationRoute(payload: wrong) == nil)
    }
    @Test func unrelatedNotificationDoesNotReplacePendingRoute() throws {
        let router = SOSNotificationRouter()
        router.receive(payload)
        let expected = try #require(router.pending)
        router.receive(["type": "walking"])
        #expect(router.pending == expected)
    }
}
