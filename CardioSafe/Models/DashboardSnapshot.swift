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

    let walkingTargetMinutes: Int?
    let healthConnection: Connection
    let healthReadings: [HealthMetric: HealthReading]
    let guardianConnection: Connection

    static let unconfigured = DashboardSnapshot(
        walkingTargetMinutes: nil,
        healthConnection: .notConnected,
        healthReadings: [:],
        guardianConnection: .notConnected
    )
}
