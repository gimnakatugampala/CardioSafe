import Foundation
import CoreLocation
import MapKit
import Observation

/// Simulator-only journey feed. It asks MapKit (MKDirections, walking) for a real route and then
/// emits GPS-shaped CLLocation fixes along that route once per second, so the walking map,
/// recorded path, distance and summary all behave as they would on a real walk.
/// It is only started from simulator builds; on a device the real GPS is used.
@MainActor @Observable
final class WalkingJourneySimulator {
    struct Journey {
        let name: String
        let start: CLLocationCoordinate2D
        let end: CLLocationCoordinate2D
    }

    static let defaultJourney = Journey(
        name: "Town Hall → Viharamahadevi Park",
        start: CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612),
        end: CLLocationCoordinate2D(latitude: 6.9189, longitude: 79.8693))

    /// Demo pace in metres per second. Faster than a real stroll so progress is visible in a short test.
    static let demoSpeed: Double = 3.5

    private(set) var isRunning = false
    private(set) var isFinished = false
    private(set) var isIllustrative = false
    private(set) var progress: Double = 0
    private(set) var routeName = defaultJourney.name
    private(set) var totalMetres: Double = 0
    private(set) var travelledMetres: Double = 0
    private(set) var statusMessage: String?
    private(set) var pathCoordinates: [CLLocationCoordinate2D] = []

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var directions: MKDirections?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cumulative: [Double] = []

    var startCoordinate: CLLocationCoordinate2D? { pathCoordinates.first }
    var endCoordinate: CLLocationCoordinate2D? { pathCoordinates.last }

    var summary: String {
        let travelled = Self.distanceText(travelledMetres), total = Self.distanceText(totalMetres)
        return "\(travelled) of \(total) · \(Int((progress * 100).rounded(.down)))%"
    }

    func start(journey: Journey = WalkingJourneySimulator.defaultJourney,
               isMoving: @escaping @MainActor () -> Bool,
               onFix: @escaping @MainActor (CLLocation) -> Void) {
        stop()
        generation = UUID()
        let token = generation
        routeName = journey.name
        isRunning = true; isFinished = false; isIllustrative = false
        progress = 0; travelledMetres = 0; totalMetres = 0
        pathCoordinates = []; cumulative = []
        statusMessage = "Planning simulated route with Apple Maps…"
        task = Task { [weak self] in
            guard let self else { return }
            let path = await self.loadPath(journey)
            guard self.generation == token, !Task.isCancelled else { return }
            self.apply(path)
            await self.run(token: token, isMoving: isMoving, onFix: onFix)
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        directions?.cancel(); directions = nil
        isRunning = false
    }

    // MARK: Route

    private func loadPath(_ journey: Journey) async -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: journey.start.latitude, longitude: journey.start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: journey.end.latitude, longitude: journey.end.longitude), address: nil)
        request.transportType = .walking
        let calculation = MKDirections(request: request)
        directions = calculation
        let timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(15)); calculation.cancel() } catch {}
        }
        defer { timeout.cancel(); directions = nil }
        do {
            let response = try await calculation.calculate()
            if let polyline = response.routes.first?.polyline, polyline.pointCount > 1 {
                var coordinates = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
                polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
                isIllustrative = false
                return coordinates
            }
        } catch {}
        // Apple Maps has limited walking data in some regions: fall back to a labelled straight path.
        isIllustrative = true
        return [journey.start, journey.end]
    }

    private func apply(_ path: [CLLocationCoordinate2D]) {
        pathCoordinates = path
        var running = 0.0
        cumulative = [0]
        for pair in zip(path, path.dropFirst()) {
            running += CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
            cumulative.append(running)
        }
        totalMetres = running
        statusMessage = isIllustrative
            ? "Illustrative straight path · Walking directions unavailable"
            : "Simulated patient is following an Apple Maps walking route"
    }

    private func position(at metres: Double) -> (CLLocationCoordinate2D, Double)? {
        guard pathCoordinates.count > 1, let total = cumulative.last, total > 0 else { return pathCoordinates.first.map { ($0, 0) } }
        let target = min(max(0, metres), total)
        for index in 1..<cumulative.count where cumulative[index] >= target {
            let a = pathCoordinates[index - 1], b = pathCoordinates[index]
            let length = cumulative[index] - cumulative[index - 1]
            let fraction = length > 0 ? (target - cumulative[index - 1]) / length : 0
            let coordinate = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * fraction,
                                                    longitude: a.longitude + (b.longitude - a.longitude) * fraction)
            let dy = b.latitude - a.latitude, dx = (b.longitude - a.longitude) * cos(a.latitude * .pi / 180)
            let course = (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            return (coordinate, course)
        }
        return pathCoordinates.last.map { ($0, 0) }
    }

    // MARK: Movement

    private func run(token: UUID, isMoving: @escaping @MainActor () -> Bool,
                     onFix: @escaping @MainActor (CLLocation) -> Void) async {
        guard totalMetres > 0 else { isRunning = false; statusMessage = "Simulated route unavailable."; return }
        var travelled = 0.0
        while !Task.isCancelled, generation == token {
            let moving = isMoving()
            if moving { travelled = min(totalMetres, travelled + Self.demoSpeed) }
            if let (coordinate, course) = position(at: travelled) {
                let fix = CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1,
                                     course: course, speed: moving ? Self.demoSpeed : 0, timestamp: Date())
                onFix(fix)
            }
            travelledMetres = travelled
            progress = min(1, travelled / totalMetres)
            if travelled >= totalMetres {
                isFinished = true; isRunning = false
                statusMessage = "Simulated journey complete · Finish the walk to save it"
                return
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }

    static func distanceText(_ metres: Double) -> String {
        metres < 1000 ? "\(Int(metres.rounded())) m"
            : "\((metres / 1000).formatted(.number.precision(.fractionLength(2)))) km"
    }
}
