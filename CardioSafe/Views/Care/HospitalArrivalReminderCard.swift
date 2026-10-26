import SwiftUI
import MapKit

struct HospitalArrivalReminderCard: View {
    let hospital: MapPlace
    @Environment(HospitalArrivalViewModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    private var isSelected: Bool { model.reminder?.place.id == hospital.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Arrival reminder", systemImage: "location.circle")
                .font(.headline)
            Text("Get a one-time notification when you enter this hospital’s 200 m area.")
                .font(.subheadline).foregroundStyle(.secondary)
            if isSelected {
                Label(model.isMonitoring ? "Monitoring arrival area" : "Monitoring needs attention",
                      systemImage: model.isMonitoring ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Stop arrival reminder", role: .destructive) { model.cancel() }
                    .buttonStyle(.bordered)
                if !model.isMonitoring {
                    Button("Retry monitoring") { Task { await model.enable(for: place) } }.disabled(model.isBusy)
                }
            } else {
                if let previous = model.reminder {
                    Text("Replaces the reminder for \(previous.place.name).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    Task { await model.enable(for: place) }
                } label: {
                    Label(model.isBusy ? "Enabling…" : enableTitle, systemImage: "bell.badge")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(model.isBusy)
            }
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let error = model.errorMessage { Text(error).font(.subheadline).foregroundStyle(.orange) }
            if model.access.permission != .always || !model.access.precise || model.errorMessage != nil {
                Button("Open app settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.font(.subheadline)
            }
            Text("Stored on this device. Background reminders need Always location and Precise Location. iOS may delay delivery; reopen CardioSafe after force quitting to resume monitoring.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 18))
    }
    private var enableTitle: String {
        switch model.access.permission {
        case .notDetermined: "Allow location"
        case .whenInUse: "Allow background reminders"
        case .denied: "Review location access"
        case .always: "Enable arrival reminder"
        }
    }
    private var place: ArrivalPlace {
        ArrivalPlace(id: hospital.id, name: hospital.name, latitude: hospital.coordinate.latitude, longitude: hospital.coordinate.longitude)
    }
}
