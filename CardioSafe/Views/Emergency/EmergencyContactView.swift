import SwiftUI
import CoreLocation

struct EmergencyContactView: View {
    /// Hidden when this screen is opened from inside the ambulance screen itself.
    var showsAmbulanceRequest = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(DispatchDemoViewModel.self) private var dispatch
    @State private var location = WalkingLocationViewModel()
    @State private var confirmingCall = false
    @State private var callMessage: String?
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var showingRequest = false

    private let countdownSeconds = 5

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("1990 Suwa Seriya", systemImage: "phone.fill")
                        .font(.title2.bold())
                    Text("Sri Lanka emergency ambulance service")
                        .foregroundStyle(.secondary)
                    Button { confirmingCall = true } label: {
                        Label("Call 1990", systemImage: "phone.arrow.up.right.fill")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent).tint(.red)
                    if let callMessage { Text(callMessage).font(.footnote) }
                    #if targetEnvironment(simulator)
                    Text("Simulator: this button previews the call handoff. No call will be placed.")
                        .font(.footnote).foregroundStyle(.secondary)
                    #endif
                    Link("Service information", destination: URL(string: "https://www.1990.lk/faquestions/how-can-i-request-for-an-ambulance/")!)
                }

                if showsAmbulanceRequest { ambulanceSection }

                Section("Your location") {
                    TimelineView(.periodic(from: .now, by: 10)) { context in
                        if let fix = location.location,
                           let snapshot = EmergencyLocationSnapshot(location: fix, now: context.date) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(snapshot.isFresh ? "Recent location" : "Last known location · May be outdated",
                                      systemImage: snapshot.isFresh ? "location.fill" : "clock.badge.exclamationmark")
                                    .font(.headline)
                                Text("Latitude \(snapshot.latitude.formatted(.number.precision(.fractionLength(5))))")
                                Text("Longitude \(snapshot.longitude.formatted(.number.precision(.fractionLength(5))))")
                                Text("Updated \(snapshot.ageSeconds) seconds ago · Accuracy ±\(snapshot.accuracyMetres.rounded(.up).formatted(.number.precision(.fractionLength(0)))) m")
                                    .font(.footnote).foregroundStyle(.secondary)
                                #if targetEnvironment(simulator)
                                Text("Simulator location supplied by Xcode/iOS Simulator.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                #endif
                            }
                        } else {
                            Text(location.errorMessage ?? "No location available. You can still use the emergency call action.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Refresh location") { location.start() }.frame(minHeight: 44)
                    Text("Read these coordinates to the call handler if needed. Opening this screen does not send your location to emergency services.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Emergency-capable facilities") {
                    Label("Verified facility information unavailable", systemImage: "cross.case")
                    Text("Map search results do not confirm emergency capability. No verified emergency-facility directory is connected. Routine department queues are not emergency triage information.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Emergency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Call 1990 Suwa Seriya?", isPresented: $confirmingCall, titleVisibility: .visible) {
                #if targetEnvironment(simulator)
                Button("Preview call handoff") {
                    callMessage = "Call preview complete. On an iPhone, the system phone flow would open for 1990. No emergency service was contacted."
                }
                #else
                Button("Continue to Phone") {
                    openURL(URL(string: "tel:1990")!) { accepted in
                        if !accepted { callMessage = "The phone flow could not open. Dial 1990 directly using a phone." }
                    }
                }
                #endif
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This call action is separate from the CardioSafe hospital and ambulance simulation.")
            }
            .fullScreenCover(isPresented: $showingRequest) { EmergencyHelpView() }
            .onAppear { location.start() }
            .onDisappear {
                location.stop()
                cancelCountdown()
            }
        }
    }

    // MARK: Ambulance request

    private var ambulanceSection: some View {
        Section {
            if let countdown {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Sending request in \(countdown)…", systemImage: "timer")
                        .font(.headline)
                        .accessibilityAddTraits(.updatesFrequently)
                    Text("Tap Cancel to stop. Nothing has been sent yet.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(role: .cancel) { cancelCountdown() } label: {
                        Text("Cancel").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent).tint(.gray)
                }
            } else if dispatch.isActive {
                Button {
                    dispatch.start()
                    showingRequest = true
                } label: {
                    Label("Open active SOS request", systemImage: "cross.case.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent).tint(CardioSafeTheme.alert)
            } else {
                Button { beginCountdown() } label: {
                    Label("Request ambulance (demo)", systemImage: "sos.circle.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered).tint(CardioSafeTheme.alert)
                .disabled(dispatch.isRestoring)
            }
        } header: {
            Text("Ambulance request (demo)")
        } footer: {
            Text("Sends a request to a demo hospital. No real ambulance is sent. In a real emergency, call 1990.")
        }
    }

    private func beginCountdown() {
        guard countdownTask == nil else { return }
        countdown = countdownSeconds
        countdownTask = Task {
            var remaining = countdownSeconds
            while remaining > 0 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                remaining -= 1
                countdown = remaining
            }
            countdown = nil
            countdownTask = nil
            dispatch.start()
            showingRequest = true
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }
}
