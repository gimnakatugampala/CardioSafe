import Foundation
import MapKit
import Observation

@MainActor
@Observable
final class CareFinderViewModel {
    static let previewRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08))
    var query = ""
    var region = previewRegion
    var selectedPlaceID: String?
    private(set) var hospitals: [MapPlace] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false
    private(set) var searchError: String?
    private(set) var patientCoordinate: CLLocationCoordinate2D?
    @ObservationIgnored private let service: any WalkingMapServicing
    @ObservationIgnored private var requestID = UUID()

    init(service: any WalkingMapServicing) { self.service = service }
    convenience init() { self.init(service: WalkingMapService()) }

    var distanceOrigin: CLLocationCoordinate2D { patientCoordinate ?? region.center }
    var distanceDescription: String { patientCoordinate == nil ? "from map centre" : "from your location" }
    var sortedHospitals: [MapPlace] {
        hospitals.sorted { distance(to: $0) < distance(to: $1) }
    }

    func distance(to place: MapPlace) -> CLLocationDistance {
        CLLocation(latitude: distanceOrigin.latitude, longitude: distanceOrigin.longitude)
            .distance(from: place.item.location)
    }

    func distanceText(to place: MapPlace) -> String {
        let metres = distance(to: place)
        let value = metres < 1000 ? "\(Int(metres.rounded())) m" : "\((metres / 1000).formatted(.number.precision(.fractionLength(1)))) km"
        return "\(value) \(distanceDescription) · straight-line"
    }

    func useLocation(_ location: CLLocation) {
        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 30 else { return }
        patientCoordinate = location.coordinate
        region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 8000, longitudinalMeters: 8000)
    }

    func clearLocation() { patientCoordinate = nil }

    func search() async {
        let id = UUID()
        requestID = id
        service.cancelSearch()
        let searchRegion = region
        selectedPlaceID = nil
        isSearching = true
        searchError = nil
        hospitals = []
        defer { if requestID == id { isSearching = false } }
        do {
            let result = try await service.search(query: query.trimmingCharacters(in: .whitespacesAndNewlines), category: .hospitals, region: searchRegion)
            guard requestID == id, !Task.isCancelled else { return }
            hospitals = result.filter { $0.category == .hospitals && MapSearchArea.contains($0.coordinate, in: searchRegion) }
            hasSearched = true
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            searchError = "Hospitals could not be loaded. Check your connection and try again."
            hasSearched = true
        }
    }

    func cancelSearch() {
        requestID = UUID()
        service.cancelSearch()
        isSearching = false
    }
}
