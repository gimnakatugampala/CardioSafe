import SwiftUI

struct PatientProfileView: View {
    @State private var model: PatientProfileViewModel
    @State private var editing = false
    @State private var savedNotice = false
    @Environment(\.colorScheme) private var scheme
    init(accountID: String) {
        _model = State(initialValue: PatientProfileViewModel(accountID: accountID))
    }
    var body: some View {
        Form {
            Section {
                Label("Your personal details", systemImage: "person.text.rectangle")
                    .font(.title3.bold()).foregroundStyle(scheme == .dark ? Color.cyan : CardioSafeTheme.teal).padding(.vertical, 8)
                Text("Saved on this device for this account. These details are not sent to hospitals or emergency services.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.isLoaded {
                if editing {
                    Section("Personal details") {
                        LabeledContent("Full name") {
                            TextField("Your name", text: $model.draft.fullName).textContentType(.name)
                                .multilineTextAlignment(.trailing).accessibilityLabel("Full name")
                        }
                        Toggle("Include date of birth", isOn: Binding(
                            get: { model.draft.dateOfBirth != nil },
                            set: { model.draft.dateOfBirth = $0 ? (model.draft.dateOfBirth ?? .now) : nil }))
                        if model.draft.dateOfBirth != nil {
                            DatePicker("Date of birth", selection: Binding(
                                get: { model.draft.dateOfBirth ?? .now },
                                set: { model.draft.dateOfBirth = $0 }), in: ...Date.now, displayedComponents: .date)
                        }
                        TextField("Phone number (optional)", text: $model.draft.phoneNumber)
                            .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    }
                    Section("Emergency contact · Optional") {
                        TextField("Contact name", text: $model.draft.emergencyContactName).textContentType(.name)
                        TextField("Contact phone number", text: $model.draft.emergencyContactPhone)
                            .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    }
                } else {
                    Section("Personal details") {
                        LabeledContent("Full name", value: value(model.saved.fullName))
                        LabeledContent("Date of birth", value: model.saved.dateOfBirth?.formatted(date: .abbreviated, time: .omitted) ?? "Not provided")
                        LabeledContent("Phone", value: value(model.saved.phoneNumber))
                    }
                    Section("Emergency contact") {
                        LabeledContent("Name", value: value(model.saved.emergencyContactName))
                        LabeledContent("Phone", value: value(model.saved.emergencyContactPhone))
                    }
                    if savedNotice { Label("Profile saved on this device", systemImage: "checkmark.circle.fill").foregroundStyle(scheme == .dark ? Color.cyan : CardioSafeTheme.teal) }
                }
            }
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(CardioSafeTheme.alert)
                    if !model.isLoaded { Button("Retry loading") { model.load() } }
                }
            }
        }
        .scrollContentBackground(.hidden).background(CardioSafeTheme.background(for: scheme))
        .navigationTitle("My details").navigationBarTitleDisplayMode(.inline)
        .tint(scheme == .dark ? Color.cyan : CardioSafeTheme.teal)
        .toolbar {
            if model.isLoaded {
                ToolbarItem(placement: .primaryAction) {
                    Button(editing ? "Save" : "Edit") {
                        if editing {
                            if model.save() { editing = false; savedNotice = true }
                        } else { model.beginEditing(); editing = true; savedNotice = false }
                    }.fontWeight(.semibold)
                }
                if editing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.beginEditing(); editing = false }
                    }
                }
            }
        }
        .task {
            model.load()
            if model.isLoaded && model.saved.fullName.isEmpty { model.beginEditing(); editing = true }
        }
    }
    private func value(_ text: String) -> String { text.isEmpty ? "Not provided" : text }
}
