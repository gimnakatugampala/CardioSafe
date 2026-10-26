import Foundation
import Observation

@MainActor @Observable
final class DocumentOCRReviewViewModel {
    nonisolated static let maximumCharacters = 50_000
    var text = "" {
        didSet { if text != oldValue { hasReviewed = false } }
    }
    var hasReviewed = false
    private(set) var isRecognizing = false
    private(set) var errorMessage: String?
    private(set) var hasAttempted = false
    @ObservationIgnored private let service: any DocumentTextRecognizing
    @ObservationIgnored private var generation = UUID()
    init(service: (any DocumentTextRecognizing)? = nil) { self.service = service ?? VisionDocumentTextService() }
    var canSave: Bool { !isRecognizing && hasAttempted && hasReviewed && text.count <= Self.maximumCharacters }
    func recognize(_ data: Data) async {
        guard !hasAttempted else { return }
        hasAttempted = true; isRecognizing = true; hasReviewed = false
        let expected = generation
        defer { if generation == expected { isRecognizing = false } }
        do {
            let result = try await service.recognize(pdfData: data)
            guard generation == expected, !Task.isCancelled else { return }
            text = result
            if result.isEmpty { errorMessage = "No readable text was found. You can type it yourself or save the PDF without text." }
        } catch {
            guard generation == expected, !Task.isCancelled else { return }
            errorMessage = (error as? DocumentRecognitionError)?.errorDescription ?? "Text recognition failed. You can type the text or save the PDF without it."
        }
    }
    func stop() { generation = UUID(); isRecognizing = false }
}
