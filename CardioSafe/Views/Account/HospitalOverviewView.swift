import SwiftUI

struct HospitalOverviewView: View {
    let account: AppAccount
    let hospitalID: String
    @Binding var selectedHospital: String
    let openRequests: () -> Void
    let openQueues: () -> Void
    @State private var requests = FacilityRequestsViewModel()
    @State private var queues = HospitalQueueViewModel()
    @Environment(FacilitySOSAlerts.self) private var alerts
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    private var pending: Int { requests.requests.filter { $0.status == "pending" }.count }
    private var assigned: Int { requests.requests.filter { ["assigned", "patient_arrived", "transporting", "hospital_arrived"].contains($0.status) }.count }
    private var name: String { hospitalID == "demo-asiri-central" ? "Asiri Central Hospital" : hospitalID }
    private var requestCount: String { requests.isLoading || requests.errorMessage != nil ? "—" : "\(pending)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("HOSPITAL OPERATIONS", systemImage: "cross.case.fill")
                            .font(.caption.weight(.bold)).tracking(1)
                        Spacer()
                        Text(Date.now, format: .dateTime.day().month(.abbreviated)).font(.caption)
                    }.foregroundStyle(.white.opacity(0.75))
                    Text(name).font(.largeTitle.bold()).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Circle().fill(requests.errorMessage != nil ? .orange : requests.isCached ? .yellow : .mint).frame(width: 7, height: 7)
                        Text(requests.isLoading ? "Connecting to your inbox" : requests.errorMessage != nil ? "Connection needs attention" : requests.isCached ? "Showing cached requests" : "Requests synced with Firebase")
                            .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.9))
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CardioSafeTheme.navy, in: RoundedRectangle(cornerRadius: 26))

                if account.hospitalIDs.count > 1 {
                    Picker("Hospital", selection: Binding(get: { hospitalID }, set: { selectedHospital = $0 })) {
                        ForEach(account.hospitalIDs, id: \.self) { id in Text(id == "demo-asiri-central" ? "Asiri Central Hospital" : id).tag(id) }
                    }.pickerStyle(.menu)
                }

                HStack(alignment: .top, spacing: 14) {
                    metric("New SOS", value: requestCount, symbol: "sos.circle", color: CardioSafeTheme.alert)
                    metric("Ambulances assigned", value: requests.isLoading || requests.errorMessage != nil ? "—" : "\(assigned)", symbol: "cross.case", color: CardioSafeTheme.accent(for: scheme))
                }

                ViewThatFits(in: .horizontal) {
                    if horizontalSizeClass == .regular && !typeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 24) {
                            inboxCard.frame(minWidth: 300)
                            queueCard.frame(minWidth: 300)
                        }
                    }
                    VStack(spacing: 24) { inboxCard; queueCard }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label("Stay ready for new requests", systemImage: "bell.badge").font(.headline)
                    Text("Enable notifications to be alerted when a new SOS request reaches your hospital. Keep the app open to receive alerts.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Enable SOS alerts") { Task { await alerts.enable() } }.buttonStyle(.bordered)
                    if let message = alerts.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 22))
            }.frame(maxWidth: 1200).padding(20).frame(maxWidth: .infinity)
        }
        .background(CardioSafeTheme.background(for: scheme))
        .navigationTitle("Overview").navigationBarTitleDisplayMode(.inline)
        .task(id: hospitalID) { requests.listen(hospitalID: hospitalID); queues.listen(hospitalID: hospitalID) }
        .onDisappear { requests.stop(); queues.stop() }
    }
    private var inboxCard: some View {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("SOS inbox").font(.title3.bold())
                        Spacer()
                        Image(systemName: "waveform.path.ecg").foregroundStyle(CardioSafeTheme.alert)
                    }
                    if requests.isLoading { ProgressView("Loading requests…") }
                    else if let error = requests.errorMessage {
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("Reconnect") { requests.listen(hospitalID: hospitalID) }
                    } else {
                        Text(pending == 0 ? "No requests awaiting a response" : "\(pending) request\(pending == 1 ? "" : "s") awaiting your response")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let newest = requests.requests.first(where: { $0.status == "pending" }) {
                            HStack {
                                Label("Request \(newest.id.prefix(8))", systemImage: "person.crop.circle")
                                Spacer()
                                if let date = newest.createdAt { Text(date, style: .relative).foregroundStyle(.secondary) }
                            }.font(.subheadline).padding(12)
                                .background(CardioSafeTheme.alert.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    Button(action: openRequests) {
                        HStack { Text("Open SOS requests").fontWeight(.semibold); Spacer(); Image(systemName: "arrow.right") }
                            .padding(15).foregroundStyle(.white).background(CardioSafeTheme.navy, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }.padding(20).background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 22))

    }
    private var queueCard: some View {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Department queues").font(.title3.bold())
                        Spacer()
                        Button("Manage", action: openQueues).font(.subheadline.weight(.semibold))
                    }
                    if queues.isLoading { ProgressView("Loading queues…") }
                    else if let error = queues.errorMessage { Text(error).font(.subheadline).foregroundStyle(.secondary) }
                    else if queues.departments.isEmpty { Text("No departments configured.").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(queues.departments) { queue in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(queue.staffDisplayName).font(.subheadline.weight(.semibold))
                                QueueTimestampView(queue: queue, showsDemoLabel: false)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(queue.waitingCount)").font(.title2.bold().monospacedDigit())
                                Text("waiting").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if queue.id != queues.departments.last?.id { Divider() }
                    }
                }.padding(20).background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 22))

    }
    private func metric(_ title: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
            Text(value).font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
            Text(title).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading).padding(18)
            .background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 22))
    }
}
