import SwiftUI
import MapKit

struct WalkingLiveMapView: View {
    let sessionViewModel: WalkingSessionViewModel
    private var locationModel: WalkingLocationViewModel { sessionViewModel.locationModel }
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612),
                           span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015))))
    @State private var followsPatient = true

    var body: some View {
        Map(position: $camera) {
            ForEach(Array((sessionViewModel.session?.routeSegments ?? []).enumerated()), id: \.offset) { _, segment in
                if segment.points.count > 1 {
                    MapPolyline(coordinates: segment.points.map(\.coordinate))
                        .stroke(CardioSafeTheme.teal, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            if let location = locationModel.location {
                Annotation("Your location", coordinate: location.coordinate) {
                    ZStack {
                        Circle().fill(.blue.opacity(0.15)).frame(width: 62, height: 62)
                        Circle().fill(.blue).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(.white, lineWidth: 4))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    }
                    .accessibilityLabel("Your current location")
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { _ in
            if camera.positionedByUser { followsPatient = false }
        }
        .onChange(of: locationModel.location) { _, location in
            guard followsPatient, let location else { return }
            camera = .region(MKCoordinateRegion(center: location.coordinate,
                                                latitudinalMeters: 650, longitudinalMeters: 650))
        }
        .overlay(alignment: .topTrailing) {
            Button {
                followsPatient = true
                locationModel.start()
                if let location = locationModel.location {
                    withAnimation { camera = .region(MKCoordinateRegion(center: location.coordinate,
                                                     latitudinalMeters: 650, longitudinalMeters: 650)) }
                }
            } label: {
                Image(systemName: followsPatient ? "location.fill" : "location")
                    .font(.title3).frame(width: 48, height: 48)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Centre map on my location")
            .padding(.trailing, 20).padding(.top, 165)
        }
        .overlay(alignment: .topLeading) {
            if let error = locationModel.errorMessage {
                Label(error, systemImage: "location.slash")
                    .font(.caption).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20).padding(.top, 110)
            } else if locationModel.location == nil {
                Text("Waiting for location · Showing Colombo preview")
                    .font(.caption).padding(10).background(.regularMaterial, in: Capsule())
                    .padding(.horizontal, 20).padding(.top, 110)
            }
        }
    }
}
