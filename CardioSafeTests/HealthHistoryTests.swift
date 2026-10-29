import Foundation
import Testing
@testable import CardioSafe

@MainActor struct HealthHistoryTests {
    @MainActor final class Service: HealthHistoryProviding {
        var fails = false
        var days: [HealthHistoryDay] = []
        func fetch(now: Date, calendar: Calendar) async throws -> [HealthHistoryDay] {
            if fails { throw CocoaError(.fileReadUnknown) }
            return days
        }
    }
    @Test func calendarWindowIncludesTodayAndHandlesDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12)))
        let days = HealthKitHistoryService.days(now: now, calendar: calendar)
        #expect(days.count == 7 && Set(days).count == 7)
        #expect(days.last == calendar.startOfDay(for: now))
        #expect(calendar.dateComponents([.day], from: days[0], to: days[6]).day == 6)
        #expect(zip(days, days.dropFirst()).contains { $1.timeIntervalSince($0) == 25 * 3600 })
    }
    @Test func missingDataIsNotInventedAsZeroAndFailedRefreshClearsStaleChart() async {
        let service = Service(), date = Date.now
        service.days = [.init(date: date, steps: nil, averageHeartRate: nil),
                        .init(date: date.addingTimeInterval(86400), steps: 0, averageHeartRate: 82)]
        let model = HealthHistoryViewModel(service: service)
        await model.load()
        #expect(model.days[0].steps == nil && model.days[0].averageHeartRate == nil)
        #expect(model.days[1].steps == 0 && model.days[1].averageHeartRate == 82)
        service.fails = true; await model.load()
        #expect(model.error != nil && model.days.isEmpty && !model.isLoading)
        service.fails = false; await model.load()
        #expect(model.error == nil && model.days.count == 2)
    }
}
