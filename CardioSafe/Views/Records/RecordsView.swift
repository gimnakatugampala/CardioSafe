import SwiftUI
import VisionKit
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI

struct RecordsView: View {
    let sessionModel: WalkingSessionViewModel
    var ownerID: String? = nil
    @State private var sosSummaries: [SOSJourneySummary] = []
    @State private var summaryLoadError = false
    @State private var model = DocumentsViewModel()
    @State private var showingDocuments = false
    @State private var imageSelection: PhotosPickerItem?
    @State private var importing = false
    @State private var readingImport = false
    @State private var importError: String?
    @State private var scanning = false
    @State private var scannedData: Data?
    @State private var pendingScan: PendingScan?
    @State private var scannerMessage: String?
    @State private var renaming: ScannedDocument?
    @State private var documentName = ""
    @State private var deleting: ScannedDocument?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if typeSize.isAccessibilitySize {
                    recordPicker.pickerStyle(.menu)
                } else {
                    recordPicker.pickerStyle(.segmented)
                }
            }.padding(.horizontal, 20).padding(.vertical, 10)
            if showingDocuments { documents }
            else { WalkingHistoryView(viewModel: sessionModel, title: "Records") }
        }
        .background(CardioSafeTheme.background(for: scheme))
        .tint(CardioSafeTheme.accent(for: scheme))
        .navigationTitle("Records")
        .toolbar {
            if showingDocuments {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if scanningAvailable { Button(action: startScan) { Label("Scan document", systemImage: "doc.viewfinder") } }
                        PhotosPicker(selection: $imageSelection, matching: .images) {
                            Label("Import image", systemImage: "photo")
                        }
                        Button { importing = true } label: { Label("Import PDF", systemImage: "square.and.arrow.down") }
                    } label: { Label("Add document", systemImage: "plus") }
                    .disabled(readingImport)
                }
            }
        }
        .task(id: ownerID) {
            model.load()
            do { sosSummaries = try ownerID.map { try SOSJourneySummaryStore().load(ownerID: $0) } ?? []; summaryLoadError = false }
            catch { sosSummaries = []; summaryLoadError = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountDataRestored)) { notification in
            guard notification.object as? String == ownerID else { return }
            model.load()
            do { sosSummaries = try ownerID.map { try SOSJourneySummaryStore().load(ownerID: $0) } ?? [] }
            catch { summaryLoadError = true }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                readingImport = true
                model.clearError()
                Task { @MainActor in
                    await Task.yield()
                    defer { readingImport = false }
                    do {
                        let imported = try DocumentImportService.read(url)
                        pendingScan = PendingScan(data: imported.data, title: imported.title, isImport: true)
                    } catch {
                        importError = (error as? DocumentImportError)?.errorDescription ?? "The PDF couldn’t be opened. Make sure it’s available in Files, then try again."
                    }
                }
            case .failure(let error):
                if (error as NSError).code != CocoaError.userCancelled.rawValue {
                    importError = "The PDF couldn’t be selected. Please try again."
                }
            }
        }
        .onChange(of: imageSelection) { _, selection in
            guard let selection else { return }
            readingImport = true
            Task { @MainActor in
                defer { readingImport = false; imageSelection = nil }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else { throw DocumentRecognitionError.invalid }
                    let pdf = try await VisionDocumentTextService.imagePDF(from: data)
                    pendingScan = PendingScan(data: pdf, title: "Image \(Date.now.formatted(date: .abbreviated, time: .omitted))", isImport: true)
                } catch {
                    importError = (error as? DocumentRecognitionError)?.errorDescription ?? "The image couldn’t be opened. Choose another image."
                }
            }
        }
        .alert("Document import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
        .fullScreenCover(isPresented: $scanning, onDismiss: {
            if let data = scannedData { pendingScan = PendingScan(data: data); scannedData = nil }
        }) {
            DocumentScannerView(onScan: { data in scannedData = data; scanning = false },
                                onCancel: { scanning = false },
                                onFailure: { scanning = false; model.reportScannerError() })
                .ignoresSafeArea()
        }
        .sheet(item: $pendingScan) { scan in ScanReviewView(data: scan.data, model: model, initialTitle: scan.title, isImport: scan.isImport) }
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
        } message: { Text("This removes the document from your account’s list and cancels its linked reminders. The PDF file on this phone is removed; PDF files are not backed up.") }
    }
    private var recordPicker: some View {
        Picker("Record type", selection: $showingDocuments) {
            Text("Walking").tag(false)
            Text("Documents").tag(true)
        }
    }
    private var documents: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("YOUR DOCUMENTS", systemImage: "doc.text.viewfinder")
                        .font(.caption.weight(.bold)).tracking(1.2)
                    Text("Keep your care records close.").font(.title2.bold())
                    Text("Document text and reminders sync to your account. PDF files stay on this phone.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if scanningAvailable {
                        Button(action: startScan) { Label("Scan document", systemImage: "doc.viewfinder") }.buttonStyle(.borderedProminent)
                        Button { importing = true } label: { Label("Import PDF", systemImage: "square.and.arrow.down") }.buttonStyle(.bordered).disabled(readingImport)
                    } else {
                        Button { importing = true } label: { Label("Import PDF", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent).disabled(readingImport)
                        Text("Camera scanning is available on supported iPhones and iPads.").font(.caption).foregroundStyle(.secondary)
                    }
                    PhotosPicker(selection: $imageSelection, matching: .images) {
                        Label("Import image for text recognition", systemImage: "photo")
                    }.buttonStyle(.bordered).disabled(readingImport)
                    Text("PDF files up to 25 MB. Review before saving; the original file stays unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                    if readingImport { ProgressView("Opening document…") }
                }.padding(.vertical, 8)
            }
            if summaryLoadError { Section { Text("SOS summaries couldn’t be loaded. Reopen Records to retry.").foregroundStyle(.secondary) } }
            if !sosSummaries.isEmpty {
                Section("Completed SOS journeys") {
                    ForEach(sosSummaries) { summary in
                        NavigationLink {
                            Form {
                                Section("Handover completed") {
                                    Text(summary.hospital).font(.headline)
                                    Text("Request \(summary.id.prefix(8))")
                                    if let date = summary.assignedAt { LabeledContent("Ambulance assigned", value: date.formatted()) }
                                    if let date = summary.pickedUpAt { LabeledContent("Patient picked up", value: date.formatted()) }
                                    LabeledContent("Handover completed", value: summary.completedAt.formatted())
                                }
                                Text("Simulation record · Saved on this device")
                            }.navigationTitle("SOS summary")
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(summary.hospital, systemImage: "checkmark.circle")
                                Text(summary.completedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Reload documents") { model.load() }
                }
            }
            if model.isLoaded && model.documents.isEmpty {
                Text("No saved PDFs yet. Add one above.").font(.subheadline).foregroundStyle(.secondary)
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
    private var scanningAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        VNDocumentCameraViewController.isSupported
        #endif
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
    var title = "Scan \(Date.now.formatted(date: .abbreviated, time: .omitted))"
    var isImport = false
}

private struct ScanReviewView: View {
    let data: Data
    let model: DocumentsViewModel
    let isImport: Bool
    @State private var title: String
    @State private var review = DocumentOCRReviewViewModel()
    @State private var showingText = false
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(data: Data, model: DocumentsViewModel, initialTitle: String, isImport: Bool) {
        self.data = data; self.model = model; self.isImport = isImport
        _title = State(initialValue: initialTitle)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Document name", text: $title).textFieldStyle(.roundedBorder).padding(.horizontal)
                    .accessibilityLabel("Document name").disabled(saving)
                Picker("Review content", selection: $showingText) {
                    Text("Document").tag(false)
                    Text("Recognised text").tag(true)
                }.pickerStyle(.segmented).padding(.horizontal)
                if review.isRecognizing { ProgressView("Recognising text on this device…") }
                if showingText {
                    Text("Check names, dates and numbers against the original. Edit any mistakes.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    TextEditor(text: $review.text).padding(.horizontal)
                        .accessibilityLabel("Recognised text for review")
                        .disabled(review.isRecognizing || saving)
                    if review.text.count > DocumentOCRReviewViewModel.maximumCharacters {
                        Text("Keep text within 50,000 characters.").font(.caption).foregroundStyle(.red)
                    }
                } else { ScannedPDFView(data: data) }
                if let error = review.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }
                if !review.isRecognizing {
                    Toggle(review.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                           ? "Save this PDF without recognised text"
                           : "I checked the recognised text against the document",
                           isOn: $review.hasReviewed)
                        .font(.subheadline).padding(.horizontal).disabled(saving)
                }
                Text("Recognition runs on this device. Reviewed text syncs to your account; the PDF stays local.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                if let error = model.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(.red).padding(.horizontal)
                }
                if saving { ProgressView("Saving document…") }
            }
            .padding(.vertical, 12)
            .navigationTitle("Review document").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.clearError(); dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task { @MainActor in
                            await Task.yield()
                            if model.save(data: data, title: title, reviewedText: review.text) { dismiss() }
                            saving = false
                        }
                    }.disabled(saving || !review.canSave || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task { await review.recognize(data) }
            .onDisappear { review.stop() }
            .interactiveDismissDisabled(saving)
        }.tint(CardioSafeTheme.accent(for: scheme))
    }
}
