import SwiftUI
import MapKit

struct WalkingLiveMapView: View {
    let sessionViewModel: WalkingSessionViewModel
    private var destinationModel: WalkingDestinationViewModel { sessionViewModel.destinationModel }
    private var locationModel: WalkingLocationViewModel { sessionViewModel.locationModel }
    private var simulator: WalkingJourneySimulator { sessionViewModel.journeySimulator }
    /// Simulated patient position in simulator builds, otherwise the real GPS fix.
    private var currentLocation: CLLocation? { sessionViewModel.currentLocation }
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612),
                           span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015))))
    @State private var followsPatient = true
    @State private var layers = WalkingMapLayersViewModel()
    @State private var visibleRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612), span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015))
    @State private var showingNearby = false
    @State private var showingCommunityConsent = false
    @State private var selectedPlace: MapPlace?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Map(position: $camera) { mapContents }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            if camera.positionedByUser { followsPatient = false }
        }
        .onChange(of: currentLocation) { previous, location in
            guard followsPatient, let location else { return }
            if previous == nil {
                if !layers.enabled.isEmpty { refreshLayers() }
                if destinationModel.destination != nil, destinationModel.route == nil, !destinationModel.isRouting {
                    Task { await destinationModel.retry(from: location) }
                }
            }
            camera = .region(MKCoordinateRegion(center: location.coordinate,
                                                latitudinalMeters: 650, longitudinalMeters: 650))
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 10) {
            Button {
                followsPatient = true
                if !sessionViewModel.isSimulatingJourney { locationModel.start() }
                if let location = currentLocation {
                    withAnimation(reduceMotion ? nil : .default) { camera = .region(MKCoordinateRegion(center: location.coordinate,
                                                     latitudinalMeters: 650, longitudinalMeters: 650)) }
                }
            } label: {
                Image(systemName: followsPatient ? "location.fill" : "location")
                    .font(.title3).frame(width: 48, height: 48)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Centre map on my location")
            Button {
                if let start = sessionViewModel.returnToStartPlace { chooseDestination(start) }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3).frame(width: 48, height: 48)
                    .background(.regularMaterial, in: Circle())
            }
            .disabled(sessionViewModel.returnToStartPlace == nil || destinationModel.isRouting)
            .accessibilityLabel("Return to start")
            .accessibilityHint(sessionViewModel.returnToStartPlace == nil
                ? "Available after the first accurate GPS position is recorded during this walk"
                : "Plans a walking route to your first recorded position without ending the walk")
            Menu {
                ForEach(MapPlaceCategory.allCases) { category in
                    Toggle(category.rawValue, isOn: Binding(get: { layers.enabled.contains(category) }, set: { layers.setEnabled(category, $0) }))
                }
                if !layers.enabled.isEmpty {
                    Button("Refresh this area") { refreshLayers() }
                    Button("Nearby places list") { showingNearby = true }
                }
            } label: {
                Image(systemName: "square.3.layers.3d")
                    .foregroundStyle(layers.enabled.isEmpty ? Color.primary : Color.teal)
                    .font(.title3).frame(width: 48, height: 48).background(.regularMaterial, in: Circle())
            }.accessibilityLabel("Map layers").accessibilityValue(layers.enabled.isEmpty ? "Hospitals and parks hidden" : layers.selectionKey)
            if !layers.enabled.isEmpty {
                Button { showingNearby = true } label: {
                    if layers.isSearching { ProgressView().frame(width: 48, height: 48) }
                    else { Image(systemName: "list.bullet").font(.title3).frame(width: 48, height: 48) }
                }.background(.regularMaterial, in: Circle()).accessibilityLabel("Nearby places list")
            }
            }
            .padding(.trailing, 20).padding(.top, 165)
        }
        .task(id: layers.selectionKey) {
            guard !layers.enabled.isEmpty else { return }
            await layers.search(in: searchRegion)
        }
        .onChange(of: destinationModel.route?.id) { _, _ in
            guard let route = destinationModel.route else { return }
            followsPatient = false
            let rect = route.polyline.boundingMapRect
            withAnimation(reduceMotion ? nil : .default) {
                camera = .rect(rect.insetBy(dx: -max(rect.width * 0.15, 100), dy: -max(rect.height * 0.15, 100)))
            }
        }
        .onDisappear { layers.cancel() }
        .confirmationDialog("Allow community routing for this walk?", isPresented: $showingCommunityConsent, titleVisibility: .visible) {
            Button("Allow for this walk") {
                Task { await destinationModel.allowCommunityRouting(from: currentLocation) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current coordinates and destination will be sent to FOSSGIS (routing.openstreetmap.de), which logs route requests. No health records or account details are sent. No API key or payment is needed. Permission ends when this walk finishes.")
        }
        .sheet(isPresented: $showingNearby) { WalkingNearbyPlacesView(model: layers, refresh: refreshLayers, onWalkHere: chooseDestination, onRestHere: chooseRestStop) }
        .sheet(item: $selectedPlace) { place in
            NavigationStack {
                WalkingNearbyPlaceDetail(place: place, onWalkHere: chooseDestination, onRestHere: chooseRestStop)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedPlace = nil } } }
            }.presentationDetents([.medium, .large])
        }
        .overlay(alignment: .topLeading) {
            if destinationModel.destination != nil {
                destinationCard.padding(.leading, 20).padding(.trailing, 88).padding(.top, 110)
            } else if sessionViewModel.isSimulatingJourney {
                journeyCard.padding(.leading, 20).padding(.trailing, 88).padding(.top, 110)
            } else if let error = locationModel.errorMessage {
                Label(locationModel.location == nil ? error + " Map preview is not your current position." : error, systemImage: "location.slash")
                    .font(.caption).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20).padding(.top, 110)
            } else if currentLocation == nil {
                Text("Waiting for location · Map preview")
                    .font(.caption).padding(10).background(.regularMaterial, in: Capsule())
                    .padding(.horizontal, 20).padding(.top, 110)
            }
        }
    }
    @MapContentBuilder private var mapContents: some MapContent {
            ForEach(layers.visiblePlaces.filter { $0.id != destinationModel.destination?.id }) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    Button { selectedPlace = place } label: {
                        Image(systemName: place.category.symbol).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 32, height: 32)
                            .background(place.category == .hospitals ? Color.red : Color.green, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("\(place.category == .hospitals ? "Hospital" : "Park"): \(place.name). Open details")
                }.annotationTitles(.hidden)
            }
            if let route = destinationModel.route {
                MapPolyline(route.polyline)
                    .stroke(.purple, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [10, 8]))
            }
            if let destination = destinationModel.destination {
                Marker("Destination: " + destination.name, systemImage: "flag.checkered", coordinate: destination.coordinate)
                    .tint(.purple)
            }
            if sessionViewModel.isSimulatingJourney, simulator.pathCoordinates.count > 1 {
                MapPolyline(coordinates: simulator.pathCoordinates)
                    .stroke(.orange.opacity(0.8), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [2, 8]))
                if let start = simulator.startCoordinate {
                    Marker("Journey start", systemImage: "figure.walk", coordinate: start).tint(.green)
                }
                if let end = simulator.endCoordinate {
                    Marker("Journey end", systemImage: "flag.fill", coordinate: end).tint(.orange)
                }
            }
            ForEach(Array((sessionViewModel.session?.routeSegments ?? []).enumerated()), id: \.offset) { _, segment in
                if segment.points.count > 1 {
                    MapPolyline(coordinates: segment.points.map(\.coordinate))
                        .stroke(CardioSafeTheme.teal, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            if let location = currentLocation {
                Annotation(sessionViewModel.isSimulatingJourney ? "Simulated patient" : "Your location", coordinate: location.coordinate) {
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

    private var journeyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(simulator.routeName, systemImage: "figure.walk.motion").font(.subheadline.bold()).lineLimit(2)
            ProgressView(value: simulator.progress)
            Text(simulator.summary).font(.caption.weight(.semibold))
            if let status = simulator.statusMessage { Text(status).font(.caption2).foregroundStyle(.secondary) }
            Text("Simulated data · Simulator only").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(destinationModel.destination?.name ?? "Destination", systemImage: "flag.checkered")
                        .font(.subheadline.bold()).lineLimit(2)
                    if let summary = destinationModel.summary {
                        Text(summary).font(.caption.weight(.semibold))
                    }
                }
                Spacer(minLength: 4)
                Button { destinationModel.clear() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel("Clear destination without ending walk")
            }
            if destinationModel.isRouting { ProgressView("Planning walking route…").font(.caption) }
            if destinationModel.summary != nil {
                Text("Dashed route · Solid trail")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityHint("Route estimate from its starting point, not turn-by-turn guidance")
                if destinationModel.route?.provider == .community {
                    HStack(spacing: 10) {
                        Link("© OpenStreetMap", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                        Link("FOSSGIS", destination: URL(string: "https://routing.openstreetmap.de/about.html")!)
                        Link("Fix map", destination: URL(string: "https://www.openstreetmap.org/fixthemap")!)
                    }.font(.caption2)
                }
            }
            if let error = destinationModel.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary)
                if destinationModel.requiresCommunityConsent {
                    Button("Use OpenStreetMap route") { showingCommunityConsent = true }.frame(minHeight: 44)
                } else {
                    Button("Retry route") { Task { await destinationModel.retry(from: currentLocation) } }.frame(minHeight: 44)
                }
            }
        }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    private func chooseRestStop(_ place: MapPlace) {
        sessionViewModel.restStop.select(place)
        if let location = currentLocation { sessionViewModel.restStop.update(location) }
        selectedPlace = nil; showingNearby = false
    }
    private func chooseDestination(_ place: MapPlace) {
        selectedPlace = nil; showingNearby = false
        let location = currentLocation
        Task { await destinationModel.select(place, from: location) }
    }
    private var searchRegion: MKCoordinateRegion {
        let centre = followsPatient ? (currentLocation?.coordinate ?? visibleRegion.center) : visibleRegion.center
        return MKCoordinateRegion(center: centre, latitudinalMeters: 4000, longitudinalMeters: 4000)
    }
    private func refreshLayers() {
        let region = searchRegion
        Task { await layers.search(in: region) }
    }

}
