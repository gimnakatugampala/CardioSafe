import SwiftUI
import MapKit

// MARK: - Find Care screen

struct CareFinderView: View {
    @Environment(HospitalArrivalViewModel.self) private var arrival
    @State private var model = CareFinderViewModel()
    @State private var locationModel = WalkingLocationViewModel()
    @State private var camera: MapCameraPosition = .region(CareFinderViewModel.previewRegion)
    @State private var selectedHospital: MapPlace?
    @State private var wantsNearby = false
    @State private var showingFullScreenMap = false
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

                // Map with expand (full screen) and + / − zoom buttons on its right edge.
                CareMapPanel(model: model, camera: $camera, onExpand: { showingFullScreenMap = true })
                    .frame(height: typeSize.isAccessibilitySize ? 360 : 290)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())) {
                    Button { search() } label: { Label("Search this area", systemImage: "arrow.clockwise") }
                        .buttonStyle(.borderedProminent)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Button { findNearMe() } label: { Label("Near me", systemImage: "location") }
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
        .fullScreenCover(isPresented: $showingFullScreenMap, onDismiss: { model.selectedPlaceID = nil }) {
            CareFullScreenMapView(model: model, camera: $camera, locationModel: locationModel,
                                  onSearch: search, onNearMe: findNearMe)
        }
        .task { if !model.hasSearched { await model.search() } }
        .onChange(of: model.selectedPlaceID) { _, id in
            // While the full-screen map is open it shows its own summary and detail sheet.
            guard !showingFullScreenMap else { return }
            if let id { selectedHospital = model.hospitals.first { $0.id == id } }
        }
        .onChange(of: locationModel.location) { _, location in
            if wantsNearby, let location { locateAndSearch(location) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { locationModel.stop(); model.clearLocation() }
        }
        .onDisappear {
            guard !showingFullScreenMap else { return }
            locationModel.stop(); model.cancelSearch()
        }
    }

    private func search() { Task { await model.search() } }

    private func findNearMe() {
        wantsNearby = true
        locationModel.start()
        if let location = locationModel.location { locateAndSearch(location) }
    }

    private func locateAndSearch(_ location: CLLocation) {
        model.useLocation(location)
        camera = .region(model.region)
        wantsNearby = false
        locationModel.stop()
        search()
    }
}

// MARK: - Map with zoom controls (inline and full screen)

struct CareMapPanel: View {
    let model: CareFinderViewModel
    @Binding var camera: MapCameraPosition
    var isFullScreen = false
    /// When set, an expand button is shown (inline mode).
    var onExpand: (() -> Void)?
    /// When set, a "my location" button is shown.
    var onLocate: (() -> Void)?

    @Environment(HospitalArrivalViewModel.self) private var arrival
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleRegion: MKCoordinateRegion
    @State private var satellite = false

    private static let minimumSpan = 0.001
    private static let maximumLatitudeSpan = 120.0
    private static let maximumLongitudeSpan = 300.0

    init(model: CareFinderViewModel, camera: Binding<MapCameraPosition>, isFullScreen: Bool = false,
         onExpand: (() -> Void)? = nil, onLocate: (() -> Void)? = nil) {
        self.model = model
        _camera = camera
        self.isFullScreen = isFullScreen
        self.onExpand = onExpand
        self.onLocate = onLocate
        _visibleRegion = State(initialValue: model.region)
    }

    private var canZoomIn: Bool { visibleRegion.span.latitudeDelta > Self.minimumSpan * 1.05 }
    private var canZoomOut: Bool { visibleRegion.span.latitudeDelta < Self.maximumLatitudeSpan * 0.95 }

    var body: some View {
        @Bindable var bindable = model
        Map(position: $camera, selection: $bindable.selectedPlaceID) {
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
        .mapStyle(satellite ? .hybrid(elevation: .flat) : .standard(pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            model.region = context.region
        }
        .overlay(alignment: .trailing) { controls.padding(.trailing, 10) }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if let onExpand {
                circleButton("arrow.up.left.and.arrow.down.right", label: "Expand map to full screen", action: onExpand)
            }
            if isFullScreen {
                Menu {
                    Toggle("Satellite imagery", isOn: $satellite)
                } label: {
                    Image(systemName: "square.3.layers.3d")
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Map style")
            }
            if let onLocate {
                circleButton("location", label: "Show hospitals near me", action: onLocate)
            }
            VStack(spacing: 0) {
                Button { zoom(by: 0.5) } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(!canZoomIn)
                .accessibilityLabel("Zoom in")
                Divider().frame(width: 28)
                Button { zoom(by: 2) } label: {
                    Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(!canZoomOut)
                .accessibilityLabel("Zoom out")
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
        .font(.body.weight(.semibold))
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel(label)
    }

    /// factor < 1 zooms in, factor > 1 zooms out.
    private func zoom(by factor: Double) {
        var region = visibleRegion
        region.span = MKCoordinateSpan(
            latitudeDelta: min(max(region.span.latitudeDelta * factor, Self.minimumSpan), Self.maximumLatitudeSpan),
            longitudeDelta: min(max(region.span.longitudeDelta * factor, Self.minimumSpan), Self.maximumLongitudeSpan))
        visibleRegion = region
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { camera = .region(region) }
    }
}

// MARK: - Full-screen map

struct CareFullScreenMapView: View {
    let model: CareFinderViewModel
    @Binding var camera: MapCameraPosition
    let locationModel: WalkingLocationViewModel
    let onSearch: () -> Void
    let onNearMe: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var detail: MapPlace?

    private var selected: MapPlace? { model.hospitals.first { $0.id == model.selectedPlaceID } }

    var body: some View {
        NavigationStack {
            CareMapPanel(model: model, camera: $camera, isFullScreen: true, onLocate: onNearMe)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
                .navigationTitle("Hospitals map")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                }
                .sheet(item: $detail, onDismiss: { model.selectedPlaceID = nil }) { hospital in
                    HospitalDetailView(hospital: hospital, distance: model.distanceText(to: hospital))
                }
        }
        .tint(CardioSafeTheme.accent(for: scheme))
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let hospital = selected {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hospital.name).font(.headline)
                        Text(hospital.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Text(model.distanceText(to: hospital)).font(.caption)
                            .foregroundStyle(CardioSafeTheme.accent(for: scheme))
                    }
                    Spacer(minLength: 8)
                    Button { model.selectedPlaceID = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close hospital summary")
                }
                Button { detail = hospital } label: {
                    Label("Hospital details", systemImage: "cross.case.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 8) {
                    if model.isSearching {
                        ProgressView()
                        Text("Searching this area…")
                    } else {
                        Text("\(model.hospitals.count) hospitals in this area")
                    }
                    Spacer(minLength: 0)
                }
                .font(.subheadline).foregroundStyle(.secondary)
                if let error = model.searchError {
                    Label(error, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.secondary)
                }
                if let message = locationModel.errorMessage {
                    Label(message, systemImage: "location.slash").font(.caption).foregroundStyle(.secondary)
                }
                Button(action: onSearch) {
                    Label("Search this area", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSearching)
                Text("Zoom or pan the map, then search to load hospitals for the visible area.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}
