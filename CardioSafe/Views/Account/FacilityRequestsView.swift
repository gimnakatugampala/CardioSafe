import SwiftUI

struct FacilityRequestsView: View {
    let hospitalID: String
    @State private var model = FacilityRequestsViewModel()
    var body: some View {
        List {
            Section {
                Label("Simulation · No real dispatch", systemImage: "info.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let completed = model.completedRequestID {
                Section {
                    Label("Request \(completed.prefix(8)) completed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.orange)
                    Button("Refresh") { model.listen(hospitalID: hospitalID) }
                }
            }
            Section("SOS requests") {
                if model.requests.isEmpty {
                    ContentUnavailableView("No active requests", systemImage: "checkmark.circle", description: Text("New patient requests appear here automatically."))
                }
                ForEach(model.requests) { request in
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Patient requesting support", systemImage: "sos.circle.fill")
                            .font(.headline)
                        Text("Request \(request.id.prefix(8))").font(.caption).foregroundStyle(.secondary)
                        if let date = request.createdAt { Text(date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary) }
                        if request.status == "assigned" {
                            Label("Ambulance assigned · Simulated journey", systemImage: "checkmark.circle.fill")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let assignedAt = request.assignedAt {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    let remaining = AmbulanceJourney.remainingSeconds(assignedAt: assignedAt, now: context.date)
                                    Button {
                                        Task { await model.complete(request, hospitalID: hospitalID) }
                                    } label: {
                                        Text(model.savingID == request.id ? "Completing…" : remaining == 0 ? "Complete request" : "Simulation arriving in \(remaining) sec")
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                    }.buttonStyle(.borderedProminent)
                                        .disabled(remaining > 0 || model.savingID != nil)
                                }
                            }
                        } else {
                            if request.status == "accepted" {
                                Label("Acceptance confirmed", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Button {
                                Task {
                                    if request.status == "accepted" { await model.assign(request, hospitalID: hospitalID) }
                                    else { await model.accept(request, hospitalID: hospitalID) }
                                }
                            } label: {
                                Text(model.savingID == request.id ? "Confirming…" : request.status == "accepted" ? "Assign ambulance" : "Accept request")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.borderedProminent).disabled(model.savingID != nil)
                        }
                    }.padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("SOS requests").navigationBarTitleDisplayMode(.inline)
        .task { model.listen(hospitalID: hospitalID) }
        .onDisappear { model.stop() }
    }
}
