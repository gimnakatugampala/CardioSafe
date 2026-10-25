import SwiftUI

struct EmergencyHelpView: View {
    @Environment(DispatchDemoViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showingDetails = false
    private var accent: Color { scheme == .dark ? .cyan : CardioSafeTheme.teal }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Label("DEMO ONLY · No real help is requested", systemImage: "testtube.2")
                        .font(.subheadline.weight(.semibold)).padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    Image(systemName: statusSymbol)
                        .font(.system(size: 60, weight: .medium)).foregroundStyle(accent)
                        .frame(width: 120, height: 120)
                        .background(accent.opacity(0.08), in: Circle()).accessibilityHidden(true)
                    VStack(spacing: 10) {
                        Text(statusTitle).font(.title.bold()).multilineTextAlignment(.center)
                        Text(statusDetail).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let minutes = model.sampleETAMinutes {
                        VStack(spacing: 4) {
                            Text("\(minutes) min").font(.system(size: 42, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("Sample arrival time · Demo").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if model.isActive {
                        ProgressView("Demo updates automatically")
                        Button("Cancel SOS demo", role: .destructive) { model.cancel() }
                            .frame(maxWidth: .infinity, minHeight: 50).buttonStyle(.bordered)
                    } else {
                        Button { model.start() } label: {
                            Text(model.stage == .ready ? "Start SOS demo" : "Try demo again")
                                .font(.headline).frame(maxWidth: .infinity).padding(19)
                        }.buttonStyle(.plain).foregroundStyle(.white)
                            .background(CardioSafeTheme.alert, in: RoundedRectangle(cornerRadius: 18))
                    }
                    Text("For a real emergency, contact local emergency services using your phone.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    DisclosureGroup("Demo details", isExpanded: $showingDetails) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Asiri Central is an example hospital. The demo does not compare distance or queues, notify hospitals, share your location or track a vehicle. Arrival times are illustrative.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(model.events) { event in
                                HStack {
                                    Text(event.stage.title).font(.caption)
                                    Spacer()
                                    Text(event.date, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.top, 12)
                    }.font(.subheadline).padding(16)
                        .background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 16))
                }.padding(24).frame(maxWidth: 540).frame(maxWidth: .infinity)
            }
            .background(CardioSafeTheme.background(for: scheme))
            .navigationTitle("SOS demo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .tint(accent)
        }
    }
    private var statusTitle: String {
        switch model.stage {
        case .ready: "Try emergency support"
        case .reviewing: "Finding help…"
        case .accepted: "Hospital accepted"
        case .assigned: "Ambulance assigned"
        case .enRoute: "Ambulance on the way"
        case .arrived: "Demo complete"
        case .cancelled: "Demo cancelled"
        }
    }
    private var statusDetail: String {
        switch model.stage {
        case .ready: "One tap to see how an SOS request would work."
        case .reviewing: "A simulated request is being reviewed."
        case .accepted, .assigned, .enRoute: "Asiri Central · Simulated response"
        case .arrived: "The simulated ambulance has arrived. No real service was contacted."
        case .cancelled: "The simulation has stopped."
        }
    }
    private var statusSymbol: String {
        switch model.stage {
        case .ready: "sos.circle"
        case .reviewing: "antenna.radiowaves.left.and.right"
        case .accepted: "cross.case.fill"
        case .assigned, .enRoute: "truck.box.fill"
        case .arrived: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        }
    }
}
