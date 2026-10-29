import MapKit

@MainActor
protocol WalkingMapServicing {
    func search(query: String, category: MapPlaceCategory, region: MKCoordinateRegion) async throws -> [MapPlace]
    func walkingRoute(from start: CLLocationCoordinate2D, to destination: MapPlace) async throws -> WalkingMapRoute
    func cancelSearch()
    func cancelRoute()
    func setCommunityRoutingAllowed(_ allowed: Bool)
}

extension WalkingMapServicing {
    func setCommunityRoutingAllowed(_ allowed: Bool) {}
}

@MainActor
final class WalkingMapService: WalkingMapServicing {
    private var searchOperation: MKLocalSearch?
    private var routeOperation: MKDirections?
    private let community = CommunityFootRoutingService()
    private var allowsCommunityRouting = false
    private var routeGeneration = UUID()
    func setCommunityRoutingAllowed(_ allowed: Bool) { allowsCommunityRouting = allowed; if !allowed { community.cancel() } }

    func search(query: String, category: MapPlaceCategory, region: MKCoordinateRegion) async throws -> [MapPlace] {
        cancelSearch()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.isEmpty ? category.rawValue : query
        request.region = region
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: category == .hospitals ? [.hospital] : [.park])
        let operation = MKLocalSearch(request: request)
        searchOperation = operation
        let timeout = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(20))
                operation.cancel()
            } catch {}
        }
        defer {
            timeout.cancel()
            if searchOperation === operation { searchOperation = nil }
        }
        let response = try await operation.start()
        try Task.checkCancellation()
        var seen = Set<String>()
        return response.mapItems.compactMap { item in
            let place = MapPlace(item: item, category: category)
            guard MapSearchArea.contains(place.coordinate, in: region) else { return nil }
            return seen.insert(place.id).inserted ? place : nil
        }
    }

    func walkingRoute(from start: CLLocationCoordinate2D, to destination: MapPlace) async throws -> WalkingMapRoute {
        cancelRoute()
        let expected = routeGeneration
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = destination.item
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        let operation = MKDirections(request: request)
        routeOperation = operation
        let timeout = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(30))
                operation.cancel()
            } catch {}
        }
        defer {
            timeout.cancel()
            if routeOperation === operation { routeOperation = nil }
        }
        do {
            let response = try await operation.calculate()
            try Task.checkCancellation()
            guard expected == routeGeneration else { throw CancellationError() }
            guard let route = response.routes.first else { throw MapServiceError.noRoute }
            return WalkingMapRoute(polyline: route.polyline, distanceMetres: route.distance, expectedSeconds: route.expectedTravelTime)
        } catch {
            try Task.checkCancellation()
            guard expected == routeGeneration else { throw CancellationError() }
            guard allowsCommunityRouting else { throw CommunityRoutingError.consentRequired }
            return try await community.route(from: start, to: destination.coordinate)
        }
    }

    func cancelSearch() { searchOperation?.cancel(); searchOperation = nil }
    func cancelRoute() { routeGeneration = UUID(); routeOperation?.cancel(); routeOperation = nil; community.cancel() }

    private enum MapServiceError: Error { case noRoute }
}
