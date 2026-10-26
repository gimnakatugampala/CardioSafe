import Foundation
import Vision
import CoreGraphics
import ImageIO

enum DocumentRecognitionError: LocalizedError {
    case invalid, tooManyPages, imageTooLarge
    var errorDescription: String? {
        switch self {
        case .invalid: "The document couldn’t be recognised. You can save the PDF without recognised text."
        case .tooManyPages: "Text recognition supports up to 10 pages per document. You can still save this PDF without text."
        case .imageTooLarge: "Choose an image smaller than 25 MB."
        }
    }
}

@MainActor protocol DocumentTextRecognizing {
    func recognize(pdfData: Data) async throws -> String
}

@MainActor final class VisionDocumentTextService: DocumentTextRecognizing {
    func recognize(pdfData: Data) async throws -> String {
        let work = Task.detached(priority: .userInitiated) { try Self.perform(pdfData: pdfData) }
        return try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
    }

    nonisolated private static func perform(pdfData: Data) throws -> String {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let pdf = CGPDFDocument(provider), !pdf.isEncrypted, pdf.numberOfPages > 0 else { throw DocumentRecognitionError.invalid }
        guard pdf.numberOfPages <= 10 else { throw DocumentRecognitionError.tooManyPages }
        var pages: [String] = []
        for index in 1...pdf.numberOfPages {
            try Task.checkCancellation()
            let text: String = try autoreleasepool {
                guard let page = pdf.page(at: index) else { throw DocumentRecognitionError.invalid }
                let bounds = page.getBoxRect(.mediaBox)
                guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
                    throw DocumentRecognitionError.invalid
                }
                let scale = 2000 / max(bounds.width, bounds.height)
                let width = max(1, Int(bounds.width * scale)), height = max(1, Int(bounds.height * scale))
                guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DocumentRecognitionError.invalid }
                let rect = CGRect(x: 0, y: 0, width: width, height: height)
                context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect)
                context.concatenate(page.getDrawingTransform(.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true))
                context.drawPDFPage(page)
                guard let image = context.makeImage() else { throw DocumentRecognitionError.invalid }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                // Keep raw recognition for the patient's review; don't silently correct medical terms.
                request.usesLanguageCorrection = false
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                try Task.checkCancellation()
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
            if pdf.numberOfPages > 1 { pages.append(text.isEmpty ? "" : "Page \(index)\n" + text) }
            else { pages.append(text) }
        }
        let result = pages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.count <= DocumentOCRReviewViewModel.maximumCharacters else { throw DocumentRecognitionError.invalid }
        return result
    }

    static func imagePDF(from data: Data) async throws -> Data {
        let work = Task.detached(priority: .userInitiated) { try Self.convertImage(data) }
        return try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
    }
    nonisolated private static func convertImage(_ data: Data) throws -> Data {
        guard data.count <= 25 * 1024 * 1024 else { throw DocumentRecognitionError.imageTooLarge }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400
              ] as CFDictionary) else { throw DocumentRecognitionError.invalid }
        let output = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
            throw DocumentRecognitionError.invalid
        }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(bounds)
        let scale = min(555 / CGFloat(image.width), 802 / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.draw(image, in: CGRect(x: (595 - size.width) / 2, y: (842 - size.height) / 2, width: size.width, height: size.height))
        context.endPDFPage(); context.closePDF()
        try Task.checkCancellation()
        return output as Data
    }
}
