import Foundation
import CoreLocation

enum WalkingSessionPhase: String, Equatable {
    case ready
    case walking
    case resting
    case finished
}

struct WalkingSessionInterval: Equatable, Codable {
    enum Kind: String, Codable {
        case walking
        case resting
    }

    let kind: Kind
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: TimeInterval
}

struct WalkingSession: Identifiable, Equatable, Codable {
    let id: UUID
    let plan: WalkingPlan?
    let startedAt: Date
    var endedAt: Date?
    var intervals: [WalkingSessionInterval]
    var routeSegments: [WalkingRouteSegment]? = nil
    var healthSnapshot: WalkingHealthSnapshot? = nil

    var walkingSeconds: TimeInterval {
        intervals.filter { $0.kind == .walking }.reduce(0) { $0 + $1.durationSeconds }
    }

    var restingSeconds: TimeInterval {
        intervals.filter { $0.kind == .resting }.reduce(0) { $0 + $1.durationSeconds }
    }

    var restPeriods: [WalkingSessionInterval] {
        intervals.filter { $0.kind == .resting }
    }
}

struct WalkingHealthSnapshot: Equatable, Codable {
    let capturedAt: Date
    let steps: Int?
    let motionDistanceMetres: Double?
    let motionUpdatedAt: Date?
    let lastHeartRateBPM: Double?
    let heartRateRecordedAt: Date?
    let activeKilocalories: Double?
    let energyThrough: Date?

    var isValid: Bool {
        if let steps, steps < 0 { return false }
        if let value = motionDistanceMetres, !value.isFinite || value < 0 { return false }
        if let value = lastHeartRateBPM, !value.isFinite || value <= 0 { return false }
        if let value = activeKilocalories, !value.isFinite || value < 0 { return false }
        return true
    }
}

struct WalkingRoutePoint: Equatable, Codable {
    let latitude: Double
    let longitude: Double
    let recordedAt: Date
    let accuracyMetres: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

struct WalkingRouteSegment: Equatable, Codable {
    var points: [WalkingRoutePoint]
}

extension WalkingSession {
    var routeDistanceMetres: Double {
        (routeSegments ?? []).reduce(0) { total, segment in
            total + zip(segment.points, segment.points.dropFirst()).reduce(0) { sum, pair in
                sum + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                    .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
            }
        }
    }
}

struct WalkingSessionTiming {
    let walkingSeconds: TimeInterval
    let restingSeconds: TimeInterval
    let currentRestSeconds: TimeInterval
    let targetSeconds: TimeInterval

    var elapsedSeconds: TimeInterval { walkingSeconds + restingSeconds }
    var displayedElapsedSeconds: TimeInterval { floor(walkingSeconds) + floor(restingSeconds) }
    var targetReached: Bool { targetSeconds > 0 && walkingSeconds >= targetSeconds }
    var progress: Double { targetSeconds > 0 ? min(1, max(0, walkingSeconds / targetSeconds)) : 0 }
}
