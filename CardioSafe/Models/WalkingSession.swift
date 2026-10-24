import Foundation

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
