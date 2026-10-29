import Foundation
import Observation

@MainActor @Observable
final class DispatchDemoViewModel {
    enum Stage: Int, CaseIterable {
        case ready, finding, reviewing, accepted, assigned, enRoute, arrived, transporting, hospitalArrived, completed, cancelled, failed
        var title: String {
            switch self {
            case .ready: "Ready"
            case .finding: "Checking nearby hospitals"
            case .failed: "Hospital check unavailable"
            case .reviewing: "Request awaiting review"
            case .accepted: "Hospital accepted"
            case .assigned: "Ambulance assigned"
            case .enRoute: "Ambulance en route"
            case .arrived: "Ambulance arrived"
            case .transporting: "On the way to hospital"
            case .hospitalArrived: "Arrived at hospital"
            case .completed: "Completed"
            case .cancelled: "Request cancelled"
            }
        }
    }
    struct Event: Identifiable {
        let id = UUID()
        let stage: Stage
        let date: Date
    }
    private(set) var stage: Stage = .ready
    private(set) var pickedUpAt: Date?
    private(set) var assignedAt: Date?
    private(set) var destination: DispatchDestination?
    private(set) var errorMessage: String?
    @ObservationIgnored private let selector: any DispatchHospitalSelecting
    private(set) var events: [Event] = []
    var isActive: Bool { [.finding, .reviewing, .accepted, .assigned, .enRoute, .arrived, .transporting, .hospitalArrived].contains(stage) }
    var sampleETAMinutes: Int? { nil }
    @ObservationIgnored private var progression: Task<Void, Never>?
    @ObservationIgnored private let requests: any SOSRequestServicing
    private(set) var isCancelling = false
    private var cancellationRequested = false
    private(set) var isRestoring = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var boundOwnerID: String?
    init(selector: (any DispatchHospitalSelecting)? = nil, requests: (any SOSRequestServicing)? = nil) {
        self.requests = requests ?? SOSRequestService()
        self.selector = selector ?? DispatchHospitalService()
    }
    /// Account changes discard in-memory details; the journal remains isolated per account.
    func restoreForAccount(ownerID: String?) async -> Bool {
        guard ownerID != boundOwnerID else { return isActive }
        generation = UUID()
        let expected = generation
        boundOwnerID = ownerID
        progression?.cancel(); selector.cancel(); requests.stop()
        destination = nil; assignedAt = nil; pickedUpAt = nil; errorMessage = nil; events = []
        isCancelling = false; cancellationRequested = false; stage = .ready
        guard ownerID != nil else { isRestoring = false; return false }
        isRestoring = true
        defer { if generation == expected { isRestoring = false } }
        record(.finding)
        do {
            let restored = try await requests.restore()
            guard generation == expected, !Task.isCancelled else { return false }
            guard let restored else { stage = .ready; events = []; return false }
            guard restored.saved.ownerID == ownerID else { throw DispatchSelectionError.unavailable }
            restore(restored)
            return restored.isActive
        } catch {
            guard generation == expected, !Task.isCancelled else { return false }
            errorMessage = "Your previous SOS couldn’t be checked. Reconnect and retry; a new request has not been created."
            record(.failed)
            return true
        }
    }

    func start() {
        guard !isRestoring else { return }
        guard !isActive else { if stage != .finding { observeRequest() }; return }
        progression?.cancel()
        requests.stop()
        generation = UUID()
        let expected = generation
        cancellationRequested = false
        events = []; destination = nil; assignedAt = nil; pickedUpAt = nil; errorMessage = nil
        isRestoring = true
        record(.finding)
        progression = Task { [weak self] in
            guard let self else { return }
            do {
                defer { if self.generation == expected { self.isRestoring = false } }
                // Always reconcile a saved request before allowing a new submission.
                if let restored = try await self.requests.restore() {
                    guard !Task.isCancelled, self.generation == expected else { return }
                    if restored.isActive {
                        self.restore(restored)
                        return
                    }
                }
            } catch {
                guard !Task.isCancelled, self.generation == expected else { return }
                self.errorMessage = "Your previous SOS couldn’t be checked. Reconnect and retry; a new request has not been created."
                self.record(.failed)
                return
            }
            do {
                let selected = try await self.selector.selectHospital()
                guard !Task.isCancelled, self.generation == expected, self.stage == .finding else { return }
                self.destination = selected
                try await self.requests.create(destination: selected)
                guard self.generation == expected, !Task.isCancelled else { return }
                if self.cancellationRequested {
                    await self.finishCancellation()
                    return
                }
                self.record(.reviewing)
                self.observeRequest()
            } catch {
                guard !Task.isCancelled, self.generation == expected, self.isActive else { return }
                self.errorMessage = (error as? DispatchSelectionError)?.errorDescription ?? "SOS submission could not be confirmed. Retry to reconnect to the saved request."
                self.record(.failed)
            }
        }
    }

    private func restore(_ restored: RestoredSOS) {
        destination = restored.saved.destination
        assignedAt = restored.assignedAt
        pickedUpAt = restored.pickedUpAt
        apply(status: restored.status)
        if restored.isActive { observeRequest() }
    }

    private func apply(status: String) {
        let next: Stage
        switch status {
        case "pending": next = .reviewing
        case "accepted": next = .accepted
        case "assigned":
            assignedAt = requests.assignedAt ?? assignedAt
            next = .assigned
        case "patient_arrived": next = .arrived
        case "transporting":
            pickedUpAt = requests.pickedUpAt ?? pickedUpAt
            next = .transporting
        case "hospital_arrived": next = .hospitalArrived
        case "completed": next = .completed
        case "cancelled": next = .cancelled
        default: return
        }
        errorMessage = next == .completed ? requests.summaryWarning : nil
        if stage != next { record(next) }
    }

    private func observeRequest() {
        let expected = generation
        requests.observe { [weak self] result in
            guard let self, self.generation == expected else { return }
            switch result {
            case .success(let status): self.apply(status: status)
            case .failure:
                self.errorMessage = "Connection interrupted. The saved SOS may still be active. Close and reopen this screen to reconnect."
            }
        }
    }
    private func record(_ next: Stage, now: Date = .now) {
        stage = next
        events.append(Event(stage: next, date: now))
    }
    func cancel(now: Date = .now) {
        guard isActive, ![.transporting, .hospitalArrived].contains(stage), !isCancelling, !isRestoring else { return }
        cancellationRequested = true
        if stage == .finding && destination == nil {
            progression?.cancel()
            selector.cancel()
            requests.stop()
            record(.cancelled, now: now)
        } else if stage != .finding {
            Task { await finishCancellation() }
        }
    }
    private func finishCancellation() async {
        isCancelling = true
        defer { isCancelling = false }
        do {
            try await requests.cancel()
            requests.stop()
            if stage != .cancelled { record(.cancelled) }
        } catch {
            cancellationRequested = false
            errorMessage = "Cancellation could not be confirmed. Check your connection and try again."
        }
    }
}
