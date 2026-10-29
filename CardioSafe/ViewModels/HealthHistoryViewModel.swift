import Foundation
import Observation
import HealthKit

struct HealthHistoryDay: Identifiable, Equatable {
    let date: Date
    var steps: Double?
    var averageHeartRate: Double?
    var id: Date { date }
}

@MainActor protocol HealthHistoryProviding {
    func fetch(now: Date, calendar: Calendar) async throws -> [HealthHistoryDay]
}

@MainActor final class HealthKitHistoryService: HealthHistoryProviding {
    private let store = HKHealthStore()
    static func days(now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }
    func fetch(now: Date, calendar: Calendar) async throws -> [HealthHistoryDay] {
        guard HKHealthStore.isHealthDataAvailable() else { throw CocoaError(.featureUnsupported) }
        var result: [HealthHistoryDay] = []
        for day in Self.days(now: now, calendar: calendar) {
            try Task.checkCancellation()
            let end = min(calendar.date(byAdding: .day, value: 1, to: day)!, now)
            let steps = try await quantity(.stepCount, unit: .count(), option: .cumulativeSum, start: day, end: end)
            let heart = try await quantity(.heartRate, unit: .count().unitDivided(by: .minute()), option: .discreteAverage, start: day, end: end)
            result.append(HealthHistoryDay(date: day, steps: steps, averageHeartRate: heart))
        }
        return result
    }
    private func quantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, option: HKStatisticsOptions, start: Date, end: Date) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(identifier), quantitySamplePredicate: predicate, options: option) { _, statistics, error in
                if let healthError = error as? HKError, healthError.code == .errorNoData {
                    continuation.resume(returning: nil); return
                }
                if let error { continuation.resume(throwing: error); return }
                let quantity = option == .cumulativeSum ? statistics?.sumQuantity() : statistics?.averageQuantity()
                let value = quantity?.doubleValue(for: unit)
                continuation.resume(returning: value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
            }
            store.execute(query)
        }
    }
}

@MainActor @Observable final class HealthHistoryViewModel {
    private(set) var days: [HealthHistoryDay] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private let service: any HealthHistoryProviding
    init(service: (any HealthHistoryProviding)? = nil) { self.service = service ?? HealthKitHistoryService() }
    func load(now: Date = .now, calendar: Calendar = .current) async {
        guard !isLoading else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let result = try await service.fetch(now: now, calendar: calendar)
            try Task.checkCancellation()
            days = result
        } catch is CancellationError {} catch {
            days = []
            self.error = "Health history couldn’t load. Check Health access and try again."
        }
    }
}
