import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

struct SOSArrivalTracker {
    let startedAt: Date
    private var seen: Set<String> = []
    init(startedAt: Date) { self.startedAt = startedAt }
    mutating func shouldAlert(id: String, createdAt: Date?) -> Bool {
        guard let createdAt, createdAt >= startedAt, !seen.contains(id) else { return false }
        seen.insert(id)
        return true
    }
}

@MainActor @Observable
final class FacilitySOSAlerts {
    private(set) var message: String?
    private var listeners: [ListenerRegistration] = []
    private var account: AppAccount?
    private var generation = UUID()
    private var trackers: [String: SOSArrivalTracker] = [:]
    private var scheduledIDs: Set<String> = []

    func configure(account: AppAccount?) {
        guard self.account != account else { return }
        listeners.forEach { $0.remove() }; listeners = []
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(scheduledIDs))
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Array(scheduledIDs))
        scheduledIDs = []; trackers = [:]; message = nil
        self.account = account; generation = UUID()
        guard let account, account.canManageQueues, FirebaseSetup.isConfigured else { return }
        let expected = generation
        let started = Date.now
        for hospitalID in account.hospitalIDs {
            trackers[hospitalID] = SOSArrivalTracker(startedAt: started)
            let listener = Firestore.firestore().collection("hospitals").document(hospitalID)
                .collection("sosRequests").whereField("status", isEqualTo: "pending")
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self, self.generation == expected else { return }
                        guard error == nil else { self.message = "SOS alerts could not connect. Refresh your account to retry."; return }
                        guard let snapshot, !snapshot.metadata.isFromCache else { return }
                        for doc in snapshot.documents {
                            let data = doc.data()
                            guard data["isSimulation"] as? Bool == true,
                                  self.trackers[hospitalID]?.shouldAlert(id: doc.documentID, createdAt: (data["createdAt"] as? Timestamp)?.dateValue()) == true else { continue }
                            await self.notify(hospitalID: hospitalID, requestID: doc.documentID, account: account, generation: expected)
                        }
                    }
                }
            listeners.append(listener)
        }
    }
    func enable() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            message = allowed ? "SOS alerts enabled. Keep this app open to receive new requests." : "Allow CardioSafe notifications in iOS Settings to receive SOS alerts."
        } catch { message = "Notification permission could not be requested. Please retry." }
    }
    private func notify(hospitalID: String, requestID: String, account: AppAccount, generation expected: UUID) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard generation == expected, Auth.auth().currentUser?.uid == account.id else { return }
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            message = "A new SOS reached your inbox. Enable SOS alerts to receive notifications."
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "New SOS request"
        content.body = "A request reached your hospital. Tap to open the SOS inbox."
        content.sound = .default
        content.userInfo = ["type": "hospital_sos", "simulation": "true", "hospitalID": hospitalID, "staffID": account.id, "requestID": requestID]
        let id = "cardiosafe.sos.\(hospitalID).\(requestID)"
        scheduledIDs.insert(id)
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            if generation != expected {
                center.removePendingNotificationRequests(withIdentifiers: [id])
                center.removeDeliveredNotifications(withIdentifiers: [id])
            }
        } catch { message = "A new SOS reached your inbox, but its notification could not be shown." }
    }
}
