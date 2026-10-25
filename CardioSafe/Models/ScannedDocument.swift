import Foundation

struct ScannedDocument: Identifiable, Equatable {
    let id: UUID
    let title: String
    let createdAt: Date
    let pageCount: Int
}
