import Foundation
import MapKit
import Observation

@MainActor
@Observable
final class WalkingMapViewModel {
    var query = ""
    var category: MapPlaceCategory = .hospitals
    var selectedPlaceID: String? {
        didSet {
            if oldValue != selectedPlaceID { resetRoute() }
        }
    }
    private(set) var places: [MapPlace] = []
    private(set) var startCoordinate: CLLocationCoordinate2D?
    private(set) var route: WalkingMapRoute?
    private(set) var isSearching = false
    private(set) var isRouting = false
    private(set) var searchMessage: String?
    private(set) var routeMessage: String?
    @ObservationIgnored private let service: any WalkingMapServicing
    @ObservationIgnored private var searchRequestID = UUID()
    @ObservationIgnored private var routeRequestID = UUID()

    init(service: any WalkingMapServicing) { self.service = service }
    convenience init() { self.init(service: WalkingMapService()) }

    var selectedPlace: MapPlace? { places.first { $0.id == selectedPlaceID } }

    var routeSummary: String? {
        guard let route else { return nil }
        let minutes = max(1, Int(ceil(route.expectedSeconds / 60)))
        let distance = route.distanceMetres < 1000
            ? "\(Int(route.distanceMetres.rounded())) m"
            : "\((route.distanceMetres / 1000).formatted(.number.precision(.fractionLength(1)))) km"
        return "\(minutes) min walk · \(distance)"
    }

    func search(in region: MKCoordinateRegion) async {
        let requestID = UUID()
        searchRequestID = requestID
        service.cancelSearch()
        selectedPlaceID = nil
        resetRoute()
        places = []
        searchMessage = nil
        isSearching = true
        defer { if searchRequestID == requestID { isSearching = false } }
        do {
            let results = try await service.search(query: query.trimmingCharacters(in: .whitespacesAndNewlines), category: category, region: region)
            guard searchRequestID == requestID, !Task.isCancelled else { return }
            places = results
            if results.isEmpty { searchMessage = "No \(category.rawValue.lowercased()) found. Move the map or try another search." }
        } catch {
            guard searchRequestID == requestID, !Task.isCancelled else { return }
            searchMessage = "Places could not be loaded. Check your connection and search again."
        }
    }

    func setStart(_ coordinate: CLLocationCoordinate2D) {
        startCoordinate = coordinate
        resetRoute()
    }

    func previewRoute() async {
        guard let startCoordinate, let destination = selectedPlace else { return }
        resetRoute()
        let requestID = UUID()
        routeRequestID = requestID
        isRouting = true
        defer { if routeRequestID == requestID { isRouting = false } }
        do {
            let result = try await service.walkingRoute(from: startCoordinate, to: destination)
            guard routeRequestID == requestID, !Task.isCancelled else { return }
            route = result
        } catch {
            guard routeRequestID == requestID, !Task.isCancelled else { return }
            routeMessage = "A walking route is unavailable here. Choose another start or destination."
        }
    }

    func clearSelection() { selectedPlaceID = nil; resetRoute() }

    func stopRequests() {
        searchRequestID = UUID()
        service.cancelSearch()
        isSearching = false
        resetRoute()
    }

    private func resetRoute() {
        routeRequestID = UUID()
        service.cancelRoute()
        route = nil
        routeMessage = nil
        isRouting = false
    }
}
