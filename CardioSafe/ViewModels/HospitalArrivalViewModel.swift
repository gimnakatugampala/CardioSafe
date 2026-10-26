import Foundation
import Observation

@MainActor @Observable
final class HospitalArrivalViewModel {
    private(set) var reminder: HospitalArrivalReminder?
    private(set) var isMonitoring = false
    private(set) var isBusy = false
    private(set) var access: ArrivalAccess
    private(set) var errorMessage: String?
    private(set) var message: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let service: any ArrivalMonitoring
    @ObservationIgnored private let notifications: any ArrivalNotifying
    @ObservationIgnored private let store: any ArrivalReminderStoring

    init(service: (any ArrivalMonitoring)? = nil, notifications: (any ArrivalNotifying)? = nil,
         store: (any ArrivalReminderStoring)? = nil) {
        let service = service ?? CoreLocationArrivalService()
        self.service = service
        self.notifications = notifications ?? ArrivalNotificationService()
        self.store = store ?? ArrivalReminderStore()
        access = service.access
        do { reminder = try self.store.load() }
        catch { errorMessage = "The saved arrival reminder couldn’t be restored."; service.stop() }
        service.onEvent = { [weak self] event in self?.handle(event) }
        refresh()
    }

    func refresh() {
        access = service.access
        if let reminder, access.canMonitor {
            if !isMonitoring { service.start(reminder) }
        } else {
            service.stop()
            isMonitoring = false
        }
    }

    func enable(for place: ArrivalPlace) async {
        guard !isBusy, place.isValid else { return }
        errorMessage = nil; message = nil
        access = service.access
        guard access.supported else { errorMessage = "Region monitoring isn’t supported on this device."; return }
        switch access.permission {
        case .notDetermined:
            message = "Allow location, then enable the arrival reminder again."
            service.requestWhenInUse(); return
        case .whenInUse:
            message = "Allow Always location for arrival reminders in the background. If no prompt appears, change it in Settings."
            service.requestAlways(); return
        case .denied:
            errorMessage = "Allow location access in Settings to enable arrival reminders."; return
        case .always: break
        }
        guard access.precise else { errorMessage = "Enable Precise Location in Settings for arrival monitoring."; return }
        isBusy = true
        generation = UUID()
        let expected = generation
        defer { isBusy = false }
        do {
            guard try await notifications.authorize() else { errorMessage = "Allow notifications in Settings to receive arrival reminders."; return }
            guard generation == expected else { return }
            let new = HospitalArrivalReminder(id: UUID(), place: place, hasBeenOutside: false)
            try store.save(new)
            if let old = reminder { notifications.cancel(id: old.regionID) }
            reminder = new; isMonitoring = false
            message = "Starting arrival monitoring…"
            service.start(new)
        } catch { errorMessage = "The arrival reminder couldn’t be enabled. Try again." }
    }

    func cancel() {
        generation = UUID()
        guard let reminder else { return }
        service.stop()
        notifications.cancel(id: reminder.regionID)
        isMonitoring = false
        do {
            try store.save(nil)
            self.reminder = nil
            errorMessage = nil; message = "Arrival reminder stopped."
        } catch { errorMessage = "Monitoring stopped, but the saved reminder couldn’t be removed. Try stopping it again." }
    }

    private func handle(_ event: ArrivalEvent) {
        if case .accessChanged = event {
            if service.access.canMonitor, message?.hasPrefix("Allow") == true { message = nil }
            refresh()
            return
        }
        guard var saved = reminder else { return }
        switch event {
        case .started(let id) where id == saved.regionID:
            isMonitoring = true; message = "Watching the 200 m arrival area."
        case .state(let id, let inside) where id == saved.regionID:
            if inside {
                if saved.hasBeenOutside { trigger(saved) }
                else { message = "Already within the area. The reminder will notify after you leave and return." }
            } else {
                saved.hasBeenOutside = true
                persist(saved)
            }
        case .exited(let id) where id == saved.regionID:
            saved.hasBeenOutside = true
            persist(saved)
        case .entered(let id) where id == saved.regionID:
            if saved.hasBeenOutside { trigger(saved) }
            else { message = "Already within the area. Leave and return to trigger the reminder." }
        case .failed(let id) where id == nil || id == saved.regionID:
            isMonitoring = false
            errorMessage = "iOS couldn’t monitor this arrival area. Check location settings and retry."
        default: break
        }
    }
    private func persist(_ saved: HospitalArrivalReminder) {
        do { try store.save(saved); reminder = saved }
        catch { service.stop(); isMonitoring = false; errorMessage = "The arrival state couldn’t be saved. Enable the reminder again." }
    }
    private func trigger(_ saved: HospitalArrivalReminder) {
        guard !isBusy else { return }
        isBusy = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }
            do {
                try await self.notifications.schedule(id: saved.regionID)
                guard self.reminder?.id == saved.id else { self.notifications.cancel(id: saved.regionID); return }
                try self.store.save(nil)
                self.service.stop(); self.reminder = nil; self.isMonitoring = false
                self.errorMessage = nil; self.message = "Arrival notification scheduled. This one-time reminder is complete."
            } catch {
                guard self.reminder?.id == saved.id else { return }
                self.notifications.cancel(id: saved.regionID)
                self.errorMessage = "The arrival notification couldn’t be scheduled. Check notification settings."
            }
        }
    }
}
