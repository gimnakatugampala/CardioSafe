import SwiftUI
import MapKit

struct HospitalDetailView: View {
    let hospital: MapPlace
    let distance: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingCall = false
    @Environment(\.openURL) private var openURL
    @State private var contactError: String?

    private var phoneURL: URL? {
        guard let phone = hospital.item.phoneNumber else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(hospital.name).font(.title2.bold())
                    Text(hospital.address).foregroundStyle(.secondary)
                    Label(distance, systemImage: "location").font(.subheadline)
                    Map(initialPosition: .region(MKCoordinateRegion(center: hospital.coordinate,
                                                                    latitudinalMeters: 1500, longitudinalMeters: 1500))) {
                        Marker(hospital.name, systemImage: "cross.case.fill", coordinate: hospital.coordinate)
                            .tint(CardioSafeTheme.teal)
                    }
                    .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 18))
                    Button {
                        hospital.item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    } label: {
                        Label("Directions in Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    if phoneURL != nil, let number = hospital.item.phoneNumber {
                        Button { confirmingCall = true } label: {
                            Label(number, systemImage: "phone").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Label("Phone number unavailable", systemImage: "phone.badge.exclamationmark").foregroundStyle(.secondary)
                    }
                    if let url = hospital.item.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                        Link(destination: url) { Label("Hospital website", systemImage: "safari") }
                    }
                    if let contactError { Text(contactError).font(.caption).foregroundStyle(.secondary) }
                    Divider()
                    Text("Department queues").font(.headline)
                    Text("Live department queues are unavailable. Hospital staff updates are not connected yet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Ambulance availability").font(.headline)
                    Text("Availability and dispatch are not connected. Opening this hospital does not request an ambulance.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Place details supplied by Apple Maps. Contact the hospital to confirm services.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .navigationTitle("Hospital details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Call this hospital?", isPresented: $confirmingCall, titleVisibility: .visible) {
                if let url = phoneURL {
                    Button("Call \(hospital.item.phoneNumber ?? "hospital")") {
                        openURL(url) { accepted in
                            if !accepted { contactError = "Calls are unavailable on this device. Use the displayed number on a phone." }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
