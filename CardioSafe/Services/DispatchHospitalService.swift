import Foundation
import MapKit
import FirebaseAuth
import FirebaseFirestore

@MainActor
protocol DispatchHospitalSelecting {
    func selectHospital() async throws -> DispatchDestination
    func cancel()
}

enum DispatchSelectionError: LocalizedError {
    case location, signIn, unavailable, noConnectedHospital
    var errorDescription: String? {
        switch self {
        case .location: "Your location is unavailable. Check Location access and try again."
        case .signIn: "Sign in from Profile to check connected hospital queues."
        case .unavailable: "Hospital data couldn’t be checked. Check your connection and try again."
        case .noConnectedHospital: "No connected sample hospital was found nearby. No request was sent."
        }
    }
}

@MainActor
final class DispatchHospitalService: DispatchHospitalSelecting {
    private let location = WalkingLocationViewModel()
    private let maps = WalkingMapService()

    func cancel() { location.stop(); maps.cancelSearch() }

    func selectHospital() async throws -> DispatchDestination {
        guard FirebaseSetup.isConfigured, Auth.auth().currentUser != nil else { throw DispatchSelectionError.signIn }
        defer { location.stop() }
        let origin: CLLocationCoordinate2D
        let source: String
        #if targetEnvironment(simulator)
        origin = CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612)
        source = "Sample Colombo location · Simulator"
        #else
        location.start()
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while location.location == nil && ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if location.authorization == .denied || location.authorization == .restricted { throw DispatchSelectionError.location }
            try await Task.sleep(for: .milliseconds(150))
        }
        guard let fix = location.location, fix.horizontalAccuracy <= 200,
              abs(fix.timestamp.timeIntervalSinceNow) < 30 else { throw DispatchSelectionError.location }
        origin = fix.coordinate
        source = "Your device location"
        #endif
        let region = MKCoordinateRegion(center: origin, latitudinalMeters: 16000, longitudinalMeters: 16000)
        let places: [MapPlace]
        do { places = try await maps.search(query: "", category: .hospitals, region: region) }
        catch { try Task.checkCancellation(); throw DispatchSelectionError.unavailable }
        try Task.checkCancellation()
        let position = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        do {
            let hospitals = try await Firestore.firestore().collection("hospitals").limit(to: 50).getDocuments(source: .server)
            try Task.checkCancellation()
            let matches = hospitals.documents.compactMap { document -> (String, MapPlace, Double)? in
                guard let placeID = document.data()["mapPlaceID"] as? String,
                      let place = places.first(where: { $0.id == placeID }) else { return nil }
                return (document.documentID, place, position.distance(from: place.item.location))
            }.filter { $0.2 <= 8000 }.sorted { $0.2 < $1.2 }.prefix(5)
            var candidates: [DemoHospitalCandidate] = []
            for (id, place, metres) in matches {
                try Task.checkCancellation()
                let snapshot = try await Firestore.firestore().collection("hospitals").document(id)
                    .collection("departments").getDocuments(source: .server)
                try Task.checkCancellation()
                guard !snapshot.documents.isEmpty,
                      snapshot.documents.allSatisfy({ $0.data()["isDemo"] as? Bool == true }) else { continue }
                let counts = snapshot.documents.compactMap { document -> Int? in
                    let data = document.data()
                    guard let count = data["waitingCount"] as? Int else { return nil }
                    return DemoHospitalSelection.freshCount(waiting: count, updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue())
                }
                candidates.append(DemoHospitalCandidate(hospitalID: id, name: place.name, distanceMetres: metres,
                                                        freshWaitingCount: counts.isEmpty ? nil : counts.reduce(0, +)))
            }
            guard var destination = DemoHospitalSelection.choose(candidates, locationDescription: source) else {
                throw DispatchSelectionError.noConnectedHospital
            }
            destination.patientCoordinate = DispatchCoordinate(latitude: origin.latitude, longitude: origin.longitude)
            if let match = matches.first(where: { $0.0 == destination.hospitalID }) {
                destination.hospitalCoordinate = DispatchCoordinate(latitude: match.1.coordinate.latitude, longitude: match.1.coordinate.longitude)
            }
            return destination
        } catch let error as DispatchSelectionError { throw error }
        catch { try Task.checkCancellation(); throw DispatchSelectionError.unavailable }
    }
}
