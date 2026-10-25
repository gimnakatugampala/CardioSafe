import Foundation
import PDFKit

struct ImportedPDF {
    let data: Data
    let title: String
}

@MainActor
enum DocumentImportService {
    static let maximumBytes = 25 * 1024 * 1024
    static func read(_ url: URL) throws -> ImportedPDF {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<ImportedPDF, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
            result = Result {
                let size = try coordinatedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= maximumBytes else { throw DocumentImportError.tooLarge }
                let data = try Data(contentsOf: coordinatedURL)
                guard data.count <= maximumBytes else { throw DocumentImportError.tooLarge }
                guard let pdf = PDFDocument(data: data) else { throw DocumentImportError.invalidPDF }
                guard !pdf.isLocked else { throw DocumentImportError.lockedPDF }
                guard pdf.pageCount > 0 else { throw DocumentImportError.invalidPDF }
                let name = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                return ImportedPDF(data: data, title: name.isEmpty ? "Imported document" : String(name.prefix(100)))
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw DocumentImportError.invalidPDF }
        return try result.get()
    }
}

enum DocumentImportError: LocalizedError {
    case tooLarge, invalidPDF, lockedPDF
    var errorDescription: String? {
        switch self {
        case .tooLarge: "Choose a PDF smaller than 25 MB."
        case .invalidPDF: "This file isn’t a readable PDF with pages. Choose another file."
        case .lockedPDF: "This PDF requires a password. Import an unlocked copy instead."
        }
    }
}
