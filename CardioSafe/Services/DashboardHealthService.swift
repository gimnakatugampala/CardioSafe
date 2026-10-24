import Foundation

struct DashboardHealthResult {
    var readings: [HealthMetric: HealthReading]
    var hasQueryErrors: Bool
}

@MainActor
protocol DashboardHealthProviding {
    var hasRequestedAccess: Bool { get }
    var supportsSampleData: Bool { get }
    func seedSampleData() async throws
    func requestAccess() async throws
    func fetchReadings(now: Date) async throws -> DashboardHealthResult
}

enum SimulatorHealthDataError: LocalizedError {
    case unavailable
    case writeAccessRequired
    var errorDescription: String? {
        switch self {
        case .unavailable: "Sample data is available only in a simulator debug build."
        case .writeAccessRequired: "Allow CardioSafe to write all four sample types in Health access. If the sheet no longer opens, change CardioSafe’s permissions in the Health app."
        }
    }
}

extension DashboardHealthProviding {
    var supportsSampleData: Bool { false }
    func seedSampleData() async throws { throw SimulatorHealthDataError.unavailable }
}

#if os(iOS)
import HealthKit

@MainActor
final class HealthKitDashboardService: DashboardHealthProviding {
    private let store = HKHealthStore()
    var hasRequestedAccess: Bool { UserDefaults.standard.bool(forKey: "dashboardHealthRequested") }

    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthServiceError.unavailable }
        try await store.requestAuthorization(toShare: [], read: [HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.heartRate)])
        UserDefaults.standard.set(true, forKey: "dashboardHealthRequested")
    }

    var supportsSampleData: Bool {
        #if DEBUG && targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    func seedSampleData() async throws {
        #if DEBUG && targetEnvironment(simulator)
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthServiceError.unavailable }
        let types: Set<HKSampleType> = [HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning),
                                       HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        try await store.requestAuthorization(toShare: types, read: Set(types.map { $0 as HKObjectType }))
        guard types.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }) else {
            throw SimulatorHealthDataError.writeAccessRequired
        }
        let now = Date.now
        let end = now.addingTimeInterval(-2)
        let dayStart = Calendar.current.startOfDay(for: end)
        let start = max(dayStart, end.addingTimeInterval(-600))
        let dayID = Int(dayStart.timeIntervalSince1970)
        let version = Int(now.timeIntervalSince1970 * 1000)
        let definitions: [(HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.stepCount, .count(), 1200),
            (.distanceWalkingRunning, .meter(), 850),
            (.heartRate, .count().unitDivided(by: .minute()), 82),
            (.activeEnergyBurned, .kilocalorie(), 45)
        ]
        let samples = definitions.map { identifier, unit, value in
            HKQuantitySample(type: HKQuantityType(identifier), quantity: HKQuantity(unit: unit, doubleValue: value),
                             start: identifier == .heartRate ? end : start, end: end,
                             metadata: [HKMetadataKeySyncIdentifier: "CardioSafe.simulator.\(dayID).\(identifier.rawValue)",
                                        HKMetadataKeySyncVersion: version,
                                        "CardioSafeSampleData": "Simulator test sample"])
        }
        try await store.save(samples)
        UserDefaults.standard.set(true, forKey: "dashboardHealthRequested")
        #else
        throw SimulatorHealthDataError.unavailable
        #endif
    }

    func fetchReadings(now: Date) async throws -> DashboardHealthResult {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthServiceError.unavailable }
        let dayStart = Calendar.current.startOfDay(for: now)
        var result = DashboardHealthResult(readings: [:], hasQueryErrors: false)
        for (metric, identifier, unit) in [(HealthMetric.steps, HKQuantityTypeIdentifier.stepCount, HKUnit.count()),
                                          (.walkingDistanceKilometres, .distanceWalkingRunning, HKUnit.meterUnit(with: .kilo))] {
            do {
                if let value = try await total(identifier, unit: unit, from: dayStart, to: now) {
                    result.readings[metric] = HealthReading(value: value, recordedAt: now)
                }
            } catch { result.hasQueryErrors = true }
        }
        do {
            if let sample = try await latestHeartRate(to: now) {
                let value = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                if value.isFinite && value > 0 {
                    result.readings[.heartRateBPM] = HealthReading(value: value, recordedAt: sample.endDate)
                }
            }
        } catch { result.hasQueryErrors = true }
        return result
    }

    private func total(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(identifier),
                                          quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                                          options: .cumulativeSum) { _, result, error in
                if let error = error as? HKError, error.code == .errorNoData {
                    continuation.resume(returning: nil)
                } else if let error { continuation.resume(throwing: error) }
                else {
                    let value = result?.sumQuantity()?.doubleValue(for: unit)
                    continuation.resume(returning: value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
                }
            }
            store.execute(query)
        }
    }

    private func latestHeartRate(to end: Date) async throws -> HKQuantitySample? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKQuantityType(.heartRate),
                                      predicate: HKQuery.predicateForSamples(withStart: end.addingTimeInterval(-86400), end: end, options: [.strictStartDate, .strictEndDate]),
                                      limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKQuantitySample) }
            }
            store.execute(query)
        }
    }
}

enum HealthServiceError: Error { case unavailable }
#endif
