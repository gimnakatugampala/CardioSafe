import Foundation
import PDFKit

@MainActor
protocol ScannedDocumentStoring {
    func load() throws -> [ScannedDocument]
    func save(data: Data, title: String, reviewedText: String?) throws -> ScannedDocument
    func rename(_ document: ScannedDocument, title: String) throws
    func delete(_ document: ScannedDocument) throws
    func url(for document: ScannedDocument) -> URL
}

@MainActor
struct LocalScannedDocumentStore: ScannedDocumentStoring {
    private let directory: URL
    private let ownerID: String?
    private let syncEnabled: Bool
    init(directory: URL? = nil) {
        self.ownerID = AccountDataScope.ownerID
        self.syncEnabled = directory == nil
        self.directory = directory ?? AccountDataScope.directory("ScannedDocuments")
    }
    func url(for document: ScannedDocument) -> URL { file(document.id) }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("pdf") }
    func load() throws -> [ScannedDocument] {
        if syncEnabled, let ownerID {
            return try AccountSyncCache.shared.values(ScannedDocument.self, owner: ownerID, kind: "document").sorted { $0.createdAt > $1.createdAt }
        }
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .map { url in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      let pdf = PDFDocument(url: url), pdf.pageCount > 0 else { throw DocumentStoreError.unreadable }
                let attributes = pdf.documentAttributes ?? [:]
                return ScannedDocument(id: id, title: attributes[PDFDocumentAttribute.titleAttribute] as? String ?? "Scanned document",
                                       createdAt: attributes[PDFDocumentAttribute.creationDateAttribute] as? Date ?? .distantPast, reviewedText: Self.reviewedText(in: attributes), pageCount: pdf.pageCount)
            }.sorted { $0.createdAt > $1.createdAt }
    }
    func save(data: Data, title: String, reviewedText: String? = nil) throws -> ScannedDocument {
        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else { throw DocumentStoreError.unreadable }
        let title = try validated(title)
        let reviewed = reviewedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (reviewed?.count ?? 0) <= 50_000 else { throw DocumentStoreError.textLength }
        let record = ScannedDocument(id: UUID(), title: title, createdAt: .now, reviewedText: reviewed?.isEmpty == false ? reviewed : nil, pageCount: pdf.pageCount)
        var attributes = pdf.documentAttributes ?? [:]
        attributes[PDFDocumentAttribute.titleAttribute] = title
        attributes[PDFDocumentAttribute.creationDateAttribute] = record.createdAt
        var keywords = (attributes[PDFDocumentAttribute.keywordsAttribute] as? [String] ?? []).filter { $0 != Self.reviewMarker }
        if let reviewed = record.reviewedText {
            attributes[PDFDocumentAttribute.subjectAttribute] = reviewed
            keywords.append(Self.reviewMarker)
        }
        attributes[PDFDocumentAttribute.keywordsAttribute] = keywords
        pdf.documentAttributes = attributes
        try write(pdf, to: file(record.id))
        if syncEnabled, let ownerID { try AccountSyncCache.shared.put(record, owner: ownerID, kind: "document", key: record.id.uuidString) }
        return record
    }
    func rename(_ document: ScannedDocument, title: String) throws {
        let title = try validated(title)
        if syncEnabled, let ownerID {
            let updated = ScannedDocument(id: document.id, title: title, createdAt: document.createdAt, reviewedText: document.reviewedText, pageCount: document.pageCount)
            try AccountSyncCache.shared.put(updated, owner: ownerID, kind: "document", key: document.id.uuidString)
        }
        guard let pdf = PDFDocument(url: file(document.id)) else {
            if syncEnabled { return }
            throw DocumentStoreError.unreadable
        }
        var attributes = pdf.documentAttributes ?? [:]
        attributes[PDFDocumentAttribute.titleAttribute] = title
        pdf.documentAttributes = attributes
        try write(pdf, to: file(document.id))
    }
    func delete(_ document: ScannedDocument) throws {
        if syncEnabled, let ownerID { try AccountSyncCache.shared.put(document, owner: ownerID, kind: "document", key: document.id.uuidString, deleted: true) }
        if FileManager.default.fileExists(atPath: file(document.id).path) { try FileManager.default.removeItem(at: file(document.id)) }
    }
    private static let reviewMarker = "CardioSafeReviewedTextV1"
    private static func reviewedText(in attributes: [AnyHashable: Any]) -> String? {
        guard (attributes[PDFDocumentAttribute.keywordsAttribute] as? [String])?.contains(reviewMarker) == true else { return nil }
        return attributes[PDFDocumentAttribute.subjectAttribute] as? String
    }
    private func validated(_ title: String) throws -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 100 else { throw DocumentStoreError.title }
        return title
    }
    private func write(_ pdf: PDFDocument, to url: URL) throws {
        guard let data = pdf.dataRepresentation() else { throw DocumentStoreError.unreadable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

enum DocumentStoreError: LocalizedError {
    case unreadable, title, textLength
    var errorDescription: String? {
        switch self {
        case .unreadable: "A document couldn’t be read. Its original file has not been changed."
        case .textLength: "Keep reviewed text within 50,000 characters."
        case .title: "Enter a document name using 1–100 characters."
        }
    }
}


extension ScannedDocumentStoring {
    func save(data: Data, title: String) throws -> ScannedDocument {
        try save(data: data, title: title, reviewedText: nil)
    }
}
