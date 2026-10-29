import Foundation
import MapKit
import Testing
@testable import CardioSafe

@MainActor struct WalkingDestinationTests {
    @MainActor final class Service: WalkingMapServicing {
        var calls = 0
        var fail = false
        var needsConsent = false
        var allowed = false
        func setCommunityRoutingAllowed(_ allowed: Bool) { self.allowed = allowed }
        var suspend = false
        var continuation: CheckedContinuation<WalkingMapRoute, Never>?
        func search(query: String, category: MapPlaceCategory, region: MKCoordinateRegion) async throws -> [MapPlace] { [] }
        func walkingRoute(from start: CLLocationCoordinate2D, to destination: MapPlace) async throws -> WalkingMapRoute {
            calls += 1
            if needsConsent && !allowed { throw CommunityRoutingError.consentRequired }
            if suspend { return await withCheckedContinuation { continuation = $0 } }
            if fail { throw CocoaError(.fileReadUnknown) }
            return Self.route()
        }
        static func route(distance: Double = 450) -> WalkingMapRoute {
            let coordinates = [CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612),
                               CLLocationCoordinate2D(latitude: 6.9291, longitude: 79.8622)]
            return WalkingMapRoute(polyline: MKPolyline(coordinates: coordinates, count: coordinates.count), distanceMetres: distance, expectedSeconds: 360)
        }
        func cancelSearch() {}
        func cancelRoute() {}
    }
    func place() -> MapPlace {
        let item = MKMapItem(location: CLLocation(latitude: 6.9291, longitude: 79.8622), address: nil)
        item.name = "Destination"
        return MapPlace(item: item, category: .parks)
    }
    func fix(age: Double = 0, accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: .init(latitude: 6.9271, longitude: 79.8612), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: Date.now.addingTimeInterval(-age))
    }
    @Test func rejectsMissingOldAndInaccurateOriginsWithoutRequestingRoute() async {
        let service = Service(), model = WalkingDestinationViewModel(service: Service())
        await model.select(place(), from: nil)
        #expect(model.errorMessage != nil && model.route == nil)
        let checked = WalkingDestinationViewModel(service: service)
        await checked.select(place(), from: fix(age: 120))
        await checked.select(place(), from: fix(accuracy: 200))
        #expect(service.calls == 0 && checked.route == nil && !checked.isRouting)
    }
    @Test func successfulRouteHasEstimateAndFailureLeavesNoInventedPath() async {
        let service = Service(), model = WalkingDestinationViewModel(service: service)
        await model.select(place(), from: fix())
        #expect(model.route?.distanceMetres == 450 && model.summary == "450 m · About 6 min")
        service.fail = true
        await model.retry(from: fix())
        #expect(model.route == nil && model.destination != nil && model.errorMessage != nil)
        service.fail = false
        await model.retry(from: fix())
        #expect(model.route != nil && model.errorMessage == nil)
    }
    @Test func clearingPendingDestinationIgnoresLateRouteResponse() async {
        let service = Service(), model = WalkingDestinationViewModel(service: service)
        service.suspend = true
        let request = Task { await model.select(place(), from: fix()) }
        while service.continuation == nil { await Task.yield() }
        model.clear()
        service.continuation?.resume(returning: Service.route())
        await request.value
        #expect(model.destination == nil && model.route == nil && !model.isRouting && model.errorMessage == nil)
    }
    @Test func invalidProviderEstimateDoesNotBecomeADisplayedRoute() async {
        let service = Service(), model = WalkingDestinationViewModel(service: service)
        service.suspend = true
        let request = Task { await model.select(place(), from: fix()) }
        while service.continuation == nil { await Task.yield() }
        service.continuation?.resume(returning: Service.route(distance: .infinity))
        await request.value
        #expect(model.route == nil && model.summary == nil && model.errorMessage != nil)
    }
    @Test func communityConsentIsExplicitAndEndsWithWalk() async {
        let service = Service(), model = WalkingDestinationViewModel(service: service)
        service.needsConsent = true
        await model.select(place(), from: fix())
        #expect(model.requiresCommunityConsent && model.route == nil && !service.allowed)
        await model.allowCommunityRouting(from: fix())
        #expect(service.allowed && model.route != nil && !model.requiresCommunityConsent)
        model.endWalk()
        #expect(!service.allowed && model.destination == nil)
        await model.select(place(), from: fix())
        #expect(model.requiresCommunityConsent && model.route == nil)
    }

}
