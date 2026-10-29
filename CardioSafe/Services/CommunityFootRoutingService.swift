import Foundation
import MapKit

enum CommunityRoutingError: LocalizedError, Equatable {
    case consentRequired, unavailable, invalidResponse, rateLimited
    var errorDescription: String? {
        switch self {
        case .consentRequired: "Apple Maps couldn’t supply this route. An optional community walking-route service is available."
        case .unavailable: "The community walking-route service is unavailable. Please try again later."
        case .invalidResponse: "No usable walking route was returned for these locations."
        case .rateLimited: "The route service is busy. Wait a minute before trying again."
        }
    }
}

@MainActor enum CommunityRouteThrottle {
    private static var nextSlot = ContinuousClock.now
    static func wait() async throws {
        let now = ContinuousClock.now
        let slot = max(now, nextSlot)
        nextSlot = slot.advanced(by: .milliseconds(1100))
        if slot > now { try await Task.sleep(for: now.duration(to: slot)) }
        try Task.checkCancellation()
    }
}

@MainActor final class CommunityFootRoutingService {
    private let session: URLSession
    private var active: Task<WalkingMapRoute, Error>?
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }
    func cancel() { active?.cancel(); active = nil }
    func route(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> WalkingMapRoute {
        cancel()
        let request = try Self.request(from: start, to: end)
        let job = Task { @MainActor [session] in
            try await CommunityRouteThrottle.wait()
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw CommunityRoutingError.unavailable }
            if response.statusCode == 429 { throw CommunityRoutingError.rateLimited }
            guard response.statusCode == 200 else { throw CommunityRoutingError.unavailable }
            return try Self.decode(data, from: start, to: end)
        }
        active = job
        return try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
    }
    static func request(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) throws -> URLRequest {
        guard CLLocationCoordinate2DIsValid(start), CLLocationCoordinate2DIsValid(end),
              CLLocation(latitude: start.latitude, longitude: start.longitude).distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude)) <= 100_000 else {
            throw CommunityRoutingError.invalidResponse
        }
        func number(_ value: Double) -> String { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value) }
        let coordinates = "\(number(start.longitude)),\(number(start.latitude));\(number(end.longitude)),\(number(end.latitude))"
        var components = URLComponents(string: "https://routing.openstreetmap.de/routed-foot/route/v1/foot/" + coordinates)!
        components.queryItems = [URLQueryItem(name: "overview", value: "full"), URLQueryItem(name: "geometries", value: "geojson"),
                                 URLQueryItem(name: "steps", value: "false"), URLQueryItem(name: "alternatives", value: "false"),
                                 URLQueryItem(name: "radiuses", value: "100;100")]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("CardioSafe/1.0 (iOS coursework walking routes)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    private struct Response: Decodable {
        let code: String
        let routes: [Route]?
        struct Route: Decodable {
            let distance: Double
            let duration: Double
            let geometry: Geometry
        }
        struct Geometry: Decodable { let type: String; let coordinates: [[Double]] }
    }
    static func decode(_ data: Data, from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) throws -> WalkingMapRoute {
        guard data.count <= 4_000_000 else { throw CommunityRoutingError.invalidResponse }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.code == "Ok", let route = response.routes?.first,
              route.distance.isFinite, (0..<1_000_000).contains(route.distance),
              route.duration.isFinite, (0..<10_000_000).contains(route.duration),
              route.geometry.type == "LineString", (2...20_000).contains(route.geometry.coordinates.count) else {
            throw CommunityRoutingError.invalidResponse
        }
        let coordinates = try route.geometry.coordinates.map { pair -> CLLocationCoordinate2D in
            guard pair.count == 2 else { throw CommunityRoutingError.invalidResponse }
            let point = CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            guard CLLocationCoordinate2DIsValid(point) else { throw CommunityRoutingError.invalidResponse }
            return point
        }
        func separation(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }
        guard separation(coordinates[0], start) <= 200, separation(coordinates[coordinates.count - 1], end) <= 200 else {
            throw CommunityRoutingError.invalidResponse
        }
        return WalkingMapRoute(polyline: MKPolyline(coordinates: coordinates, count: coordinates.count),
                               distanceMetres: route.distance, expectedSeconds: route.duration, provider: .community)
    }
}
