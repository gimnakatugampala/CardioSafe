import SwiftUI

struct EmergencyHelpView: View {
    @Environment(DispatchDemoViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showingDetails = false
    @State private var showingEmergencyContacts = false
    private var accent: Color { scheme == .dark ? .cyan : CardioSafeTheme.teal }

    var body: some View {
        Group {
        if [.assigned, .arrived, .transporting].contains(model.stage), let assignedAt = (model.stage == .transporting ? model.pickedUpAt : model.assignedAt),
           let destination = model.destination,
           destination.patientCoordinate != nil, destination.hospitalCoordinate != nil {
            AmbulanceTrackingView(destination: destination, assignedAt: assignedAt, dispatch: model)
        } else {
            requestBody
        }
        }
        .safeAreaInset(edge: .bottom) {
            Button { showingEmergencyContacts = true } label: {
                Label("Call 1990 & location", systemImage: "phone.fill")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered).padding(.horizontal).padding(.vertical, 8)
            .background(.regularMaterial)
        }
        .sheet(isPresented: $showingEmergencyContacts) { EmergencyContactView(showsAmbulanceRequest: false) }
    }

    private var requestBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Label("Simulation · No emergency service contacted", systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold)).padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    Image(systemName: statusSymbol)
                        .font(.system(size: 60, weight: .medium)).foregroundStyle(accent)
                        .frame(width: 120, height: 120)
                        .background(accent.opacity(0.08), in: Circle()).accessibilityHidden(true)
                        .contentTransition(.symbolEffect(.replace))
                    VStack(spacing: 10) {
                        Text(statusTitle).font(.title.bold()).multilineTextAlignment(.center)
                        Text(statusDetail).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let destination = model.destination {
                        VStack(spacing: 6) {
                            Label(destination.name, systemImage: "cross.case.fill").font(.headline)
                            Text("\((destination.distanceMetres / 1000).formatted(.number.precision(.fractionLength(1)))) km away · Straight-line")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(destination.locationDescription).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(18)
                        .background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 20))
                    }
                    if let minutes = model.sampleETAMinutes {
                        VStack(spacing: 4) {
                            Text("\(minutes) min").font(.system(size: 42, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("Simulated arrival time").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if [.hospitalArrived, .transporting, .arrived].contains(model.stage) {
                        Label("Waiting for the crew’s confirmation", systemImage: "checkmark.shield")
                            .foregroundStyle(accent)
                    } else if model.isActive {
                        if model.isCancelling {
                            ProgressView("Confirming cancellation…")
                        } else if model.stage == .accepted {
                            Label("Acceptance confirmed", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                        } else {
                            ProgressView(model.isRestoring ? "Restoring your SOS…" : model.stage == .finding ? "Checking location, hospitals and queues…" : "Waiting for hospital response…")
                        }
                        Button(model.isCancelling ? "Cancelling…" : "Cancel SOS", role: .destructive) { model.cancel() }
                            .frame(maxWidth: .infinity, minHeight: 50).buttonStyle(.bordered).disabled(model.isCancelling || model.isRestoring)
                    } else {
                        Button { model.start() } label: {
                            Text(model.stage == .ready ? "Start SOS" : model.stage == .completed ? "Start new SOS" : "Try again")
                                .font(.headline).frame(maxWidth: .infinity).padding(19)
                        }.buttonStyle(.plain).foregroundStyle(.white)
                            .background(CardioSafeTheme.alert, in: RoundedRectangle(cornerRadius: 18))
                    }
                    if let error = model.errorMessage, model.stage != .failed { Text(error).font(.subheadline).foregroundStyle(.orange) }
                    Text("For a real emergency, call 1990 or your local emergency number using your phone.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    DisclosureGroup("Request details", isExpanded: $showingDetails) {
                        VStack(alignment: .leading, spacing: 14) {
                            if let destination = model.destination {
                                Text(destination.reason).font(.subheadline)
                                Text(destination.reportedWaiting.map { "\($0) reported waiting across recently updated departments." } ?? "No fresh queue count is available; old or missing counts were not treated as zero.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("MapKit finds nearby hospitals. Firebase supplies connected sample department counts updated within 15 minutes. This simulation sends a request to the assigned staff screen in CardioSafe. Staff must accept it before the status changes. No real ambulance service is contacted or tracked.")
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
            .navigationTitle("Ambulance request").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .tint(accent)
            // Only reconnect to a request that is already active. A new request needs an explicit tap.
            .onAppear { if model.isActive { model.start() } }
        }
    }

    private var statusTitle: String {
        switch model.stage {
        case .ready: "Request an ambulance"
        case .finding: "Finding a nearby hospital…"
        case .failed: "Couldn’t check hospitals"
        case .reviewing: "Waiting for hospital…"
        case .accepted: "Hospital accepted"
        case .assigned: "Ambulance assigned"
        case .enRoute: "Ambulance on the way"
        case .arrived: "Ambulance has arrived"
        case .transporting: "On the way to hospital"
        case .hospitalArrived: "Arrived at hospital"
        case .completed: "Completed"
        case .cancelled: "Request cancelled"
        }
    }
    private var statusDetail: String {
        switch model.stage {
        case .ready: "Tap Start SOS to send a simulated request to a demo hospital."
        case .finding: "We’re checking nearby hospitals and connected queue information."
        case .failed: model.errorMessage ?? "No request was sent. Try again."
        case .reviewing: "Waiting for hospital staff to accept your request."
        case .accepted, .assigned, .enRoute: "Hospital staff accepted your simulation request. Waiting for ambulance assignment."
        case .arrived: "Stay at your pickup location. The crew will confirm pickup."
        case .transporting: "Your crew is taking you to the hospital. No action is needed."
        case .hospitalArrived: "Hospital staff are completing your handover. No action is needed."
        case .completed: "Hospital staff completed this request. You can close this screen or start a new SOS."
        case .cancelled: "The simulation has stopped."
        }
    }
    private var statusSymbol: String {
        switch model.stage {
        case .ready: "sos.circle"
        case .finding, .reviewing: "antenna.radiowaves.left.and.right"
        case .failed: "exclamationmark.circle"
        case .accepted: "cross.case.fill"
        case .assigned, .enRoute: "truck.box.fill"
        case .transporting: "cross.case.fill"
        case .arrived, .hospitalArrived, .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        }
    }
}
