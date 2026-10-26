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
            Section("New requests") {
                let pending = model.requests.filter { $0.status == "pending" }
                if pending.isEmpty {
                    Label("No new SOS requests", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                ForEach(pending) { request in requestCard(request) }
            }
            let ongoing = model.requests.filter { $0.status != "pending" }
            if !ongoing.isEmpty {
                Section("In progress") {
                    ForEach(ongoing) { request in requestCard(request) }
                }
            }
        }
        .navigationTitle("SOS requests").navigationBarTitleDisplayMode(.inline)
        .task { model.listen(hospitalID: hospitalID) }
        .onDisappear { model.stop() }
    }

    private func requestCard(_ request: SOSRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(request.status == "pending" ? "New SOS" : request.status == "accepted" ? "Awaiting ambulance" : "Ambulance assigned", systemImage: request.status == "pending" ? "sos.circle.fill" : "cross.case.fill")
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
