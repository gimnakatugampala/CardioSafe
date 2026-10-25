import Foundation
import Observation

@MainActor @Observable
final class WalkingReminderViewModel {
    var hour: Int
    var minute: Int
    private(set) var isEnabled = false
    private(set) var isBusy = false
    private(set) var authorization: ReminderAuthorization = .notDetermined
    private(set) var message: String?
    private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let service: any WalkingReminderServicing
    init(defaults: UserDefaults = .standard, service: (any WalkingReminderServicing)? = nil) {
        self.defaults = defaults
        self.service = service ?? WalkingReminderService()
        let storedHour = defaults.object(forKey: "walkingReminderHour") as? Int ?? 9
        let storedMinute = defaults.integer(forKey: "walkingReminderMinute")
        hour = (0...23).contains(storedHour) ? storedHour : 9
        minute = (0...59).contains(storedMinute) ? storedMinute : 0
    }
    func load() async {
        guard !isBusy else { return }
        isBusy = true
        authorization = await service.authorization()
        let scheduled = await service.hasDailyReminder()
        isEnabled = authorization == .allowed && scheduled
        isBusy = false
    }
    func setEnabled(_ enabled: Bool) async {
        guard !isBusy else { return }
        isBusy = true; message = nil; errorMessage = nil
        defer { isBusy = false }
        if !enabled {
            service.cancelDaily(); isEnabled = false
            message = "Daily walking reminder turned off."
            return
        }
        guard await ensurePermission() else { return }
        do {
            try await service.scheduleDaily(hour: hour, minute: minute)
            persistTime(); isEnabled = true
            message = "Daily reminder scheduled for \(timeText)."
        } catch { errorMessage = "The reminder couldn’t be scheduled. Please retry." }
    }
    func saveTime() async {
        guard !isBusy else { return }
        if isEnabled { await setEnabled(true) }
        else { persistTime(); message = "Reminder time saved. Turn on Daily reminder to schedule it."; errorMessage = nil }
    }
    func sendTest() async {
        guard !isBusy else { return }
        isBusy = true; message = nil; errorMessage = nil
        defer { isBusy = false }
        guard await ensurePermission() else { return }
        do {
            try await service.scheduleTest()
            message = "Test scheduled for five seconds from now. Focus or notification settings may silence the banner."
        } catch { errorMessage = "The test notification couldn’t be scheduled. Please retry." }
    }
    private func ensurePermission() async -> Bool {
        authorization = await service.authorization()
        do {
            if authorization == .notDetermined {
                _ = try await service.requestPermission()
                authorization = await service.authorization()
            }
            guard authorization == .allowed else {
                errorMessage = "Notifications are off. Enable them in iOS Settings → Notifications → CardioSafe."
                return false
            }
            return true
        } catch { errorMessage = "Notification permission couldn’t be checked. Please retry."; return false }
    }
    private func persistTime() {
        defaults.set(hour, forKey: "walkingReminderHour")
        defaults.set(minute, forKey: "walkingReminderMinute")
    }
    var timeText: String {
        (Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now)
            .formatted(date: .omitted, time: .shortened)
    }
}
