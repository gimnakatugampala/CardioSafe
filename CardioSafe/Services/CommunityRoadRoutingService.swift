import Foundation
import MapKit

/// Driving routes from the public OSRM server run by FOSSGIS (routing.openstreetmap.de).
/// Used when Apple Maps cannot supply driving directions (e.g. limited coverage in Sri Lanka).
@MainActor final class CommunityRoadRoutingService {
    struct Route {
        let polyline: MKPolyline
        let distanceMetres: Double
        let seconds: Double
    }

    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    func routes(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> [Route] {
        let request = try Self.request(from: start, to: end)
        try await CommunityRouteThrottle.wait()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CommunityRoutingError.unavailable }
        if http.statusCode == 429 { throw CommunityRoutingError.rateLimited }
        guard http.statusCode == 200 else { throw CommunityRoutingError.unavailable }
        return try Self.decode(data, from: start, to: end)
    }

    static func request(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) throws -> URLRequest {
        guard CLLocationCoordinate2DIsValid(start), CLLocationCoordinate2DIsValid(end) else {
            throw CommunityRoutingError.invalidResponse
        }
        func n(_ v: Double) -> String { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), v) }
        let coords = "\(n(start.longitude)),\(n(start.latitude));\(n(end.longitude)),\(n(end.latitude))"
        var c = URLComponents(string: "https://routing.openstreetmap.de/routed-car/route/v1/driving/" + coords)!
        c.queryItems = [URLQueryItem(name: "overview", value: "full"),
                        URLQueryItem(name: "geometries", value: "geojson"),
                        URLQueryItem(name: "steps", value: "false"),
                        URLQueryItem(name: "alternatives", value: "true")]
        var r = URLRequest(url: c.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        r.setValue("CardioSafe/1.0 (iOS coursework hospital routes)", forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    private struct Response: Decodable {
        let code: String
        let routes: [R]?
        struct R: Decodable {
            let distance: Double
            let duration: Double
            let geometry: G
        }
        struct G: Decodable { let type: String; let coordinates: [[Double]] }
    }

    static func decode(_ data: Data, from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) throws -> [Route] {
        guard data.count <= 6_000_000 else { throw CommunityRoutingError.invalidResponse }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.code == "Ok", let items = response.routes, !items.isEmpty else {
            throw CommunityRoutingError.invalidResponse
        }
        let routes = items.compactMap { item -> Route? in
            guard item.distance.isFinite, item.distance >= 0, item.duration.isFinite, item.duration >= 0,
                  item.geometry.type == "LineString", item.geometry.coordinates.count >= 2 else { return nil }
            let points = item.geometry.coordinates.compactMap { pair -> CLLocationCoordinate2D? in
                guard pair.count == 2 else { return nil }
                let p = CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                return CLLocationCoordinate2DIsValid(p) ? p : nil
            }
            guard points.count == item.geometry.coordinates.count else { return nil }
            return Route(polyline: MKPolyline(coordinates: points, count: points.count),
                         distanceMetres: item.distance, seconds: item.duration)
        }
        guard !routes.isEmpty else { throw CommunityRoutingError.invalidResponse }
        return routes
    }
}
