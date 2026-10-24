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
            } else {
                Label("No GPS path was recorded for this walk.", systemImage: "location.slash")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
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
