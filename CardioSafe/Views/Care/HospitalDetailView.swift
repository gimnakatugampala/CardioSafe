import SwiftUI
import MapKit

struct HospitalDetailView: View {
    @Environment(HospitalArrivalViewModel.self) private var arrival
    let hospital: MapPlace
    let distance: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingCall = false
    @Environment(\.openURL) private var openURL
    @State private var contactError: String?
    @Environment(\.colorScheme) private var scheme

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
                    VStack(alignment: .leading, spacing: 10) {
                        Label("CARE FINDER", systemImage: "cross.case.fill")
                            .font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(CardioSafeTheme.teal)
                        Text(hospital.name).font(.largeTitle.bold()).tracking(-0.8)
                        Text(hospital.address).font(.subheadline).foregroundStyle(.secondary)
                        Label(distance, systemImage: "location.fill")
                            .font(.caption.weight(.medium)).foregroundStyle(CardioSafeTheme.teal)
                    }
                    Map(initialPosition: .region(MKCoordinateRegion(center: hospital.coordinate,
                                                                    latitudinalMeters: 1500, longitudinalMeters: 1500))) {
                        if let saved = arrival.reminder, saved.place.id == hospital.id {
                            MapCircle(center: hospital.coordinate, radius: HospitalArrivalReminder.radiusMetres)
                                .foregroundStyle(.teal.opacity(0.12)).stroke(.teal, lineWidth: 2)
                        }
                        Marker(hospital.name, systemImage: "cross.case.fill", coordinate: hospital.coordinate)
                            .tint(CardioSafeTheme.teal)
                    }
                    .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 18))
                    Button {
                        hospital.item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    } label: {
                        Label("Directions in Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .foregroundStyle(.white)
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
                    HospitalArrivalReminderCard(hospital: hospital)
                    HStack {
                        Text("Department queues").font(.title3.bold())
                        Spacer()
                        Image(systemName: "person.3.sequence.fill").foregroundStyle(CardioSafeTheme.teal)
                    }.padding(.top, 8)
                    HospitalQueuesView(mapPlaceID: hospital.id)
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "truck.box.fill").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ambulance availability").font(.subheadline.weight(.semibold))
                            Text("Dispatch is not connected. Opening this hospital does not request an ambulance.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 18))
                    Text("Place details supplied by Apple Maps. Contact the hospital to confirm services.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .background(CardioSafeTheme.background(for: scheme))
            .foregroundStyle(CardioSafeTheme.text(for: scheme))
            .tint(CardioSafeTheme.teal)
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
