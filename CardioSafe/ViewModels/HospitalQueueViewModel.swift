import Foundation
import Observation
import FirebaseFirestore

@MainActor
@Observable
final class HospitalQueueViewModel {
    private(set) var departments: [DepartmentQueue] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hospitalID: String?
    private(set) var hospitalName: String?
    private(set) var isSaving = false
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var generation = UUID()

    func findHospital(mapPlaceID: String) async {
        stop()
        guard FirebaseSetup.isConfigured else {
            errorMessage = "Hospital queue services aren’t connected yet."; return
        }
        isLoading = true
        let token = generation
        do {
            let result = try await Firestore.firestore().collection("hospitals")
                .whereField("mapPlaceID", isEqualTo: mapPlaceID).limit(to: 1).getDocuments()
            guard generation == token, !Task.isCancelled else { return }
            guard let document = result.documents.first else {
                errorMessage = "This hospital has not connected department queues yet."; isLoading = false; return
            }
            hospitalName = document.data()["name"] as? String
            listen(hospitalID: document.documentID)
        } catch {
            guard generation == token else { return }
            errorMessage = "Queue updates are unavailable. Sign in and check your connection."
            isLoading = false
        }
    }

    func listen(hospitalID: String) {
        listener?.remove()
        generation = UUID()
        departments = []
        errorMessage = nil
        self.hospitalID = hospitalID
        guard FirebaseSetup.isConfigured else { errorMessage = "Queue services aren’t connected yet."; return }
        isLoading = true
        let token = generation
        listener = Firestore.firestore().collection("hospitals").document(hospitalID).collection("departments")
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.isLoading = false
                    if error != nil {
                        self.departments = []
                        self.errorMessage = "Queue updates could not be loaded. Check your access and connection."
                        return
                    }
                    guard let snapshot else { return }
                    let values = snapshot.documents.compactMap { document -> DepartmentQueue? in
                        let data = document.data()
                        guard let name = data["name"] as? String, let count = data["waitingCount"] as? Int else { return nil }
                        let queue = DepartmentQueue(id: document.documentID, name: name, waitingCount: count,
                                                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue(),
                                                    isCached: snapshot.metadata.isFromCache || document.metadata.hasPendingWrites,
                                                    isDemo: data["isDemo"] as? Bool ?? false)
                        return queue.isValid ? queue : nil
                    }
                    self.departments = values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    self.errorMessage = values.count < snapshot.documents.count ? "Some department records could not be read." : nil
                }
            }
    }

    func update(_ queue: DepartmentQueue, count: Int, account: AppAccount) async -> Bool {
        guard !isSaving, let hospitalID, account.canManageQueues,
              account.hospitalIDs.contains(hospitalID), (0...9999).contains(count) else {
            errorMessage = "You don’t have access to update this department."; return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await Firestore.firestore().collection("hospitals").document(hospitalID)
                .collection("departments").document(queue.id).updateData([
                    "waitingCount": count, "updatedAt": FieldValue.serverTimestamp(), "updatedBy": account.id
                ])
            return true
        } catch { errorMessage = "The queue update was not confirmed. Check your connection and retry."; return false }
    }

    func stop() {
        generation = UUID()
        listener?.remove(); listener = nil
        departments = []; hospitalID = nil; hospitalName = nil; errorMessage = nil; isLoading = false
    }
}
