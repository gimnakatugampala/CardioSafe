import Foundation
import MapKit
import Testing
@testable import CardioSafe

@MainActor struct WalkingMapLayersTests {
    @MainActor final class Service: WalkingMapServicing {
        var calls: [MapPlaceCategory] = []
        var results: [MapPlaceCategory: [MapPlace]] = [:]
        var failHospital = false
        var suspended = false
        var continuation: CheckedContinuation<[MapPlace], Never>?
        func search(query: String, category: MapPlaceCategory, region: MKCoordinateRegion) async throws -> [MapPlace] {
            calls.append(category)
            if suspended { return await withCheckedContinuation { continuation = $0 } }
            if category == .hospitals && failHospital { throw CocoaError(.fileReadUnknown) }
            return results[category, default: []]
        }
        func walkingRoute(from start: CLLocationCoordinate2D, to destination: MapPlace) async throws -> WalkingMapRoute { throw CocoaError(.featureUnsupported) }
        func cancelSearch() {}
        func cancelRoute() {}
    }
    let region = MKCoordinateRegion(center: .init(latitude: 6.9271, longitude: 79.8612), latitudinalMeters: 4000, longitudinalMeters: 4000)
    func place(_ name: String, category: MapPlaceCategory, latitude: Double = 6.9271) -> MapPlace {
        let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: 79.8612), address: nil)
        item.name = name
        item.pointOfInterestCategory = category == .parks ? .park : .hospital
        return MapPlace(item: item, category: category)
    }
    @Test func hiddenLayersNeverSearchAndDisablingRemovesPins() async {
        let service = Service()
        let model = WalkingMapLayersViewModel(service: service)
        await model.search(in: region)
        #expect(model.visiblePlaces.isEmpty && service.calls.isEmpty)
        let active = WalkingMapLayersViewModel(service: service)
        service.results[.hospitals] = [place("Hospital", category: .hospitals)]
        active.setEnabled(.hospitals, true)
        await active.search(in: region)
        #expect(service.calls == [.hospitals] && active.visiblePlaces.count == 1)
        active.setEnabled(.hospitals, false)
        #expect(active.visiblePlaces.isEmpty && !active.isSearching)
    }
    @Test func filtersDuplicatesWrongCategoriesAndDistantResultsAndCapsPins() async {
        let service = Service(), model = WalkingMapLayersViewModel(service: service)
        let duplicate = place("Duplicate", category: .hospitals)
        service.results[.hospitals] = [duplicate, duplicate, place("Wrong", category: .parks), place("Far", category: .hospitals, latitude: 8)]
        model.setEnabled(.hospitals, true)
        await model.search(in: region)
        #expect(model.visiblePlaces.count == 1)
        service.results[.hospitals] = (0..<40).map { place("Hospital \($0)", category: .hospitals) }
        await model.search(in: region)
        #expect(model.visiblePlaces.count == 20)
    }
    @Test func oneFailedLayerDoesNotHideOtherLayerResults() async {
        let service = Service(), model = WalkingMapLayersViewModel(service: service)
        service.failHospital = true
        let unclassified = place("Car park", category: .parks)
        unclassified.item.pointOfInterestCategory = .parking
        service.results[.parks] = [unclassified, place("Park", category: .parks)]
        model.setEnabled(.hospitals, true); model.setEnabled(.parks, true)
        await model.search(in: region)
        #expect(model.errors[.hospitals] != nil && model.visiblePlaces.first?.category == .parks)
        #expect(!model.isSearching)
    }
    @Test func lateResponseCannotRestoreDisabledLayer() async {
        let service = Service(), model = WalkingMapLayersViewModel(service: service)
        service.suspended = true
        model.setEnabled(.hospitals, true)
        let request = Task { await model.search(in: region) }
        while service.continuation == nil { await Task.yield() }
        model.setEnabled(.hospitals, false)
        service.continuation?.resume(returning: [place("Late", category: .hospitals)])
        await request.value
        #expect(model.visiblePlaces.isEmpty && model.places[.hospitals] == nil && !model.isSearching)
    }
}
