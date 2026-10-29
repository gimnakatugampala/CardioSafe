import Foundation
import MapKit
import Testing
@testable import CardioSafe

@MainActor struct CommunityFootRoutingTests {
    let start = CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612)
    let end = CLLocationCoordinate2D(latitude: 6.9189, longitude: 79.8693)

    @Test func requestsFootProfileWithLongitudeFirst() throws {
        let request = try CommunityFootRoutingService.request(from: start, to: end)
        let url = try #require(request.url)
        #expect(url.host == "routing.openstreetmap.de")
        #expect(url.path.contains("/routed-foot/route/v1/foot/79.861200,6.927100;79.869300,6.918900"))
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("CardioSafe") == true)
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "geometries", value: "geojson")) == true)
        #expect(throws: (any Error).self) {
            try CommunityFootRoutingService.request(from: start, to: .init(latitude: 91, longitude: 0))
        }
    }

    func fixture(coordinates: String, distance: Double = 1759.5) -> Data {
        Data("{\"code\":\"Ok\",\"routes\":[{\"distance\":\(distance),\"duration\":1411.7,\"geometry\":{\"type\":\"LineString\",\"coordinates\":\(coordinates)}}]}".utf8)
    }
    @Test func decodesFootGeometryAndRejectsUnrelatedOrInvalidPaths() throws {
        let data = fixture(coordinates: "[[79.8612,6.9271],[79.865,6.923],[79.8693,6.9189]]")
        let route = try CommunityFootRoutingService.decode(data, from: start, to: end)
        #expect(route.provider == .community && route.polyline.pointCount == 3)
        #expect(route.distanceMetres == 1759.5 && route.expectedSeconds == 1411.7)
        for invalid in [fixture(coordinates: "[[0,0],[1,1]]"),
                        fixture(coordinates: "[[79.8612,6.9271]]"),
                        fixture(coordinates: "[[79.8612,6.9271],[79.8693,96.9189]]"),
                        Data("{\"code\":\"NoRoute\"}".utf8)] {
            #expect(throws: (any Error).self) { try CommunityFootRoutingService.decode(invalid, from: start, to: end) }
        }
    }
}
