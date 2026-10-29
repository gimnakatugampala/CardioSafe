import Foundation
import Observation

nonisolated struct SOSNotificationRoute: Identifiable, Equatable, Sendable {
    let hospitalID: String
    let staffID: String
    var id: String { staffID + ":" + hospitalID }
    init?(payload: [AnyHashable: Any]) {
        guard payload["type"] as? String == "hospital_sos",
              payload["simulation"] as? String == "true",
              let hospital = payload["hospitalID"] as? String,
              let staff = payload["staffID"] as? String,
              !hospital.isEmpty, !staff.isEmpty,
              hospital.count <= 128, staff.count <= 128,
              !hospital.contains("/"), !staff.contains("/") else { return nil }
        hospitalID = hospital; staffID = staff
    }
    @MainActor func isAllowed(for account: AppAccount?) -> Bool {
        guard let account else { return false }
        return account.id == staffID && account.canManageQueues && account.hospitalIDs.contains(hospitalID)
    }
}

@MainActor @Observable
final class SOSNotificationRouter {
    static let shared = SOSNotificationRouter()
    var pending: SOSNotificationRoute?
    func receive(_ payload: [AnyHashable: Any]) {
        guard let route = SOSNotificationRoute(payload: payload) else { return }
        pending = route
    }
}
