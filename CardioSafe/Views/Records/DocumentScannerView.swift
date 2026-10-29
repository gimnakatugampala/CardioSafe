import SwiftUI
import VisionKit
import PDFKit

struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: (Data) -> Void
    let onCancel: () -> Void
    let onFailure: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(parent: DocumentScannerView) { self.parent = parent }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.onCancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.onFailure() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { parent.onCancel(); return }
            let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
            let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
                for index in 0..<scan.pageCount {
                    autoreleasepool {
                        let image = scan.imageOfPage(at: index)
                        context.beginPage()
                        UIColor.white.setFill(); context.cgContext.fill(bounds)
                        let scale = min(555 / max(image.size.width, 1), 802 / max(image.size.height, 1))
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        image.draw(in: CGRect(x: (595 - size.width) / 2, y: (842 - size.height) / 2, width: size.width, height: size.height))
                    }
                }
            }
            parent.onScan(data)
        }
    }
}

struct ScannedPDFView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}

struct SavedDocumentView: View {
    let document: ScannedDocument
    let url: URL
    @State private var showingText = false
    var body: some View {
        VStack(spacing: 12) {
            if document.reviewedText != nil {
                Picker("Saved content", selection: $showingText) {
                    Text("Document").tag(false)
                    Text("Reviewed text").tag(true)
                }.pickerStyle(.segmented).padding(.horizontal)
            }
            if showingText, let text = document.reviewedText {
                ScrollView {
                    Text(text).frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled)
                }
                Text("Reviewed text saved with this document. Refer to the original for clinical details.")
                    .font(.caption).foregroundStyle(.secondary).padding()
            } else if let data = try? Data(contentsOf: url), PDFDocument(data: data) != nil { ScannedPDFView(data: data) }
            else { ContentUnavailableView("Document unavailable", systemImage: "doc.badge.ellipsis", description: Text("This PDF stays on the phone where it was added. Synced reviewed text and reminders are available on this phone.")) }
        }.navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { DocumentRemindersView(document: document) } label: {
                    Label("Reminders", systemImage: "bell.badge")
                }
            }
        }
    }
}
