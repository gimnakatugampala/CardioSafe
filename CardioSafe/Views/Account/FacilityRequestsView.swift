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
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.orange)
                    Button("Refresh") { model.listen(hospitalID: hospitalID) }
                }
            }
            Section("Incoming SOS") {
                if model.requests.isEmpty {
                    ContentUnavailableView("No waiting requests", systemImage: "checkmark.circle", description: Text("New patient requests appear here automatically."))
                }
                ForEach(model.requests) { request in
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Patient requesting support", systemImage: "sos.circle.fill")
                            .font(.headline)
                        Text("Request \(request.id.prefix(8))").font(.caption).foregroundStyle(.secondary)
                        if let date = request.createdAt { Text(date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary) }
                        Button {
                            Task { await model.accept(request, hospitalID: hospitalID) }
                        } label: {
                            Text(model.savingID == request.id ? "Accepting…" : "Accept request")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.borderedProminent).disabled(model.savingID != nil)
                    }.padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("SOS requests").navigationBarTitleDisplayMode(.inline)
        .task { model.listen(hospitalID: hospitalID) }
        .onDisappear { model.stop() }
    }
}
