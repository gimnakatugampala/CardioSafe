import Foundation
import MapKit
import Observation

@MainActor @Observable
final class AmbulanceTrackingViewModel {
    private(set) var polyline: MKPolyline?
    private(set) var points: [CLLocationCoordinate2D] = []
    private(set) var distanceMetres: Double?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var isIllustrative = false
    @ObservationIgnored private var directions: MKDirections?
    @ObservationIgnored private var generation = UUID()

    func load(from hospital: DispatchCoordinate, to patient: DispatchCoordinate) async {
        stop()
        let expected = generation
        isLoading = true; isIllustrative = false; errorMessage = nil; points = []; polyline = nil
        defer { if generation == expected { isLoading = false } }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: hospital.mapCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: patient.mapCoordinate))
        request.transportType = .automobile
        let calculation = MKDirections(request: request)
        directions = calculation
        do {
            let response = try await calculation.calculate()
            guard generation == expected, !Task.isCancelled else { return }
            guard let route = response.routes.first, route.polyline.pointCount > 1 else {
                useIllustrativePath(from: hospital, to: patient); return
            }
            polyline = route.polyline
            distanceMetres = route.distance
            var coordinates = [CLLocationCoordinate2D](repeating: .init(), count: route.polyline.pointCount)
            route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
            points = coordinates
        } catch {
            guard generation == expected, !Task.isCancelled else { return }
            useIllustrativePath(from: hospital, to: patient)
        }
    }

    func position(progress: Double) -> CLLocationCoordinate2D? {
        guard let first = points.first else { return nil }
        let lengths = zip(points, points.dropFirst()).map { a, b in
            CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }
        let target = lengths.reduce(0, +) * min(1, max(0, progress))
        var covered = 0.0
        for (index, length) in lengths.enumerated() {
            if length > 0 && covered + length >= target {
                let fraction = (target - covered) / length
                let a = points[index], b = points[index + 1]
                return .init(latitude: a.latitude + (b.latitude - a.latitude) * fraction,
                             longitude: a.longitude + (b.longitude - a.longitude) * fraction)
            }
            covered += length
        }
        return points.last ?? first
    }

    private func useIllustrativePath(from hospital: DispatchCoordinate, to patient: DispatchCoordinate) {
        points = [hospital.mapCoordinate, patient.mapCoordinate]
        polyline = MKPolyline(coordinates: points, count: points.count)
        isIllustrative = true
        distanceMetres = nil
    }

    func stop() { generation = UUID(); directions?.cancel(); directions = nil }
}

extension DispatchCoordinate {
    var mapCoordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
