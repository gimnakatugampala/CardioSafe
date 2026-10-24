#if os(iOS)
import Foundation
import HealthKit
import CoreMotion
import Observation

@MainActor
@Observable
final class WalkingHealthViewModel {
    private(set) var steps: Int?
    private(set) var distanceMetres: Double?
    private(set) var motionUpdatedAt: Date?
    private(set) var heartRate: Double?
    private(set) var heartRateDate: Date?
    private(set) var activeKilocalories: Double?
    private(set) var energyThrough: Date?
    private(set) var motionMessage: String?
    private(set) var healthMessage: String?
    private(set) var isConnecting = false
    private(set) var hasRequestedHealth = UserDefaults.standard.bool(forKey: "walkingHealthRequested")
    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var sessionStart: Date?
    @ObservationIgnored private var generation = UUID()

    func start(at date: Date) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        stop()
        sessionStart = date
        steps = nil; distanceMetres = nil; motionUpdatedAt = nil
        heartRate = nil; heartRateDate = nil; activeKilocalories = nil; energyThrough = nil
        motionMessage = nil; healthMessage = nil
        let token = generation
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: date) { [weak self] data, error in
                Task { @MainActor in
                    guard let self, self.generation == token, self.sessionStart != nil else { return }
                    if let data {
                        self.steps = data.numberOfSteps.intValue
                        self.distanceMetres = data.distance?.doubleValue
                        self.motionUpdatedAt = data.endDate
                        self.motionMessage = nil
                    } else if error != nil {
                        self.motionMessage = "Motion data unavailable. Check Motion & Fitness access in Settings."
                    }
                }
            }
        } else { motionMessage = "Step counting is unavailable on this device." }
        if hasRequestedHealth { beginHealthUpdates() }
    }

    func connectHealth() async {
        guard !isConnecting else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            healthMessage = "Apple Health is unavailable on this device."
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let types: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
            try await healthStore.requestAuthorization(toShare: [], read: types)
            hasRequestedHealth = true
            UserDefaults.standard.set(true, forKey: "walkingHealthRequested")
            if sessionStart != nil { beginHealthUpdates() }
        } catch { healthMessage = "Apple Health could not be opened. Please try again." }
    }

    func snapshot(at date: Date) -> WalkingHealthSnapshot {
        WalkingHealthSnapshot(capturedAt: date, steps: steps,
                              motionDistanceMetres: distanceMetres, motionUpdatedAt: motionUpdatedAt,
                              lastHeartRateBPM: heartRate, heartRateRecordedAt: heartRateDate,
                              activeKilocalories: activeKilocalories, energyThrough: energyThrough)
    }

    func stop() {
        generation = UUID()
        pedometer.stopUpdates()
        refreshTask?.cancel()
        refreshTask = nil
        sessionStart = nil
    }

    private func beginHealthUpdates() {
        refreshTask?.cancel()
        let token = generation
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == token, let start = self.sessionStart else { return }
                await self.refreshHealth(since: start, token: token)
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
    }

    private func refreshHealth(since start: Date, token: UUID) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthMessage = "Apple Health is unavailable on this device."
            return
        }
        do {
            let sample = try await latestHeartRate(since: start.addingTimeInterval(-900))
            guard generation == token, !Task.isCancelled else { return }
            if let sample {
                let value = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                heartRate = value.isFinite && value > 0 ? value : nil
                heartRateDate = heartRate == nil ? nil : sample.endDate
            } else { heartRate = nil; heartRateDate = nil }
            let energyEnd = Date.now
            let energy = try await sessionEnergy(since: start, through: energyEnd)
            guard generation == token, !Task.isCancelled else { return }
            activeKilocalories = energy
            energyThrough = energy == nil ? nil : energyEnd
            healthMessage = heartRate == nil && energy == nil
                ? "No readable Health samples yet. Check access and your connected device." : nil
        } catch {
            guard generation == token else { return }
            healthMessage = "Health readings could not be refreshed. Showing the last available data."
        }
    }

    private func latestHeartRate(since start: Date) async throws -> HKQuantitySample? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKQuantityType(.heartRate),
                                      predicate: HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate),
                                      limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKQuantitySample) }
            }
            healthStore.execute(query)
        }
    }

    private func sessionEnergy(since start: Date, through end: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(.activeEnergyBurned),
                                          quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                                          options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: .kilocalorie())) }
            }
            healthStore.execute(query)
        }
    }
}
#endif
