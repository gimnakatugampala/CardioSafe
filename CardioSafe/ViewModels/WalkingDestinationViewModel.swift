import Foundation
import MapKit
import Observation

@MainActor @Observable final class WalkingDestinationViewModel {
    private(set) var destination: MapPlace?
    private(set) var route: WalkingMapRoute?
    private(set) var isRouting = false
    private(set) var requiresCommunityConsent = false
    private(set) var errorMessage: String?
    @ObservationIgnored private let service: any WalkingMapServicing
    @ObservationIgnored private var generation = UUID()
    init(service: (any WalkingMapServicing)? = nil) { self.service = service ?? WalkingMapService() }

    var summary: String? {
        guard let route else { return nil }
        let distance = route.distanceMetres < 1000 ? "\(Int(route.distanceMetres.rounded())) m"
            : "\((route.distanceMetres / 1000).formatted(.number.precision(.fractionLength(1)))) km"
        return "\(distance) · About \(max(1, Int(ceil(route.expectedSeconds / 60)))) min"
    }
    func clear() {
        generation = UUID(); service.cancelRoute()
        destination = nil; route = nil; errorMessage = nil; isRouting = false; requiresCommunityConsent = false
    }
    func endWalk() { clear(); service.setCommunityRoutingAllowed(false) }
    func allowCommunityRouting(from location: CLLocation?) async {
        service.setCommunityRoutingAllowed(true)
        await retry(from: location)
    }
    func select(_ place: MapPlace, from location: CLLocation?, now: Date = .now) async {
        clear()
        destination = place
        guard let location, CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy.isFinite, (0...100).contains(location.horizontalAccuracy),
              (-5...30).contains(now.timeIntervalSince(location.timestamp)) else {
            errorMessage = "A recent, accurate location is needed. Allow location access and retry."
            return
        }
        let expected = generation
        isRouting = true
        defer { if generation == expected { isRouting = false } }
        do {
            let result = try await service.walkingRoute(from: location.coordinate, to: place)
            guard generation == expected, !Task.isCancelled else { return }
            guard result.distanceMetres.isFinite, result.distanceMetres >= 0, result.distanceMetres < 1_000_000,
                  result.expectedSeconds.isFinite, result.expectedSeconds >= 0, result.expectedSeconds < 10_000_000,
                  result.polyline.pointCount > 1 else { throw CocoaError(.fileReadCorruptFile) }
            route = result
        } catch {
            guard generation == expected, !Task.isCancelled else { return }
            if let communityError = error as? CommunityRoutingError {
                requiresCommunityConsent = communityError == .consentRequired
                errorMessage = communityError.localizedDescription
            } else {
                errorMessage = "A walking route couldn’t be loaded. Check your connection and retry, or choose another place."
            }
        }
    }
    func retry(from location: CLLocation?) async {
        guard let destination else { return }
        await select(destination, from: location)
    }
}
