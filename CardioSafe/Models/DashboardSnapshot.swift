import Foundation

enum HealthMetric: CaseIterable {
    case steps
    case walkingDistanceKilometres
    case heartRateBPM
}

struct HealthReading {
    let value: Double
    let recordedAt: Date
}

struct DashboardSnapshot {
    enum Connection {
        case notConnected
        case connected
    }

    var walkingPlan: WalkingPlan?

    var walkingTargetMinutes: Int? { walkingPlan?.walkingMinutes }
    var healthConnection: Connection
    var healthReadings: [HealthMetric: HealthReading]
    let guardianConnection: Connection

    static let unconfigured = DashboardSnapshot(
        walkingPlan: nil,
        healthConnection: .notConnected,
        healthReadings: [:],
        guardianConnection: .notConnected
    )
}
