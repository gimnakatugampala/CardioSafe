import SwiftUI

struct HospitalQueuesView: View {
    let mapPlaceID: String
    @State private var model = HospitalQueueViewModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isLoading { ProgressView("Loading department queues…") }
            if let error = model.errorMessage {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                Button("Retry queues") { Task { await model.findHospital(mapPlaceID: mapPlaceID) } }
            }
            ForEach(model.departments) { queue in
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent(queue.name, value: "\(queue.waitingCount) waiting")
                    QueueTimestampView(queue: queue)
                }
            }
            if !model.isLoading && model.errorMessage == nil && model.departments.isEmpty {
                Text("No department updates have been published.").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Last reported counts; queue size does not predict treatment priority or waiting time.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await model.findHospital(mapPlaceID: mapPlaceID) }
        .onDisappear { model.stop() }
    }
}

struct QueueTimestampView: View {
    let queue: DepartmentQueue
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 3) {
                if let date = queue.updatedAt {
                    Text("Updated \(date.formatted(.relative(presentation: .named)))")
                    if context.date.timeIntervalSince(date) > 900 { Text("Update needed · Confirm with hospital") }
                } else { Text("Update time unavailable") }
                if queue.isCached { Text("Cached or pending update · Not confirmed live") }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
