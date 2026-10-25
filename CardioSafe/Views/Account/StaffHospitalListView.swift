import SwiftUI

struct StaffHospitalListView: View {
    let account: AppAccount
    var body: some View {
        List(account.hospitalIDs, id: \.self) { id in
            NavigationLink(id) { StaffDepartmentView(hospitalID: id, account: account) }
        }
        .navigationTitle("Assigned hospitals").navigationBarTitleDisplayMode(.inline)
    }
}

private struct StaffDepartmentView: View {
    let hospitalID: String
    let account: AppAccount
    @State private var model = HospitalQueueViewModel()
    @State private var editing: DepartmentQueue?
    var body: some View {
        List {
            if model.isLoading { ProgressView("Loading departments…") }
            if let error = model.errorMessage {
                Text(error)
                Button("Retry") { model.listen(hospitalID: hospitalID) }
            }
            ForEach(model.departments) { queue in
                Button { editing = queue } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        LabeledContent(queue.name, value: "\(queue.waitingCount) waiting")
                        QueueTimestampView(queue: queue)
                    }
                }
            }
            if !model.isLoading && model.errorMessage == nil && model.departments.isEmpty {
                Text("No departments are configured for this hospital.")
            }
        }
        .navigationTitle("Department queues").navigationBarTitleDisplayMode(.inline)
        .task { model.listen(hospitalID: hospitalID) }
        .onDisappear { model.stop() }
        .sheet(item: $editing) { queue in QueueEditor(queue: queue, model: model, account: account) }
    }
}

private struct QueueEditor: View {
    let queue: DepartmentQueue
    let model: HospitalQueueViewModel
    let account: AppAccount
    @State private var count: Int
    @Environment(\.dismiss) private var dismiss
    init(queue: DepartmentQueue, model: HospitalQueueViewModel, account: AppAccount) {
        self.queue = queue; self.model = model; self.account = account
        _count = State(initialValue: queue.waitingCount)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(queue.name) { Stepper("\(count) waiting", value: $count, in: 0...9999) }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                Button(model.isSaving ? "Saving…" : "Publish queue count") {
                    Task { if await model.update(queue, count: count, account: account) { dismiss() } }
                }
            }
            .disabled(model.isSaving)
            .navigationTitle("Update queue").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isSaving) } }
            .interactiveDismissDisabled(model.isSaving)
        }
    }
}
