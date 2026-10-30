import SwiftUI

struct FacilityRequestsView: View {
    let hospitalID: String
    @State private var model = FacilityRequestsViewModel()
    var body: some View {
        List {
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
        let status = SOSJourneyStatus(rawValue: request.status)
        return VStack(alignment: .leading, spacing: 12) {
            Label(status?.title ?? "Request", systemImage: request.status == "pending" ? "sos.circle.fill" : "cross.case.fill").font(.headline)
            Text("Request \(request.id.prefix(8))").font(.caption).foregroundStyle(.secondary)
            if let date = request.createdAt { Text(date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary) }
            if status == .patientArrived { Text("Confirm pickup only when the patient is with the crew.").font(.subheadline).foregroundStyle(.secondary) }
            if status == .hospitalArrived { Text("Complete after the patient has been handed over to hospital staff.").font(.subheadline).foregroundStyle(.secondary) }
            if model.actionRequestID == request.id, let message = model.actionMessage {
                Label(message, systemImage: model.actionFailed ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.subheadline).foregroundStyle(model.actionFailed ? Color.orange : Color.secondary)
                    .accessibilityLabel(message)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let journeyStart = status == .assigned ? request.assignedAt : status == .transporting ? request.pickedUpAt : nil
                let needsJourney = status == .assigned || status == .transporting
                let remaining = journeyStart.map { AmbulanceJourney.remainingSeconds(assignedAt: $0, now: context.date) } ?? (needsJourney ? 90 : 0)
                Button {
                    Task { await model.advance(request, hospitalID: hospitalID) }
                } label: {
                    Text(model.savingID == request.id ? "Confirming…" : remaining > 0 ? "Ambulance en route · \(remaining) sec" : status?.action ?? "Unavailable")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(remaining > 0 || model.savingID != nil || status?.next == nil)
            }
        }.padding(.vertical, 8)
    }
}
