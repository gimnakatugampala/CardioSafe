import Foundation
import PDFKit

@MainActor
protocol ScannedDocumentStoring {
    func load() throws -> [ScannedDocument]
    func save(data: Data, title: String) throws -> ScannedDocument
    func rename(_ document: ScannedDocument, title: String) throws
    func delete(_ document: ScannedDocument) throws
    func url(for document: ScannedDocument) -> URL
}

@MainActor
struct LocalScannedDocumentStore: ScannedDocumentStoring {
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("ScannedDocuments", isDirectory: true)
    }
    func url(for document: ScannedDocument) -> URL { file(document.id) }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("pdf") }
    func load() throws -> [ScannedDocument] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .map { url in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      let pdf = PDFDocument(url: url), pdf.pageCount > 0 else { throw DocumentStoreError.unreadable }
                let attributes = pdf.documentAttributes ?? [:]
                return ScannedDocument(id: id, title: attributes[PDFDocumentAttribute.titleAttribute] as? String ?? "Scanned document",
                                       createdAt: attributes[PDFDocumentAttribute.creationDateAttribute] as? Date ?? .distantPast, pageCount: pdf.pageCount)
            }.sorted { $0.createdAt > $1.createdAt }
    }
    func save(data: Data, title: String) throws -> ScannedDocument {
        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else { throw DocumentStoreError.unreadable }
        let title = try validated(title)
        let record = ScannedDocument(id: UUID(), title: title, createdAt: .now, pageCount: pdf.pageCount)
        pdf.documentAttributes = [PDFDocumentAttribute.titleAttribute: title, PDFDocumentAttribute.creationDateAttribute: record.createdAt]
        try write(pdf, to: file(record.id))
        return record
    }
    func rename(_ document: ScannedDocument, title: String) throws {
        let title = try validated(title)
        guard let pdf = PDFDocument(url: file(document.id)) else { throw DocumentStoreError.unreadable }
        var attributes = pdf.documentAttributes ?? [:]
        attributes[PDFDocumentAttribute.titleAttribute] = title
        pdf.documentAttributes = attributes
        try write(pdf, to: file(document.id))
    }
    func delete(_ document: ScannedDocument) throws { try FileManager.default.removeItem(at: file(document.id)) }
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
    case unreadable, title
    var errorDescription: String? {
        switch self {
        case .unreadable: "A document couldn’t be read. Its original file has not been changed."
        case .title: "Enter a document name using 1–100 characters."
        }
    }
}
