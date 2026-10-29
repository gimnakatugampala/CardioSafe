import Foundation
import MapKit
import Observation

@MainActor @Observable final class WalkingMapLayersViewModel {
    private(set) var enabled: Set<MapPlaceCategory> = []
    private(set) var places: [MapPlaceCategory: [MapPlace]] = [:]
    private(set) var errors: [MapPlaceCategory: String] = [:]
    private(set) var isSearching = false
    @ObservationIgnored private let service: any WalkingMapServicing
    @ObservationIgnored private var generation = UUID()
    init(service: (any WalkingMapServicing)? = nil) { self.service = service ?? WalkingMapService() }
    var selectionKey: String { MapPlaceCategory.allCases.filter { enabled.contains($0) }.map(\.rawValue).joined(separator: "|") }
    var visiblePlaces: [MapPlace] {
        var seen = Set<String>()
        return MapPlaceCategory.allCases.flatMap { enabled.contains($0) ? places[$0, default: []] : [] }
            .filter { seen.insert($0.id).inserted }
    }
    func setEnabled(_ category: MapPlaceCategory, _ value: Bool) {
        cancel()
        if value { enabled.insert(category) }
        else { enabled.remove(category); places[category] = nil; errors[category] = nil }
    }
    func cancel() { generation = UUID(); service.cancelSearch(); isSearching = false }
    func search(in region: MKCoordinateRegion) async {
        cancel()
        let expected = generation
        let categories = MapPlaceCategory.allCases.filter { enabled.contains($0) }
        guard !categories.isEmpty else { return }
        for category in categories { places[category] = []; errors[category] = nil }
        isSearching = true
        defer { if generation == expected { isSearching = false } }
        for category in categories {
            guard generation == expected, !Task.isCancelled else { return }
            do {
                let result = try await service.search(query: "", category: category, region: region)
                guard generation == expected, !Task.isCancelled else { return }
                var seen = Set<String>()
                places[category] = Array(result.filter {
                    $0.category == category && (category != .parks || $0.item.pointOfInterestCategory == .park) && MapSearchArea.contains($0.coordinate, in: region) && seen.insert($0.id).inserted
                }.prefix(20))
            } catch {
                guard generation == expected, !Task.isCancelled else { return }
                errors[category] = "\(category.rawValue) couldn’t load. Check your connection and refresh the area."
            }
        }
    }
}
