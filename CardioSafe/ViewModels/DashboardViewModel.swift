import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    struct MetricDisplay: Identifiable {
        let id: HealthMetric
        let title: String
        let symbol: String
        let value: String
        let unit: String
        let accessibilityDescription: String
    }

    private(set) var snapshot: DashboardSnapshot

    init(snapshot: DashboardSnapshot) {
        self.snapshot = snapshot
    }

    convenience init() {
        self.init(snapshot: .unconfigured)
    }

    var walkingStatus: String {
        if let minutes = snapshot.walkingTargetMinutes {
            return "\(minutes) minute target"
        }
        return "No walking plan set"
    }

    var walkingTitle: String {
        snapshot.walkingTargetMinutes == nil ? "Set up your walking plan" : "Your next walking session"
    }

    var walkingDescription: String {
        if let minutes = snapshot.walkingTargetMinutes {
            return "Your saved clinician-provided duration is \(minutes) minutes."
        }
        return "Add the walking duration provided by your clinician."
    }

    var walkingActionTitle: String {
        snapshot.walkingTargetMinutes == nil ? "View walking setup" : "View my walking plan"
    }

    var healthMetrics: [MetricDisplay] {
        HealthMetric.allCases.map { metric in
            let title: String
            let symbol: String
            let unit: String
            switch metric {
            case .steps:
                title = "Steps"; symbol = "shoeprints.fill"; unit = "steps"
            case .walkingDistanceKilometres:
                title = "Distance"; symbol = "location"; unit = "km"
            case .heartRateBPM:
                title = "Heart rate"; symbol = "heart"; unit = "bpm"
            }
            let reading = snapshot.healthConnection == .connected ? snapshot.healthReadings[metric] : nil
            let value = reading.map { $0.value.formatted(.number.precision(.fractionLength(0...1))) } ?? "—"
            let time = reading.map { $0.recordedAt.formatted(date: .omitted, time: .shortened) }
            return MetricDisplay(
                id: metric, title: title, symbol: symbol, value: value,
                unit: time.map { "\(unit) · \($0)" } ?? unit,
                accessibilityDescription: reading == nil
                    ? "\(title), no accessible data."
                    : "\(title), \(value) \(unit), recorded at \(time ?? "unknown time")."
            )
        }
    }

    var healthStatus: String {
        switch snapshot.healthConnection {
        case .notConnected: "Apple Health is not connected. No readings available."
        case .connected:
            snapshot.healthReadings.isEmpty ? "No accessible readings available." : "Latest available measurements. Check the recorded times."
        }
    }

    var guardianStatus: String {
        switch snapshot.guardianConnection {
        case .notConnected: "Not active"
        case .connected: "Simulation connected"
        }
    }

    var guardianDetail: String {
        switch snapshot.guardianConnection {
        case .notConnected: "Emergency help & safety check-ins. Dispatch demo not connected."
        case .connected: "Emergency help & safety check-ins. Dispatch simulation connected."
        }
    }
}
