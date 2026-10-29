import SwiftUI

struct DocumentRemindersView: View {
    let document: ScannedDocument
    @State private var model = DocumentRemindersViewModel()
    @State private var editing: DocumentReminder?
    @State private var showingForm = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            Section {
                Label(document.title, systemImage: "doc.text")
                Text("Reminders and their repeat schedules sync to your account. Allow notifications separately on each phone.")
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
                        Text(reminder.frequency == .once
                             ? reminder.date.formatted(date: .abbreviated, time: .shortened)
                             : reminder.frequency.title + " · " + (reminder.frequency == .daily ? reminder.date.formatted(date: .omitted, time: .shortened) : reminder.date.formatted(.dateTime.weekday(.wide).hour().minute())))
                            .font(.subheadline)
                        if reminder.frequency != .once, let next = reminder.nextDate() {
                            Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                        if reminder.completed { Text("Completed").font(.caption).foregroundStyle(.secondary) }
                        else {
                            if model.deliveredIDs.contains(reminder.notificationID) {
                                Text("Delivered to Notification Centre").font(.caption).foregroundStyle(.secondary)
                            } else if reminder.frequency == .once && reminder.date <= .now {
                                Text("Time passed · Delivery not confirmed").font(.caption).foregroundStyle(.secondary)
                            }
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
        .task { model.load(); await model.refreshDelivery() }
        .onReceive(NotificationCenter.default.publisher(for: .accountDataRestored)) { _ in if !model.busy { model.load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshDelivery() } }
        }
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
    @State private var frequency: ReminderFrequency
    @State private var weekday: Int
    init(document: ScannedDocument, existing: DocumentReminder?, model: DocumentRemindersViewModel) {
        self.document = document; self.existing = existing; self.model = model
        _frequency = State(initialValue: existing?.frequency ?? .once)
        _weekday = State(initialValue: Calendar.current.component(.weekday, from: existing?.date ?? .now))
        _title = State(initialValue: existing?.title ?? "")
        _date = State(initialValue: existing?.frequency != nil && existing?.frequency != .once ? existing!.date : max(existing?.date ?? .now.addingTimeInterval(3600), .now.addingTimeInterval(60)))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("For example, review my report", text: $title).accessibilityLabel("Reminder title")
                    Picker("Repeat", selection: $frequency) {
                        ForEach(ReminderFrequency.allCases) { Text($0.title).tag($0) }
                    }
                    if frequency == .once {
                        DatePicker("When", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    } else {
                        if frequency == .weekly {
                            Picker("Day", selection: $weekday) {
                                ForEach(1...7, id: \.self) { day in Text(Calendar.current.weekdaySymbols[day - 1]).tag(day) }
                            }
                        }
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                        Text("Repeats at this phone’s local time. Marking complete or cancelling stops all future alerts.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
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
                            if await model.save(documentID: document.id, existing: existing, title: title, date: scheduledDate, frequency: frequency) { dismiss() }
                        }
                    }.disabled(model.busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(model.busy)
        }
    }
    private var scheduledDate: Date {
        guard frequency != .once else { return date }
        var parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        if frequency == .weekly { parts.weekday = weekday }
        return Calendar.current.nextDate(after: .now, matching: parts, matchingPolicy: .nextTime) ?? date
    }

}

struct ReminderDocumentDestination: View {
    let documentID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var document: ScannedDocument?
    @State private var loaded = false
    var body: some View {
        Group {
            if let document {
                SavedDocumentView(document: document, url: LocalScannedDocumentStore().url(for: document))
            } else if loaded {
                ContentUnavailableView("Record unavailable", systemImage: "doc.questionmark",
                                       description: Text("This record may have been removed or has not synced to this phone."))
            } else { ProgressView("Opening record…") }
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task {
            document = try? LocalScannedDocumentStore().load().first { $0.id == documentID }
            loaded = true
        }
    }
}
