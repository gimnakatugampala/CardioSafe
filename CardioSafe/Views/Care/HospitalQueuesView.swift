import SwiftUI

struct HospitalQueuesView: View {
    let mapPlaceID: String
    @State private var model = HospitalQueueViewModel()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isLoading { ProgressView("Loading department queues…") }
            if let error = model.errorMessage {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                Button("Retry queues") { Task { await model.findHospital(mapPlaceID: mapPlaceID) } }
            }
            if model.departments.contains(where: \.isDemo) {
                Label("Demo queues · These are not the hospital’s actual counts.", systemImage: "testtube.2")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CardioSafeTheme.text(for: scheme))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CardioSafeTheme.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            ForEach(model.departments) { queue in
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: "cross.case.fill")
                        .font(.title3).foregroundStyle(CardioSafeTheme.teal)
                        .frame(width: 44, height: 44)
                        .background(CardioSafeTheme.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(queue.name).font(.subheadline.weight(.semibold))
                        QueueTimestampView(queue: queue, showsDemoLabel: false)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(queue.waitingCount)").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("waiting").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.06), lineWidth: 1) }
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
    var showsDemoLabel = true
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 3) {
                if queue.isDemo && showsDemoLabel {
                    Label("Demonstration data · Not the hospital’s actual queue", systemImage: "testtube.2")
                        .foregroundStyle(.orange)
                }
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
