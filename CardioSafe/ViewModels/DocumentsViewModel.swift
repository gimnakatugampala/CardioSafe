import Foundation
import Observation

@MainActor @Observable
final class DocumentsViewModel {
    private(set) var documents: [ScannedDocument] = []
    private(set) var errorMessage: String?
    private(set) var isLoaded = false
    private let store: any ScannedDocumentStoring
    init(store: (any ScannedDocumentStoring)? = nil) { self.store = store ?? LocalScannedDocumentStore() }
    func load() {
        do { documents = try store.load(); isLoaded = true; errorMessage = nil }
        catch { isLoaded = false; errorMessage = "Documents couldn’t be loaded. Please retry. Existing files have not been changed." }
    }
    func save(data: Data, title: String, reviewedText: String? = nil) -> Bool {
        do {
            let record = try store.save(data: data, title: title, reviewedText: reviewedText)
            documents.insert(record, at: 0); errorMessage = nil
            return true
        } catch { errorMessage = message(error, fallback: "The scan couldn’t be saved. Keep this preview open and retry."); return false }
    }
    func rename(_ document: ScannedDocument, title: String) -> Bool {
        do {
            guard try store.load().first(where: { $0.id == document.id }) == document else {
                errorMessage = "This document changed on another phone. Reopen it before renaming."; return false
            }
            try store.rename(document, title: title)
            if let index = documents.firstIndex(where: { $0.id == document.id }) {
                documents[index] = ScannedDocument(id: document.id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: document.createdAt, reviewedText: document.reviewedText, pageCount: document.pageCount)
            }
            errorMessage = nil; return true
        } catch { errorMessage = message(error, fallback: "The document couldn’t be renamed. Please retry."); return false }
    }
    func delete(_ document: ScannedDocument) {
        do {
            let reminderStore = LocalDocumentReminderStore()
            let previous = try reminderStore.load()
            let linked = previous.filter { $0.documentID == document.id }
            try reminderStore.save(previous.filter { $0.documentID != document.id })
            do { try store.delete(document) }
            catch { try reminderStore.save(previous); throw error }
            for reminder in linked { DocumentReminderService().cancel(reminder) }
            documents.removeAll { $0.id == document.id }; errorMessage = nil
        }
        catch { errorMessage = "The document couldn’t be deleted. Please retry." }
    }
    func url(for document: ScannedDocument) -> URL { store.url(for: document) }
    func reportScannerError() { errorMessage = "The scanner couldn’t finish. Please try again." }
    func clearError() { errorMessage = nil }
    private func message(_ error: Error, fallback: String) -> String {
        (error as? DocumentStoreError)?.errorDescription ?? fallback
    }
}
