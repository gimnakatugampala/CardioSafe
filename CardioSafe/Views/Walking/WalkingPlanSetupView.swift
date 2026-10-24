import SwiftUI

struct WalkingPlanSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WalkingPlanViewModel
    private let isEditing: Bool

    init(plan: WalkingPlan?, onSave: @escaping (WalkingPlan) async throws -> Void) {
        _viewModel = State(initialValue: WalkingPlanViewModel(plan: plan, savePlan: onSave))
        isEditing = plan != nil
    }

    var body: some View {
        @Bindable var form = viewModel
        NavigationStack {
            Form {
                Section {
                    Label("Use your clinician’s plan", systemImage: "cross.case")
                        .font(.headline)
                    Text("Enter the duration you were already given. CardioSafe does not choose a walking or rest target for you.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Walking target") {
                    minuteField("Walking duration", text: $form.walkingMinutesText)
                    if let error = viewModel.walkingError { errorLabel(error) }
                }
                Section {
                    Toggle("Include a planned rest interval", isOn: $form.includesPlannedRest)
                    if viewModel.includesPlannedRest {
                        minuteField("Rest per break", text: $form.restMinutesText)
                        if let error = viewModel.restError { errorLabel(error) }
                    }
                } header: {
                    Text("Rest · optional")
                } footer: {
                    Text("Only add a rest duration if your clinician provided one. Planned rest per break is separate from the actual total time spent resting.")
                }
                Section {
                    Label("Saved on this device. Account sync is not connected.", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = viewModel.saveError {
                    Section { errorLabel(error) }
                }
            }
            .disabled(viewModel.isSaving)
            .navigationTitle(isEditing ? "Edit walking plan" : "Walking plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await viewModel.save() { dismiss() }
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView().accessibilityLabel("Saving plan")
                        } else {
                            Text("Save")
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isSaving)
                }
            }
            .tint(CardioSafeTheme.teal)
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(viewModel.isSaving)
        }
    }

    private func minuteField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.medium))
            HStack {
                TextField("Minutes", text: text)
                    .font(.title2).monospacedDigit()
                    .accessibilityLabel("\(title) in minutes")
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Text("min").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.caption).foregroundStyle(CardioSafeTheme.alert)
            .fixedSize(horizontal: false, vertical: true)
    }
}
