import SwiftUI
import MapKit

struct WalkingMapView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = WalkingMapViewModel()
    @State private var camera: MapCameraPosition = .region(Self.defaultRegion)
    @State private var visibleRegion = Self.defaultRegion
    @State private var satellite = false
    @State private var showingList = false

    private static var defaultRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612),
                           span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045))
    }

    var body: some View {
        @Bindable var model = viewModel
        NavigationStack {
            Map(position: $camera, selection: $model.selectedPlaceID) {
                ForEach(viewModel.places) { place in
                    Marker(place.name, systemImage: place.category.symbol, coordinate: place.coordinate)
                        .tint(place.category == .hospitals ? CardioSafeTheme.teal : .green)
                        .tag(place.id)
                }
                if let start = viewModel.startCoordinate {
                    Annotation("Walking start", coordinate: start, anchor: .bottom) {
                        Image(systemName: "figure.walk.circle.fill")
                            .font(.title).foregroundStyle(.white, CardioSafeTheme.navy)
                            .padding(3).background(.white, in: Circle())
                            .accessibilityLabel("Chosen walking start")
                    }
                }
                if let route = viewModel.route {
                    MapPolyline(route.polyline).stroke(.blue, lineWidth: 5)
                }
            }
            .mapStyle(satellite ? .hybrid(elevation: .flat) : .standard(pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapScaleView() }
            .onMapCameraChange(frequency: .onEnd) { visibleRegion = $0.region }
            .overlay {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold)).foregroundStyle(CardioSafeTheme.navy)
                    .padding(6).background(.regularMaterial, in: Circle())
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .safeAreaInset(edge: .top, spacing: 0) { searchControls }
            .safeAreaInset(edge: .bottom, spacing: 0) { informationPanel }
            .navigationTitle("Walking map")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle("Satellite imagery", isOn: $satellite)
                        Button("Reset view to Colombo") { camera = .region(Self.defaultRegion) }
                    } label: {
                        Label("Map layers", systemImage: "square.3.layers.3d")
                    }
                }
            }
            .task(id: viewModel.category) { await viewModel.search(in: visibleRegion) }
            .onChange(of: viewModel.route?.id) {
                guard let route = viewModel.route else { return }
                let rect = route.polyline.boundingMapRect
                camera = .rect(rect.insetBy(dx: -max(rect.width * 0.15, 200), dy: -max(rect.height * 0.15, 200)))
            }
            .onDisappear { viewModel.stopRequests() }
            .sheet(isPresented: $showingList) { placesList }
        }
        .tint(CardioSafeTheme.teal)
    }

    private var searchControls: some View {
        @Bindable var model = viewModel
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search hospitals or parks", text: $model.query)
                    .submitLabel(.search)
                    .onSubmit { searchArea() }
                    .accessibilityLabel("Search nearby places")
                if !viewModel.query.isEmpty {
                    Button { viewModel.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 12))
            Picker("Places to display", selection: $model.category) {
                ForEach(MapPlaceCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.symbol).tag(category)
                }
            }
            .pickerStyle(.segmented)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { searchButton; startButton }
                VStack(spacing: 8) { searchButton; startButton }
            }
        }
        .padding(12).background(.regularMaterial)
    }

    private var searchButton: some View {
        Button(action: searchArea) {
            Label("Search this area", systemImage: "arrow.clockwise")
                .font(.caption.weight(.semibold)).frame(minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isSearching)
    }

    private var startButton: some View {
        Button { viewModel.setStart(visibleRegion.center) } label: {
            Label(viewModel.startCoordinate == nil ? "Set start here" : "Move start here", systemImage: "plus.viewfinder")
                .font(.caption.weight(.semibold)).frame(minHeight: 36)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Uses the centre crosshair as the walking start, not your device location.")
    }

    private var informationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selected = viewModel.selectedPlace {
                selectedPlacePanel(selected)
            } else {
                HStack {
                    Text(viewModel.category.rawValue).font(.headline)
                    Spacer()
                    Button("List (\(viewModel.places.count))") { showingList = true }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                if viewModel.isSearching {
                    ProgressView("Finding places…").font(.subheadline)
                } else if let message = viewModel.searchMessage {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("Select a pin or open the list to preview a walking route.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text("Choose a start using the map centre. Live location tracking is not active.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    private func selectedPlacePanel(_ place: MapPlace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name).font(.headline)
                    Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Button { viewModel.clearSelection() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close place details")
            }
            if let summary = viewModel.routeSummary {
                Label(summary, systemImage: "figure.walk").font(.subheadline.bold())
                Text("Route estimate from your selected start.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let message = viewModel.routeMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                Task { await viewModel.previewRoute() }
            } label: {
                HStack {
                    if viewModel.isRouting { ProgressView() }
                    Text(viewModel.startCoordinate == nil ? "Set a start point first" : "Preview walking route")
                }
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.startCoordinate == nil || viewModel.isRouting)
        }
    }

    private var placesList: some View {
        NavigationStack {
            List {
                if viewModel.places.isEmpty {
                    Text(viewModel.searchMessage ?? "No results yet. Search an area on the map.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.places) { place in
                    Button {
                        viewModel.selectedPlaceID = place.id
                        camera = .region(MKCoordinateRegion(center: place.coordinate,
                                                           span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))
                        showingList = false
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(place.name, systemImage: place.category.symbol).font(.headline)
                            Text(place.address).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle(viewModel.category.rawValue)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showingList = false } }
            }
        }
    }

    private func searchArea() {
        Task { await viewModel.search(in: visibleRegion) }
    }
}
