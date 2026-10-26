import Foundation

struct DispatchDestination: Equatable, Codable {
    var patientCoordinate: DispatchCoordinate? = nil
    var hospitalCoordinate: DispatchCoordinate? = nil
    let hospitalID: String
    let name: String
    let distanceMetres: Double
    let reportedWaiting: Int?
    let reason: String
    let locationDescription: String
}

struct DemoHospitalCandidate {
    let hospitalID: String
    let name: String
    let distanceMetres: Double
    let freshWaitingCount: Int?
}

enum DemoHospitalSelection {
    static func choose(_ candidates: [DemoHospitalCandidate], locationDescription: String) -> DispatchDestination? {
        let nearby = candidates.filter { $0.distanceMetres.isFinite && $0.distanceMetres >= 0 && $0.distanceMetres <= 8000 }
        guard let nearest = nearby.map(\.distanceMetres).min() else { return nil }
        let shortlist = nearby.filter { $0.distanceMetres <= nearest + 1000 }
        let selected = shortlist.sorted {
            let first = $0.freshWaitingCount ?? Int.max
            let second = $1.freshWaitingCount ?? Int.max
            if first != second { return first < second }
            if $0.distanceMetres != $1.distanceMetres { return $0.distanceMetres < $1.distanceMetres }
            return $0.hospitalID < $1.hospitalID
        }.first!
        let reason = selected.freshWaitingCount == nil
            ? "Nearest connected hospital; current queue counts are unavailable."
            : "Smaller reported queue among connected hospitals within 1 km of the nearest."
        return DispatchDestination(hospitalID: selected.hospitalID, name: selected.name,
                                   distanceMetres: selected.distanceMetres, reportedWaiting: selected.freshWaitingCount,
                                   reason: reason, locationDescription: locationDescription)
    }
    static func freshCount(waiting: Int, updatedAt: Date?, now: Date = .now) -> Int? {
        guard (0...9999).contains(waiting), let updatedAt,
              now.timeIntervalSince(updatedAt) >= -5, now.timeIntervalSince(updatedAt) <= 900 else { return nil }
        return waiting
    }
}


struct DispatchCoordinate: Equatable, Codable {
    let latitude: Double
    let longitude: Double
}

/// Shared assignment time keeps the visual journey consistent when the sheet reopens.
enum AmbulanceJourney {
    static let duration: TimeInterval = 90
    static func progress(assignedAt: Date, now: Date) -> Double {
        min(1, max(0, now.timeIntervalSince(assignedAt) / duration))
    }
    static func remainingSeconds(assignedAt: Date, now: Date) -> Int {
        max(0, Int(ceil(duration * (1 - progress(assignedAt: assignedAt, now: now)))))
    }
}
