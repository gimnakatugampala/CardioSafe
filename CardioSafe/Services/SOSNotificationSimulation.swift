import Foundation
import UserNotifications

@MainActor
struct SOSNotificationSimulation {
    func schedule(account: AppAccount, hospitalID: String) async throws {
        guard account.canManageQueues, account.hospitalIDs.contains(hospitalID) else {
            throw SimulationError.staff
        }
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw SimulationError.permission }
        let content = UNMutableNotificationContent()
        content.title = "New SOS request"
        content.body = "A request reached your hospital. Tap to open the SOS inbox."
        content.sound = .default
        // Same string data fields can be carried by an FCM notification message.
        content.userInfo = ["type": "hospital_sos", "simulation": "true", "hospitalID": hospitalID, "staffID": account.id]
        try await center.add(UNNotificationRequest(identifier: "cardiosafe.sos.simulation", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }
    enum SimulationError: LocalizedError {
        case staff, permission
        var errorDescription: String? {
            switch self {
            case .staff: "Sign in with verified staff access to this hospital."
            case .permission: "Allow CardioSafe notifications in iOS Settings, then retry."
            }
        }
    }
}
