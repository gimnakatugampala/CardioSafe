import SwiftUI
import MapKit

struct CareFinderView: View {
    @Environment(HospitalArrivalViewModel.self) private var arrival
    @State private var model = CareFinderViewModel()
    @State private var locationModel = WalkingLocationViewModel()
    @State private var camera: MapCameraPosition = .region(CareFinderViewModel.previewRegion)
    @State private var selectedHospital: MapPlace?
    @State private var wantsNearby = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search hospitals in this area", text: $model.query)
                        .submitLabel(.search).onSubmit { search() }
                    if !model.query.isEmpty {
                        Button { model.query = ""; search() } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Clear hospital search")
                    }
                }
                .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 14))
                Map(position: $camera, selection: $model.selectedPlaceID) {
                    if let saved = arrival.reminder {
                        MapCircle(center: .init(latitude: saved.place.latitude, longitude: saved.place.longitude),
                                  radius: HospitalArrivalReminder.radiusMetres)
                            .foregroundStyle(.teal.opacity(0.12)).stroke(.teal, lineWidth: 2)
                    }
                    ForEach(model.hospitals) { hospital in
                        Marker(hospital.name, systemImage: "cross.case.fill", coordinate: hospital.coordinate)
                            .tint(CardioSafeTheme.teal).tag(hospital.id)
                    }
                    if let coordinate = model.patientCoordinate {
                        Annotation("Your location", coordinate: coordinate) {
                            Circle().fill(.blue).frame(width: 16, height: 16)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 290).clipShape(RoundedRectangle(cornerRadius: 20))
                .onMapCameraChange(frequency: .onEnd) { context in model.region = context.region }
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())) {
                    Button { search() } label: { Label("Search this area", systemImage: "arrow.clockwise") }
                        .buttonStyle(.borderedProminent)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Button {
                        wantsNearby = true
                        locationModel.start()
                        if let location = locationModel.location { locateAndSearch(location) }
                    } label: { Label("Near me", systemImage: "location") }
                        .buttonStyle(.bordered)
                }
                .font(.subheadline).controlSize(.large)
                Text(model.patientCoordinate == nil ? "Showing the map area. Use Near me for hospitals around your location." : "Distances are straight-line estimates from your latest location.")
                    .font(.caption).foregroundStyle(.secondary)
                if wantsNearby, let error = locationModel.errorMessage {
                    Label(error, systemImage: "location.slash").font(.caption).foregroundStyle(.secondary)
                }
                if let saved = arrival.reminder {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Arrival reminder · " + saved.place.name, systemImage: "bell.badge")
                            .font(.subheadline.weight(.semibold))
                        Text(arrival.isMonitoring ? "Watching the 200 m area" : "Open hospital details to check reminder permissions")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Stop reminder", role: .destructive) { arrival.cancel() }.font(.subheadline)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
                HStack {
                    Text("Hospitals").font(.title3.bold())
                    Spacer()
                    if model.isSearching { ProgressView() }
                    else { Text("\(model.hospitals.count) found").font(.caption).foregroundStyle(.secondary) }
                }
                if let error = model.searchError {
                    ContentUnavailableView {
                        Label("Search unavailable", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: { Button("Retry") { search() } }
                } else if model.hasSearched && model.hospitals.isEmpty && !model.isSearching {
                    ContentUnavailableView("No hospitals found", systemImage: "cross.case",
                                           description: Text("Move the map or change your search, then search this area."))
                }
                ForEach(model.sortedHospitals) { hospital in
                    Button { selectedHospital = hospital } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(hospital.name).font(.headline).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            Text(hospital.address).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            Text(model.distanceText(to: hospital)).font(.caption).foregroundStyle(CardioSafeTheme.accent(for: scheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(17)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                Label("Open a hospital for available department updates. Ambulance availability is not connected.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedHospital, onDismiss: { model.selectedPlaceID = nil }) { hospital in
            HospitalDetailView(hospital: hospital, distance: model.distanceText(to: hospital))
        }
        .task { if !model.hasSearched { await model.search() } }
        .onChange(of: model.selectedPlaceID) { _, id in
            if let id { selectedHospital = model.hospitals.first { $0.id == id } }
        }
        .onChange(of: locationModel.location) { _, location in
            if wantsNearby, let location { locateAndSearch(location) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { locationModel.stop(); model.clearLocation() }
        }
        .onDisappear { locationModel.stop(); model.cancelSearch() }
    }

    private func search() { Task { await model.search() } }

    private func locateAndSearch(_ location: CLLocation) {
        model.useLocation(location)
        camera = .region(model.region)
        wantsNearby = false
        locationModel.stop()
        search()
    }
}
