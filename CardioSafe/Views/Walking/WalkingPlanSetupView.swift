import SwiftUI

struct WalkingPlanSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WalkingPlanViewModel
    private let onSave: (WalkingPlan) -> Void
    private let isEditing: Bool

    init(plan: WalkingPlan?, onSave: @escaping (WalkingPlan) -> Void) {
        _viewModel = State(initialValue: WalkingPlanViewModel(plan: plan))
        self.onSave = onSave
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
                    Label("This plan is kept only while the app is open for now.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isEditing ? "Edit walking plan" : "Walking plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let plan = viewModel.submit() {
                            onSave(plan)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .tint(CardioSafeTheme.teal)
            .scrollDismissesKeyboard(.interactively)
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
