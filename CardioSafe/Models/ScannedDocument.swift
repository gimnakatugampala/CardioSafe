import Foundation

struct ScannedDocument: Identifiable, Equatable, Codable {
    let id: UUID
    let title: String
    let createdAt: Date
    var reviewedText: String? = nil
    let pageCount: Int
}
