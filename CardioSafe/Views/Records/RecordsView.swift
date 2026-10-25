import SwiftUI
import VisionKit
import AVFoundation

struct RecordsView: View {
    let sessionModel: WalkingSessionViewModel
    @State private var model = DocumentsViewModel()
    @State private var showingDocuments = false
    @State private var scanning = false
    @State private var scannedData: Data?
    @State private var pendingScan: PendingScan?
    @State private var scannerMessage: String?
    @State private var renaming: ScannedDocument?
    @State private var documentName = ""
    @State private var deleting: ScannedDocument?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Picker("Record type", selection: $showingDocuments) {
                Text("Walking").tag(false)
                Text("Documents").tag(true)
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 10)
            if showingDocuments { documents }
            else { WalkingHistoryView(viewModel: sessionModel, title: "Records") }
        }
        .background(CardioSafeTheme.background(for: scheme))
        .navigationTitle("Records")
        .toolbar {
            if showingDocuments {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: startScan) { Label("Scan document", systemImage: "doc.viewfinder") }
                }
            }
        }
        .task { model.load() }
        .fullScreenCover(isPresented: $scanning, onDismiss: {
            if let data = scannedData { pendingScan = PendingScan(data: data); scannedData = nil }
        }) {
            DocumentScannerView(onScan: { data in scannedData = data; scanning = false },
                                onCancel: { scanning = false },
                                onFailure: { scanning = false; model.reportScannerError() })
                .ignoresSafeArea()
        }
        .sheet(item: $pendingScan) { scan in ScanReviewView(data: scan.data, model: model) }
        .alert("Document scanner", isPresented: Binding(get: { scannerMessage != nil }, set: { if !$0 { scannerMessage = nil } })) {
            Button("OK", role: .cancel) { scannerMessage = nil }
        } message: { Text(scannerMessage ?? "") }
        .sheet(item: $renaming) { document in
            NavigationStack {
                Form {
                    TextField("Document name", text: $documentName)
                    if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                }
                .navigationTitle("Rename document").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { renaming = nil; model.clearError() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { if model.rename(document, title: documentName) { renaming = nil } }
                    }
                }
            }.presentationDetents([.medium, .large])
        }
        .confirmationDialog("Delete this document?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let document = deleting {
                Button("Delete \(document.title)", role: .destructive) { model.delete(document); deleting = nil }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This permanently removes the PDF from this device. There is no cloud copy in CardioSafe.") }
    }
    private var documents: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("YOUR DOCUMENTS", systemImage: "doc.text.viewfinder")
                        .font(.caption.weight(.bold)).tracking(1.2)
                    Text("Keep your care records close.").font(.title2.bold())
                    Text("Scan prescriptions, reports or other paperwork into PDFs. Documents stay on this device and are not uploaded to Firebase or sent to hospitals.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(action: startScan) { Label("Scan document", systemImage: "doc.viewfinder") }
                        .buttonStyle(.borderedProminent)
                }.padding(.vertical, 8)
            }
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Reload documents") { model.load() }
                }
            }
            if model.isLoaded && model.documents.isEmpty {
                ContentUnavailableView("No scanned documents yet", systemImage: "doc.text", description: Text("Scan a document to review its pages and save a named PDF."))
            }
            Section("Saved PDFs") {
                ForEach(model.documents) { document in
                    NavigationLink { SavedDocumentView(document: document, url: model.url(for: document)) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "doc.richtext").font(.title2).foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(document.title).font(.headline)
                                Text("\(document.pageCount) \(document.pageCount == 1 ? "page" : "pages") · \(document.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deleting = document } label: { Label("Delete", systemImage: "trash") }
                        Button { beginRename(document) } label: { Label("Rename", systemImage: "pencil") }.tint(.blue)
                    }
                    .contextMenu {
                        Button { beginRename(document) } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) { deleting = document } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { model.load() }
    }
    private func beginRename(_ document: ScannedDocument) {
        model.clearError(); documentName = document.title; renaming = document
    }
    private func startScan() {
        #if targetEnvironment(simulator)
        scannerMessage = "Use a supported iPhone or iPad to scan documents. Camera capture is unavailable in this simulator build; saved PDFs can still be opened here."
        #else
        guard VNDocumentCameraViewController.isSupported else {
            scannerMessage = "Document scanning isn’t available on this device. Use a supported iPhone or iPad to scan; the iOS Simulator cannot use the document camera."
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status != .denied && status != .restricted else {
            scannerMessage = "Camera access is unavailable. Check Camera permission in iOS Settings → CardioSafe before scanning."
            return
        }
        model.clearError(); scannedData = nil; scanning = true
        #endif
    }
}

private struct PendingScan: Identifiable {
    let id = UUID()
    let data: Data
}

private struct ScanReviewView: View {
    let data: Data
    let model: DocumentsViewModel
    @State private var title = "Scan \(Date.now.formatted(date: .abbreviated, time: .omitted))"
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Document name", text: $title).textFieldStyle(.roundedBorder).padding(.horizontal)
                    .accessibilityLabel("Document name")
                Text("Review every page before saving. Stored on this device only.").font(.caption).foregroundStyle(.secondary)
                ScannedPDFView(data: data)
                if let error = model.errorMessage { Text(error).font(.subheadline).foregroundStyle(.red).padding(.horizontal) }
                if saving { ProgressView("Saving PDF…") }
            }
            .navigationTitle("Review scan").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.clearError(); dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save PDF") {
                        saving = true
                        Task { @MainActor in
                            await Task.yield()
                            if model.save(data: data, title: title) { dismiss() }
                            saving = false
                        }
                    }.disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.interactiveDismissDisabled(saving)
        }
    }
}
