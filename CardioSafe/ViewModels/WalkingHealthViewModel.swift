#if os(iOS)
import Foundation
import HealthKit
import CoreMotion
import Observation

@MainActor
@Observable
final class WalkingHealthViewModel {
    private(set) var isSimulatorFeedRunning = false
    var highHeartRateTest = false
    private(set) var isStartingSimulatorFeed = false
    private(set) var usesSimulatorSamples = false
    var isResting = false
    @ObservationIgnored private var simulatorTask: Task<Void, Never>?
    @ObservationIgnored private var simulatorSessionID = UUID().uuidString
    private var simulatorTick = 0

    var supportsSimulatorFeed: Bool {
        #if DEBUG && targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

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
        simulatorSessionID = UUID().uuidString
        simulatorTick = 0
        highHeartRateTest = false
        usesSimulatorSamples = false
        isResting = false
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

    func startSimulatorFeed() async {
        #if DEBUG && targetEnvironment(simulator)
        guard sessionStart != nil, !isSimulatorFeedRunning, !isStartingSimulatorFeed else { return }
        isStartingSimulatorFeed = true
        defer { isStartingSimulatorFeed = false }
        let token = generation
        do {
            let types: Set<HKSampleType> = [HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning),
                                           HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
            try await healthStore.requestAuthorization(toShare: types, read: Set(types.map { $0 as HKObjectType }))
            guard generation == token, sessionStart != nil else { return }
            guard types.allSatisfy({ healthStore.authorizationStatus(for: $0) == .sharingAuthorized }) else {
                throw SimulatorHealthDataError.writeAccessRequired
            }
            refreshTask?.cancel()
            pedometer.stopUpdates()
            usesSimulatorSamples = true
            hasRequestedHealth = true
            UserDefaults.standard.set(true, forKey: "walkingHealthRequested")
            motionMessage = nil
            isSimulatorFeedRunning = true
            simulatorTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.generation == token, let start = self.sessionStart else { return }
                    do {
                        try await self.writeSimulatorTick()
                        guard self.generation == token, !Task.isCancelled else { return }
                        await self.refreshHealth(since: start, token: token)
                        try await Task.sleep(for: .seconds(10))
                    } catch {
                        guard self.generation == token else { return }
                        if !Task.isCancelled { self.healthMessage = "Test feed stopped: \(error.localizedDescription)" }
                        self.isSimulatorFeedRunning = false
                        return
                    }
                }
            }
        } catch { healthMessage = error.localizedDescription }
        #endif
    }

    func stopSimulatorFeed() {
        simulatorTask?.cancel()
        simulatorTask = nil
        isSimulatorFeedRunning = false
    }

    #if DEBUG && targetEnvironment(simulator)
    private func writeSimulatorTick() async throws {
        guard let start = sessionStart else { return }
        let end = Date.now
        simulatorTick += 1
        let identifier = "CardioSafe.walksim.\(simulatorSessionID).\(simulatorTick)"
        let definitions: [(HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.stepCount, .count(), isResting ? 0 : 12),
            (.distanceWalkingRunning, .meter(), isResting ? 0 : 8.4),
            (.heartRate, .count().unitDivided(by: .minute()), highHeartRateTest ? 160 : (isResting ? 78 : Double(82 + (simulatorTick % 5) * 2))),
            (.activeEnergyBurned, .kilocalorie(), isResting ? 0 : 0.7)
        ]
        let samples = definitions.map { type, unit, value in
            HKQuantitySample(type: HKQuantityType(type), quantity: HKQuantity(unit: unit, doubleValue: value),
                             start: max(start, end.addingTimeInterval(-1)), end: end,
                             metadata: ["CardioSafeSimulatorSession": simulatorSessionID,
                                        "CardioSafeSampleData": "Simulated walking sensor feed",
                                        HKMetadataKeySyncIdentifier: "\(identifier).\(type.rawValue)", HKMetadataKeySyncVersion: 1])
        }
        try await healthStore.save(samples)
    }
    #endif

    private func sessionPredicate(since start: Date, through end: Date?) -> NSPredicate {
        let dates = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        if usesSimulatorSamples {
            return NSCompoundPredicate(andPredicateWithSubpredicates: [dates,
                HKQuery.predicateForObjects(withMetadataKey: "CardioSafeSimulatorSession", allowedValues: [simulatorSessionID])])
        }
        return dates
    }

    func snapshot(at date: Date) -> WalkingHealthSnapshot {
        WalkingHealthSnapshot(capturedAt: date, steps: steps,
                              motionDistanceMetres: distanceMetres, motionUpdatedAt: motionUpdatedAt,
                              lastHeartRateBPM: heartRate, heartRateRecordedAt: heartRateDate,
                              activeKilocalories: activeKilocalories, energyThrough: energyThrough,
                              isSimulatorTestData: usesSimulatorSamples)
    }

    func stop() {
        generation = UUID()
        stopSimulatorFeed()
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
            if usesSimulatorSamples {
                let end = Date.now
                let count = try await simulatorTotal(.stepCount, unit: .count(), since: start, through: end)
                let distance = try await simulatorTotal(.distanceWalkingRunning, unit: .meter(), since: start, through: end)
                guard generation == token, !Task.isCancelled else { return }
                steps = count.map { Int($0) }
                distanceMetres = distance
                motionUpdatedAt = count == nil && distance == nil ? nil : end
            }
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
                                      predicate: sessionPredicate(since: start, through: nil),
                                      limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKQuantitySample) }
            }
            healthStore.execute(query)
        }
    }

    private func simulatorTotal(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, since start: Date, through end: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(identifier),
                                          quantitySamplePredicate: sessionPredicate(since: start, through: end),
                                          options: .cumulativeSum) { _, result, error in
                if let error = error as? HKError, error.code == .errorNoData { continuation.resume(returning: nil) }
                else if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit)) }
            }
            healthStore.execute(query)
        }
    }

    private func sessionEnergy(since start: Date, through end: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(.activeEnergyBurned),
                                          quantitySamplePredicate: sessionPredicate(since: start, through: end),
                                          options: .cumulativeSum) { _, result, error in
                if let error = error as? HKError, error.code == .errorNoData { continuation.resume(returning: nil) }
                else if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: .kilocalorie())) }
            }
            healthStore.execute(query)
        }
    }
}
#endif
