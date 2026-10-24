import SwiftUI
import MapKit

struct WalkingRoutePreview: View {
    let height: CGFloat
    let onExplore: () -> Void
    private let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612),
        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
    )

    var body: some View {
        Button(action: onExplore) {
            Map(initialPosition: .region(region), interactionModes: [])
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .allowsHitTesting(false)
                .frame(height: height)
                .overlay(alignment: .topLeading) {
                    Label("Colombo · Preview", systemImage: "map")
                        .font(.caption.weight(.semibold)).padding(.horizontal, 11).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule()).padding(12)
                }
                .overlay(alignment: .bottomTrailing) {
                    Label("Explore map", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule()).padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Explore the map. Preview area: Colombo. Your location and route are not being tracked.")
    }
}

struct WalkingStatusPill: View {
    let title: String
    let symbol: String
    let colour: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(colour)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(colour.opacity(0.08), in: Capsule())
    }
}

struct WalkingMetric: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
                .foregroundStyle(CardioSafeTheme.text(for: colorScheme))
            if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct WalkingModeNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Walking data", systemImage: "figure.walk")
                .font(.caption.weight(.semibold))
            Text("Walking time, rest breaks and GPS paths are saved on this device. GPS continues while a session is active, including with the screen locked. Available health readings are saved when you finish. They require access and a supported data source.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
