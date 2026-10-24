import SwiftUI
import MapKit

struct WalkingOverviewView: View {
    let viewModel: DashboardViewModel
    @Environment(\.colorScheme) private var colorScheme

    private let previewRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612),
        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Walking companion").font(.title2.bold())
                    Text("Your plan, location and route in one place.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label("Map preview", systemImage: "map")
                        Spacer()
                        Text("Colombo").foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.semibold)).padding(14)
                    Map(initialPosition: .region(previewRegion))
                        .mapStyle(.standard(pointsOfInterest: .excludingAll))
                        .mapControls { MapCompass(); MapScaleView() }
                        .frame(height: 280)
                        .accessibilityLabel("Map preview of Colombo. This is not your current location or a walking route.")
                    Label("Default area · Location tracking not connected", systemImage: "location.slash")
                        .font(.caption).foregroundStyle(.secondary).padding(14)
                }
                .background(CardioSafeTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 12) {
                    Label(viewModel.walkingStatus, systemImage: "figure.walk")
                        .font(.headline)
                    Text(viewModel.walkingDescription).font(.subheadline).foregroundStyle(.secondary)
                    Divider()
                    Text("Walking sessions are not available in this version.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(CardioSafeTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 16))
            }
            .frame(maxWidth: 900).padding(20).frame(maxWidth: .infinity)
        }
        .background(CardioSafeTheme.background(for: colorScheme))
    }
}
