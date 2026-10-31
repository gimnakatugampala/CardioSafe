import SwiftUI
import MapKit

struct WalkingRecordedRouteView: View {
    let session: WalkingSession

    private var segments: [WalkingRouteSegment] { session.routeSegments ?? [] }
    private var points: [WalkingRoutePoint] { segments.flatMap(\.points) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recorded path").font(.headline)
                Spacer()
                if points.count > 1 {
                    Text(Measurement(value: session.routeDistanceMetres, unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .road))
                        .font(.subheadline.weight(.semibold))
                }
            }
            if points.count > 1 {
                HStack(alignment: .top, spacing: 20) {
                    routeStat("Distance", WalkingSession.distanceText(session.routeDistanceMetres))
                    routeStat("Avg pace", session.averagePaceText ?? "—")
                    routeStat("GPS points", "\(points.count)")
                }
            }
            if let first = points.first {
                Map {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        if segment.points.count > 1 {
                            MapPolyline(coordinates: segment.points.map(\.coordinate))
                                .stroke(CardioSafeTheme.teal, lineWidth: 5)
                        }
                    }
                    Marker("First recorded location", systemImage: "figure.walk", coordinate: first.coordinate).tint(.green)
                    if points.count > 1, let last = points.last {
                        Marker("Last recorded location", systemImage: "flag.fill", coordinate: last.coordinate).tint(CardioSafeTheme.navy)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 18))
                Text(points.count > 1
                     ? "GPS estimate. Gaps separate rest breaks and times when recording was unavailable."
                     : "Only one location was captured; there is not enough data for a path.")
                    .font(.caption).foregroundStyle(.secondary)
                if session.isSimulated {
                    Label("Simulated journey · test data, not a real walk", systemImage: "testtube.2")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Label("No GPS path was recorded for this walk.", systemImage: "location.slash")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private extension WalkingRecordedRouteView {
    func routeStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension WalkingSession {
    /// True when the walk was recorded from the simulator journey / simulated HealthKit feed.
    var isSimulated: Bool { healthSnapshot?.isSimulatorTestData == true }
    /// Average walking pace as min:sec per km, using walking time only.
    var averagePaceText: String? {
        let metres = routeDistanceMetres
        guard metres >= 50, walkingSeconds > 0 else { return nil }
        let perKm = walkingSeconds / (metres / 1000)
        guard perKm.isFinite, perKm < 3600 else { return nil }
        return String(format: "%d:%02d /km", Int(perKm) / 60, Int(perKm) % 60)
    }
    static func distanceText(_ metres: Double) -> String { WalkingJourneySimulator.distanceText(metres) }
}

#if DEBUG
#Preview("Recorded path · example") {
    let start = Date.now.addingTimeInterval(-300)
    let points = [
        WalkingRoutePoint(latitude: 6.9271, longitude: 79.8612, recordedAt: start, accuracyMetres: 5),
        WalkingRoutePoint(latitude: 6.9276, longitude: 79.8612, recordedAt: start + 60, accuracyMetres: 5),
        WalkingRoutePoint(latitude: 6.9280, longitude: 79.8615, recordedAt: start + 120, accuracyMetres: 5)
    ]
    let session = WalkingSession(id: UUID(), plan: nil, startedAt: start, endedAt: .now,
                                 intervals: [.init(kind: .walking, startedAt: start, endedAt: .now, durationSeconds: 300)],
                                 routeSegments: [.init(points: points)])
    WalkingRecordedRouteView(session: session).padding(20)
}
#endif
