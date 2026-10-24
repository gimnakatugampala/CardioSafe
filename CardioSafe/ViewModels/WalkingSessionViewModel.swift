import Foundation
import Observation

@MainActor
@Observable
final class WalkingSessionViewModel {
    private(set) var phase: WalkingSessionPhase = .ready
    private(set) var session: WalkingSession?
    private(set) var completedSessions: [WalkingSession] = []
    @ObservationIgnored private let clock: any WalkingSessionClock
    @ObservationIgnored private var intervalStart: WalkingSessionInstant?

    private(set) var isLoadingHistory = false
    private(set) var historyError: String?
    private(set) var saveError: String?
    private(set) var isSaving = false
    private(set) var savedSessionIDs: Set<UUID> = []
    @ObservationIgnored private var store: (any WalkingSessionStoring)?
    @ObservationIgnored private var ownerID = "local-device"

    convenience init(store: any WalkingSessionStoring, ownerID: String) {
        self.init()
        self.store = store
        self.ownerID = ownerID
    }

    func loadHistory() async {
        guard let store, !isLoadingHistory else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let records = try await store.loadSessions(for: ownerID)
            savedSessionIDs.formUnion(records.map(\.id))
            let local = completedSessions.filter { item in !records.contains { $0.id == item.id } }
            completedSessions = (records + local).sorted { $0.startedAt > $1.startedAt }
            historyError = nil
        } catch { historyError = "Your walking history could not be loaded. Please retry." }
    }

    func savePendingSessions() async {
        guard let store, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            while let item = completedSessions.first(where: { !savedSessionIDs.contains($0.id) }) {
                try await store.saveSession(item, for: ownerID)
                savedSessionIDs.insert(item.id)
            }
            saveError = nil
        } catch { saveError = "This walk could not be saved. Retry before closing the app." }
    }

    init(clock: any WalkingSessionClock) { self.clock = clock }
    convenience init() { self.init(clock: SystemWalkingSessionClock()) }

    convenience init(completedSession: WalkingSession, saved: Bool) {
        self.init()
        session = completedSession
        phase = .finished
        if saved { savedSessionIDs.insert(completedSession.id) }
    }

    func summaryModel(for item: WalkingSession) -> WalkingSessionViewModel {
        let model = WalkingSessionViewModel(completedSession: item, saved: savedSessionIDs.contains(item.id))
        model.store = store
        model.ownerID = ownerID
        model.completedSessions = [item]
        if !savedSessionIDs.contains(item.id) { model.saveError = "This walk has not been saved. Please retry." }
        return model
    }

    var isActive: Bool { phase == .walking || phase == .resting }
    var hasSummary: Bool { phase == .finished && session != nil }

    @discardableResult
    func start(plan: WalkingPlan? = nil) -> Bool {
        guard !isActive else { return false }
        if let plan {
            guard plan.walkingMinutes > 0, plan.walkingMinutes <= Int.max / 60 else { return false }
            if let rest = plan.restMinutesPerBreak, rest <= 0 || rest > Int.max / 60 { return false }
        }
        let now = clock.read()
        session = WalkingSession(id: UUID(), plan: plan, startedAt: now.date, endedAt: nil, intervals: [])
        intervalStart = now
        phase = .walking
        return true
    }

    @discardableResult
    func beginRest() -> Bool {
        guard phase == .walking else { return false }
        let now = clock.read()
        closeInterval(at: now, kind: .walking)
        intervalStart = now
        phase = .resting
        return true
    }

    @discardableResult
    func resume() -> Bool {
        guard phase == .resting else { return false }
        let now = clock.read()
        closeInterval(at: now, kind: .resting)
        intervalStart = now
        phase = .walking
        return true
    }

    @discardableResult
    func finish() -> Bool {
        guard isActive else { return false }
        let now = clock.read()
        closeInterval(at: now, kind: phase == .walking ? .walking : .resting)
        session?.endedAt = now.date
        intervalStart = nil
        phase = .finished
        if let session { completedSessions.insert(session, at: 0) }
        Task { await savePendingSessions() }
        return true
    }

    func timing() -> WalkingSessionTiming {
        let openSeconds = intervalStart.map { max(0, clock.read().monotonicSeconds - $0.monotonicSeconds) } ?? 0
        let walking = (session?.walkingSeconds ?? 0) + (phase == .walking ? openSeconds : 0)
        let resting = (session?.restingSeconds ?? 0) + (phase == .resting ? openSeconds : 0)
        return WalkingSessionTiming(
            walkingSeconds: walking,
            restingSeconds: resting,
            currentRestSeconds: phase == .resting ? openSeconds : 0,
            targetSeconds: Double(session?.plan?.walkingMinutes ?? 0) * 60
        )
    }

    func durationText(_ seconds: TimeInterval) -> String {
        let seconds = Int(max(0, seconds).rounded(.down))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }

    var homeTitle: String? {
        switch phase {
        case .walking: "Walking session in progress"
        case .resting: "Rest break in progress"
        case .finished: "Your latest walk summary"
        case .ready: nil
        }
    }

    var homeSubtitle: String? {
        switch phase {
        case .walking: "Open Walk to return to your session"
        case .resting: "Open Walk to resume when you choose"
        case .finished: "Open Walk to view walking and rest totals"
        case .ready: nil
        }
    }

    private func closeInterval(at now: WalkingSessionInstant, kind: WalkingSessionInterval.Kind) {
        guard let intervalStart else { return }
        session?.intervals.append(WalkingSessionInterval(
            kind: kind,
            startedAt: intervalStart.date,
            endedAt: now.date,
            durationSeconds: max(0, now.monotonicSeconds - intervalStart.monotonicSeconds)
        ))
    }
}
