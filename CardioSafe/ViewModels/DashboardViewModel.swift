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
    private(set) var isLoadingPlan = false
    private(set) var isSavingPlan = false
    private(set) var hasLoadedPlan = false
    private(set) var planLoadError: String?
    private(set) var isSeedingHealth = false
    private(set) var sampleDataMessage: String?
    private(set) var isRefreshingHealth = false
    private(set) var isConnectingHealth = false
    private(set) var healthError: String?
    private(set) var healthRefreshedAt: Date?
    @ObservationIgnored private let healthService: (any DashboardHealthProviding)?
    @ObservationIgnored private let planStore: any WalkingPlanStoring
    @ObservationIgnored private let ownerID: String

    init(snapshot: DashboardSnapshot, planStore: any WalkingPlanStoring, ownerID: String, healthService: (any DashboardHealthProviding)? = nil) {
        self.healthService = healthService
        self.snapshot = snapshot
        self.planStore = planStore
        self.ownerID = ownerID
    }

    convenience init(planStore: any WalkingPlanStoring, ownerID: String, healthService: (any DashboardHealthProviding)? = nil) {
        self.init(snapshot: .unconfigured, planStore: planStore, ownerID: ownerID, healthService: healthService)
    }

    var hasRequestedHealthAccess: Bool { healthService?.hasRequestedAccess ?? false }

    var supportsSampleHealthData: Bool { healthService?.supportsSampleData ?? false }

    func loadSampleHealthData() async {
        guard let healthService, healthService.supportsSampleData, !isSeedingHealth, !isConnectingHealth else { return }
        isSeedingHealth = true
        sampleDataMessage = nil
        defer { isSeedingHealth = false }
        do {
            try await healthService.seedSampleData()
            // Wait for any older refresh before reading the samples just saved.
            while isRefreshingHealth {
                try await Task.sleep(for: .milliseconds(50))
            }
            await refreshHealth()
            sampleDataMessage = snapshot.healthReadings.isEmpty
                ? "Test samples saved to HealthKit. No readable samples returned; check read access in Health."
                : "Simulator test samples saved to HealthKit and read back. Repeating replaces today’s test set."
        } catch {
            sampleDataMessage = error.localizedDescription
        }
    }

    func connectHealth() async {
        guard let healthService, !isConnectingHealth else { return }
        isConnectingHealth = true
        defer { isConnectingHealth = false }
        do {
            try await healthService.requestAccess()
            await refreshHealth()
        } catch { healthError = "Apple Health could not be opened on this device. Please retry." }
    }

    func refreshHealth(now: Date = .now) async {
        guard let healthService, healthService.hasRequestedAccess, !isRefreshingHealth else { return }
        isRefreshingHealth = true
        defer { isRefreshingHealth = false }
        do {
            let result = try await healthService.fetchReadings(now: now)
            guard !Task.isCancelled else { return }
            snapshot.healthReadings = result.readings
            snapshot.healthConnection = .connected
            healthRefreshedAt = now
            healthError = result.hasQueryErrors ? "Some Health readings could not be refreshed. Pull down to retry." : nil
        } catch {
            snapshot.healthReadings = [:]
            snapshot.healthConnection = .notConnected
            healthError = "Health readings are unavailable. Pull down to retry."
        }
    }

    func loadWalkingPlan() async {
        guard !hasLoadedPlan, !isLoadingPlan, !isSavingPlan else { return }
        isLoadingPlan = true
        planLoadError = nil
        defer { isLoadingPlan = false }
        do {
            snapshot.walkingPlan = try await planStore.loadPlan(for: ownerID)
            hasLoadedPlan = true
        } catch {
            planLoadError = "Your saved walking plan could not be loaded. Retry before making changes."
        }
    }

    func saveWalkingPlan(_ plan: WalkingPlan) async throws {
        guard hasLoadedPlan else { throw WalkingPlanStorageError.planNotLoaded }
        guard !isSavingPlan else { throw WalkingPlanStorageError.saveInProgress }
        isSavingPlan = true
        defer { isSavingPlan = false }
        try await planStore.savePlan(plan, for: ownerID)
        snapshot.walkingPlan = plan
    }

    var walkingStatus: String {
        if isLoadingPlan { return "Loading walking plan…" }
        if planLoadError != nil { return "Walking plan unavailable" }
        if let minutes = snapshot.walkingTargetMinutes {
            return "\(minutes) minute target"
        }
        return "No walking plan set"
    }

    var walkingTitle: String {
        if isLoadingPlan { return "Loading walking plan…" }
        if planLoadError != nil { return "Walking plan unavailable" }
        return snapshot.walkingTargetMinutes == nil ? "Set up your walking plan" : "Your walking plan"
    }

    var walkingDescription: String {
        if let minutes = snapshot.walkingTargetMinutes {
            if let rest = snapshot.walkingPlan?.restMinutesPerBreak {
                return "Walk \(minutes) min · Planned rest \(rest) min per break."
            }
            return "Your clinician-provided walking target is \(minutes) minutes."
        }
        return "Add the walking duration provided by your clinician."
    }

    var walkingActionTitle: String {
        snapshot.walkingTargetMinutes == nil ? "View walking setup" : "Review walking plan"
    }

    var walkingHomeTitle: String {
        if isLoadingPlan || planLoadError != nil { return walkingStatus }
        return snapshot.walkingPlan == nil ? "Plan your next walk" : walkingStatus
    }

    var walkingHomeSubtitle: String {
        if isLoadingPlan { return "Reading your saved walking target" }
        if planLoadError != nil { return "Open Walk to retry loading your plan" }
        if let rest = snapshot.walkingPlan?.restMinutesPerBreak {
            return "\(rest) min planned rest per break · Review plan"
        }
        return snapshot.walkingPlan == nil
            ? "Set the walking target from your clinician"
            : "Clinician-provided target · Review plan"
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
            let displayUnit = reading.map { sample in
                metric == .heartRateBPM
                    ? "bpm · \(sample.recordedAt.formatted(.relative(presentation: .named)))"
                    : "\(unit) · today"
            } ?? unit
            return MetricDisplay(
                id: metric, title: title, symbol: symbol, value: value,
                unit: displayUnit,
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
