import Foundation
import Observation

@MainActor @Observable
final class DispatchDemoViewModel {
    enum Stage: Int, CaseIterable {
        case ready, reviewing, accepted, assigned, enRoute, arrived, cancelled
        var title: String {
            switch self {
            case .ready: "Ready to demonstrate"
            case .reviewing: "Demo request awaiting review"
            case .accepted: "Demo hospital accepted"
            case .assigned: "Demo ambulance assigned"
            case .enRoute: "Demo ambulance en route"
            case .arrived: "Demo ambulance arrived"
            case .cancelled: "Demo cancelled"
            }
        }
    }
    struct Event: Identifiable {
        let id = UUID()
        let stage: Stage
        let date: Date
    }
    private(set) var stage: Stage = .ready
    private(set) var events: [Event] = []
    var isActive: Bool { [.reviewing, .accepted, .assigned, .enRoute].contains(stage) }
    var sampleETAMinutes: Int? {
        switch stage {
        case .assigned: 10
        case .enRoute: 4
        case .arrived: 0
        default: nil
        }
    }
    @ObservationIgnored private var progression: Task<Void, Never>?
    @ObservationIgnored private let pause: () async throws -> Void
    init(pause: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(3)) }) {
        self.pause = pause
    }
    func start() {
        guard !isActive else { return }
        progression?.cancel()
        events = []
        record(.reviewing)
        progression = Task { [weak self] in
            for next in [Stage.accepted, .assigned, .enRoute, .arrived] {
                guard let pause = self?.pause else { return }
                do { try await pause() } catch { return }
                guard !Task.isCancelled, let self, self.isActive else { return }
                self.record(next)
            }
        }
    }
    private func record(_ next: Stage, now: Date = .now) {
        stage = next
        events.append(Event(stage: next, date: now))
    }
    func cancel(now: Date = .now) {
        guard isActive else { return }
        progression?.cancel()
        progression = nil
        record(.cancelled, now: now)
    }
}
