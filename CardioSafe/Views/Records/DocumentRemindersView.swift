import SwiftUI

struct DocumentRemindersView: View {
    let document: ScannedDocument
    @State private var model = DocumentRemindersViewModel()
    @State private var editing: DocumentReminder?
    @State private var showingForm = false
    var body: some View {
        List {
            Section {
                Label(document.title, systemImage: "doc.text")
                Text("One-time reminders saved on this device. Notification previews keep your document details private.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { editing = nil; showingForm = true } label: {
                    Label("Add reminder", systemImage: "plus.circle.fill")
                }.disabled(!model.loaded)
            }
            if let error = model.errorMessage {
                Section { Text(error).foregroundStyle(.red)
                    if !model.loaded { Button("Retry") { model.load() } }
                }
            }
            Section("Your reminders") {
                if model.items(for: document.id).isEmpty {
                    Text("No reminders yet. Add a follow-up or a task for this document.").foregroundStyle(.secondary)
                }
                ForEach(model.items(for: document.id)) { reminder in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(reminder.title, systemImage: reminder.completed ? "checkmark.circle.fill" : "bell")
                            .font(.headline)
                        Text(reminder.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                        if reminder.completed { Text("Completed").font(.caption).foregroundStyle(.secondary) }
                        else {
                            if reminder.date <= .now { Text("Time passed").font(.caption).foregroundStyle(.secondary) }
                            HStack {
                                Button("Edit") { editing = reminder; showingForm = true }
                                Spacer()
                                Button("Mark complete") { model.finish(reminder, remove: false) }
                            }.buttonStyle(.borderless)
                        }
                        Button(reminder.completed ? "Remove" : "Cancel reminder", role: .destructive) {
                            model.finish(reminder, remove: true)
                        }.buttonStyle(.borderless).font(.subheadline)
                    }.padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Reminders").navigationBarTitleDisplayMode(.inline)
        .task { model.load() }
        .sheet(isPresented: $showingForm) {
            DocumentReminderForm(document: document, existing: editing, model: model)
        }
    }
}

private struct DocumentReminderForm: View {
    let document: ScannedDocument
    let existing: DocumentReminder?
    let model: DocumentRemindersViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var date: Date
    init(document: ScannedDocument, existing: DocumentReminder?, model: DocumentRemindersViewModel) {
        self.document = document; self.existing = existing; self.model = model
        _title = State(initialValue: existing?.title ?? "")
        _date = State(initialValue: max(existing?.date ?? .now.addingTimeInterval(3600), .now.addingTimeInterval(60)))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("For example, review my report", text: $title).accessibilityLabel("Reminder title")
                    DatePicker("When", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    Label(document.title, systemImage: "doc.text")
                    Text("CardioSafe will ask for notification permission if needed. Keep notifications enabled to receive the alert.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
                if model.busy { ProgressView("Saving reminder…") }
            }
            .navigationTitle(existing == nil ? "Add reminder" : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.save(documentID: document.id, existing: existing, title: title, date: date) { dismiss() }
                        }
                    }.disabled(model.busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(model.busy)
        }
    }
}
