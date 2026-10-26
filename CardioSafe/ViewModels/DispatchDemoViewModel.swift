import Foundation
import Observation

@MainActor @Observable
final class DispatchDemoViewModel {
    enum Stage: Int, CaseIterable {
        case ready, finding, reviewing, accepted, assigned, enRoute, arrived, completed, cancelled, failed
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
    private(set) var assignedAt: Date?
    private(set) var destination: DispatchDestination?
    private(set) var errorMessage: String?
    @ObservationIgnored private let selector: any DispatchHospitalSelecting
    private(set) var events: [Event] = []
    var isActive: Bool { [.finding, .reviewing, .accepted, .assigned, .enRoute].contains(stage) }
    var sampleETAMinutes: Int? { nil }
    @ObservationIgnored private var progression: Task<Void, Never>?
    @ObservationIgnored private let requests: any SOSRequestServicing
    private(set) var isCancelling = false
    private var cancellationRequested = false
    init(selector: (any DispatchHospitalSelecting)? = nil, requests: (any SOSRequestServicing)? = nil) {
        self.requests = requests ?? SOSRequestService()
        self.selector = selector ?? DispatchHospitalService()
    }
    func start() {
        guard !isActive else { if stage != .finding { observeRequest() }; return }
        progression?.cancel()
        requests.stop()
        cancellationRequested = false
        events = []; destination = nil; assignedAt = nil; errorMessage = nil
        record(.finding)
        progression = Task { [weak self] in
            guard let selector = self?.selector else { return }
            do {
                let selected = try await selector.selectHospital()
                guard !Task.isCancelled, let self, self.stage == .finding else { return }
                self.destination = selected
                try await self.requests.create(hospitalID: selected.hospitalID)
                if self.cancellationRequested {
                    await self.finishCancellation()
                    return
                }
                self.record(.reviewing)
                self.observeRequest()
            } catch {
                guard !Task.isCancelled, let self, self.isActive else { return }
                self.errorMessage = (error as? DispatchSelectionError)?.errorDescription ?? "Hospital information is unavailable. No request was sent."
                self.record(.failed)
                return
            }

        }
    }
    private func observeRequest() {
        requests.observe { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let status):
                        self.errorMessage = nil
                        let next: Stage
                        switch status {
                        case "pending": next = .reviewing
                        case "accepted": next = .accepted
                        case "assigned":
                            self.assignedAt = self.requests.assignedAt
                            next = .assigned
                        case "completed": next = .completed
                        case "cancelled": next = .cancelled
                        default: return
                        }
                        if self.stage != next { self.record(next) }
                    case .failure:
                        self.errorMessage = "Connection interrupted. The request may still be open. Close and reopen this screen to reconnect."
                    }
                }
    }
    private func record(_ next: Stage, now: Date = .now) {
        stage = next
        events.append(Event(stage: next, date: now))
    }
    func cancel(now: Date = .now) {
        guard isActive, !isCancelling else { return }
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
