import SwiftUI
import MapKit

struct AmbulanceTrackingView: View {
    let destination: DispatchDestination
    let assignedAt: Date
    let dispatch: DispatchDemoViewModel
    @State private var tracking = AmbulanceTrackingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let progress = AmbulanceJourney.progress(assignedAt: assignedAt, now: context.date)
                let arrived = progress >= 1 && tracking.polyline != nil
                Map {
                    if let patient = destination.patientCoordinate {
                        Annotation("Patient", coordinate: patient.mapCoordinate, anchor: .bottom) {
                            Image(systemName: "person.fill")
                                .font(.title3).padding(12).foregroundStyle(.white)
                                .background(.blue, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 3))
                        }
                    }
                    if let hospital = destination.hospitalCoordinate {
                        Marker(destination.name, systemImage: "cross.case.fill", coordinate: hospital.mapCoordinate).tint(.teal)
                    }
                    if let route = tracking.polyline {
                        MapPolyline(route).stroke(.blue.opacity(0.65), style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: tracking.isIllustrative ? [8, 6] : []))
                    }
                    if let ambulance = tracking.position(progress: progress) {
                        Annotation("Ambulance · Simulated", coordinate: ambulance) {
                            Image(systemName: "cross.case.fill")
                                .font(.title3).padding(12).foregroundStyle(.white)
                                .background(.red, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: 3))
                                .shadow(radius: 3)
                        }
                    }
                }
                .mapControls { MapCompass(); MapScaleView() }
                .safeAreaInset(edge: .top, spacing: 0) {
                    Label("Simulation · No real ambulance dispatched", systemImage: "info.circle")
                        .font(.caption.weight(.semibold)).padding(12).frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(arrived ? "Arrived at patient" : "Ambulance on the way").font(.title2.bold())
                                Text(destination.name).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if tracking.polyline != nil {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(AmbulanceJourney.remainingSeconds(assignedAt: assignedAt, now: context.date)) sec")
                                        .font(.title2.bold()).monospacedDigit()
                                    Text("Simulated ETA").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text(destination.locationDescription).font(.caption).foregroundStyle(.secondary)
                        if tracking.isLoading { ProgressView("Loading driving route…") }
                        if let error = tracking.errorMessage {
                            Text(error).font(.subheadline).foregroundStyle(.orange)
                            Button("Retry route") { Task { await loadRoute() } }
                        }
                        if tracking.polyline != nil {
                            ProgressView(value: progress).tint(.teal)
                            Text(tracking.isIllustrative ? "Illustrative straight-line path · Road directions unavailable" : "Driving route · Simulated movement")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("90-second simulation · Not live GPS tracking").font(.caption).foregroundStyle(.secondary)
                        }
                        if let error = dispatch.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
                        if arrived {
                            Button("Close tracking") { dismiss() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                        } else {
                            Button(dispatch.isCancelling ? "Cancelling…" : "Cancel SOS", role: .destructive) { dispatch.cancel() }
                                .buttonStyle(.bordered).disabled(dispatch.isCancelling)
                        }
                    }.padding(20).background(.regularMaterial)
                }
            }
            .navigationTitle("Ambulance tracking").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .task { await loadRoute() }
            .onDisappear { tracking.stop() }
        }
    }

    private func loadRoute() async {
        guard let hospital = destination.hospitalCoordinate, let patient = destination.patientCoordinate else { return }
        await tracking.load(from: hospital, to: patient)
    }
}
