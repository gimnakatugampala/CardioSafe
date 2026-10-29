import Foundation
import MapKit

enum MapPlaceCategory: String, CaseIterable, Identifiable {
    case hospitals = "Hospitals"
    case parks = "Parks"

    var id: String { rawValue }
    var symbol: String { self == .hospitals ? "cross.case.fill" : "leaf.fill" }
}

@MainActor
struct MapPlace: Identifiable {
    nonisolated let id: String
    let item: MKMapItem
    let category: MapPlaceCategory

    init(item: MKMapItem, category: MapPlaceCategory) {
        self.item = item
        self.category = category
        let coordinate = item.location.coordinate
        id = "\(item.name ?? "Unnamed place")|\(coordinate.latitude)|\(coordinate.longitude)"
    }

    var coordinate: CLLocationCoordinate2D { item.location.coordinate }
    var name: String { item.name ?? "Unnamed place" }
    var address: String { item.address?.fullAddress ?? "Address unavailable" }
}

@MainActor
struct WalkingMapRoute {
    let id = UUID()
    let polyline: MKPolyline
    let distanceMetres: Double
    let expectedSeconds: TimeInterval
    var provider: WalkingRouteProvider = .appleMaps
}

enum WalkingRouteProvider { case appleMaps, community }

enum MapSearchArea {
    static func contains(_ coordinate: CLLocationCoordinate2D, in region: MKCoordinateRegion) -> Bool {
        let latitudeDifference = abs(coordinate.latitude - region.center.latitude)
        let longitudeDifference = abs(coordinate.longitude - region.center.longitude)
            .truncatingRemainder(dividingBy: 360)
        let wrappedLongitudeDifference = min(longitudeDifference, 360 - longitudeDifference)
        return latitudeDifference <= abs(region.span.latitudeDelta) / 2
            && wrappedLongitudeDifference <= abs(region.span.longitudeDelta) / 2
    }
}
