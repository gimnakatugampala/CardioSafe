import Foundation
import Observation

struct DocumentReminderRoute: Identifiable, Equatable {
    let documentID: UUID
    let ownerID: String
    var id: String { ownerID + documentID.uuidString }
    init?(payload: [AnyHashable: Any]) {
        guard payload["type"] as? String == "document_reminder",
              let value = payload["documentID"] as? String, let id = UUID(uuidString: value),
              let owner = payload["ownerID"] as? String, !owner.isEmpty, owner.count <= 128 else { return nil }
        documentID = id; ownerID = owner
    }
}

@MainActor @Observable final class DocumentReminderRouter {
    static let shared = DocumentReminderRouter()
    var pending: DocumentReminderRoute?
}
