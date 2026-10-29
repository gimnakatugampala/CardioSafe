import Foundation
import CoreLocation
import MapKit
import Observation

@MainActor
@Observable
final class WalkingSessionViewModel {
    let destinationModel = WalkingDestinationViewModel()
    let automaticSOS = AutomaticSOSViewModel()
    let restStop = WalkingRestStopViewModel()
    #if os(iOS)
    let locationModel = WalkingLocationViewModel(backgroundUpdates: true)
    let healthModel = WalkingHealthViewModel()
    #endif
    private(set) var needsRecoveryDecision = false
    private(set) var recoveryCheckpoint: Date?
    private(set) var recoveryError: String?
    @ObservationIgnored private var recoveryStore: (any WalkingRecoveryStoring)?
    @ObservationIgnored private var checkpointTask: Task<Void, Never>?
    @ObservationIgnored private var tracksSensors = false
    private(set) var phase: WalkingSessionPhase = .ready
    private(set) var session: WalkingSession?
    private(set) var completedSessions: [WalkingSession] = []
    var returnToStartPlace: MapPlace? {
        guard isActive, let point = session?.routeSegments?.first(where: { !$0.points.isEmpty })?.points.first,
              CLLocationCoordinate2DIsValid(point.coordinate), point.accuracyMetres.isFinite,
              (0...50).contains(point.accuracyMetres) else { return nil }
        let item = MKMapItem(location: CLLocation(latitude: point.latitude, longitude: point.longitude), address: nil)
        item.name = "Walk starting point"
        return MapPlace(item: item, category: .parks)
    }

    @ObservationIgnored private let clock: any WalkingSessionClock
    @ObservationIgnored private var needsRouteSegment = true
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
        self.recoveryStore = FileWalkingRecoveryStore()
        self.tracksSensors = true
        self.ownerID = ownerID
    }

    func useAccount(_ newOwner: String) async {
        guard ownerID != newOwner else {
            if session == nil { await loadHistory(); restoreUnfinishedWalk() }
            return
        }
        if isActive { _ = finish() }
        while isSaving || isLoadingHistory { await Task.yield() }
        await savePendingSessions()
        ownerID = newOwner
        destinationModel.endWalk()
        automaticSOS.setEnabled(false)
        restStop.clear()
        phase = .ready; session = nil; intervalStart = nil
        needsRecoveryDecision = false; recoveryCheckpoint = nil; recoveryError = nil
        completedSessions = []; savedSessionIDs = []; saveError = nil; historyError = nil
        await loadHistory()
        restoreUnfinishedWalk()
    }
    func loadHistory() async {
        guard let store, !isLoadingHistory else { return }
        isLoadingHistory = true
        let expectedOwner = ownerID
        defer { isLoadingHistory = false }
        do {
            let records = try await store.loadSessions(for: expectedOwner)
            guard ownerID == expectedOwner else { return }
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
                do { try recoveryStore?.clear(owner: ownerID, sessionID: item.id) }
                catch { recoveryError = "The saved walk’s recovery copy could not be cleared. It will be checked on restart." }
            }
            saveError = nil
        } catch { saveError = "This walk could not be saved. Retry before closing the app." }
    }

    init(clock: any WalkingSessionClock, recoveryStore: (any WalkingRecoveryStoring)? = nil, sessionStore: (any WalkingSessionStoring)? = nil, ownerID: String = "local-device") {
        self.clock = clock; self.recoveryStore = recoveryStore; self.store = sessionStore; self.ownerID = ownerID
    }
    convenience init() { self.init(clock: SystemWalkingSessionClock()) }

    convenience init(completedSession: WalkingSession, saved: Bool) {
        self.init()
        session = completedSession
        phase = .finished
        restStop.isWalking = false
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
        guard !isActive, !needsRecoveryDecision else { return false }
        if let plan {
            guard plan.walkingMinutes > 0, plan.walkingMinutes <= Int.max / 60 else { return false }
            if let rest = plan.restMinutesPerBreak, rest <= 0 || rest > Int.max / 60 { return false }
        }
        destinationModel.endWalk()
        automaticSOS.setEnabled(false)
        restStop.clear()
        let now = clock.read()
        session = WalkingSession(id: UUID(), plan: plan, startedAt: now.date, endedAt: nil, intervals: [])
        intervalStart = now
        needsRouteSegment = true
        phase = .walking
        restStop.isWalking = true
        #if os(iOS)
        if tracksSensors {
            locationModel.onLocation = { [weak self] in self?.recordLocation($0) }
            locationModel.start()
            healthModel.start(at: now.date)
        }
        #endif
        checkpoint()
        beginCheckpoints()
        return true
    }

    @discardableResult
    func beginRest() -> Bool {
        guard phase == .walking else { return false }
        let now = clock.read()
        closeInterval(at: now, kind: .walking)
        intervalStart = now
        needsRouteSegment = true
        phase = .resting
        restStop.isWalking = false
        #if os(iOS)
        healthModel.isResting = true
        #endif
        checkpoint()
        return true
    }

    @discardableResult
    func resume() -> Bool {
        guard phase == .resting else { return false }
        let now = clock.read()
        closeInterval(at: now, kind: .resting)
        intervalStart = now
        needsRouteSegment = true
        phase = .walking
        restStop.isWalking = true
        #if os(iOS)
        healthModel.isResting = false
        #endif
        checkpoint()
        return true
    }

    @discardableResult
    func finish() -> Bool {
        guard isActive else { return false }
        let now = clock.read()
        checkpointTask?.cancel(); checkpointTask = nil
        destinationModel.endWalk()
        automaticSOS.setEnabled(false)
        restStop.clear()
        closeInterval(at: now, kind: phase == .walking ? .walking : .resting)
        session?.endedAt = now.date
        intervalStart = nil
        phase = .finished
        restStop.isWalking = false
        #if os(iOS)
        if tracksSensors { session?.healthSnapshot = healthModel.snapshot(at: now.date) }
        locationModel.stop()
        locationModel.onLocation = nil
        healthModel.stop()
        #endif
        persistFinishedRecovery(at: now.date)
        if let session { completedSessions.insert(session, at: 0) }
        Task { await savePendingSessions() }
        return true
    }

    // A checkpoint closes the current interval only in the recovery copy.
    func checkpoint() {
        guard isActive, var copy = session, let intervalStart else { return }
        let now = clock.read()
        copy.intervals.append(WalkingSessionInterval(kind: phase == .walking ? .walking : .resting,
            startedAt: intervalStart.date, endedAt: now.date,
            durationSeconds: max(0, now.monotonicSeconds - intervalStart.monotonicSeconds)))
        #if os(iOS)
        if tracksSensors { copy.healthSnapshot = healthModel.snapshot(at: now.date) }
        #endif
        do {
            try recoveryStore?.save(WalkingRecoveryRecord(session: copy, checkpointAt: now.date), owner: ownerID)
            recoveryError = nil
        } catch { recoveryError = "Walk recovery could not be backed up. Finish and save before closing the app." }
    }
    private func beginCheckpoints() {
        checkpointTask?.cancel()
        guard recoveryStore != nil else { return }
        checkpointTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.isActive else { return }
                self.checkpoint()
            }
        }
    }
    private func restoreUnfinishedWalk() {
        guard session == nil else { return }
        do {
            guard let record = try recoveryStore?.load(owner: ownerID) else { return }
            if savedSessionIDs.contains(record.session.id) {
                try recoveryStore?.clear(owner: ownerID, sessionID: record.session.id)
                return
            }
            session = record.session
            recoveryCheckpoint = record.checkpointAt
            needsRouteSegment = true; intervalStart = nil
            if record.session.endedAt != nil {
                phase = .finished
        restStop.isWalking = false
                completedSessions.insert(record.session, at: 0)
                Task { await savePendingSessions() }
            } else {
                phase = .ready
                needsRecoveryDecision = true
            }
        } catch { recoveryError = "An unfinished walk could not be restored. Its recovery file has been kept." }
    }
    @discardableResult func resumeRecoveredWalk() -> Bool {
        guard needsRecoveryDecision, let savedAt = recoveryCheckpoint else { return false }
        let now = clock.read()
        let gaps = (session?.untrackedGaps ?? []) + [WalkingRecoveryGap(from: savedAt, to: max(savedAt, now.date))]
        session?.untrackedGaps = gaps
        needsRecoveryDecision = false; phase = .walking
        restStop.isWalking = true; intervalStart = now; needsRouteSegment = true
        #if os(iOS)
        if tracksSensors {
            locationModel.onLocation = { [weak self] in self?.recordLocation($0) }
            locationModel.start(); healthModel.start(at: now.date)
        }
        #endif
        checkpoint(); beginCheckpoints()
        return true
    }
    @discardableResult func finishRecoveredWalk() -> Bool {
        guard needsRecoveryDecision, let savedAt = recoveryCheckpoint else { return false }
        let now = clock.read()
        let gaps = (session?.untrackedGaps ?? []) + [WalkingRecoveryGap(from: savedAt, to: max(savedAt, now.date))]
        session?.untrackedGaps = gaps
        session?.endedAt = savedAt
        needsRecoveryDecision = false; phase = .finished
        restStop.isWalking = false; intervalStart = nil
        persistFinishedRecovery(at: savedAt)
        if let session { completedSessions.insert(session, at: 0) }
        Task { await savePendingSessions() }
        return true
    }
    private func persistFinishedRecovery(at date: Date) {
        guard let session else { return }
        do { try recoveryStore?.save(WalkingRecoveryRecord(session: session, checkpointAt: date), owner: ownerID) }
        catch { recoveryError = "This walk’s recovery copy could not be saved. Retry saving before closing." }
    }

    func breakRoute() { needsRouteSegment = true }

    func recordLocation(_ location: CLLocation, receivedAt: Date = .now) {
        if isActive { restStop.update(location, now: receivedAt) }
        guard phase == .walking, let intervalStart,
              CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
              receivedAt.timeIntervalSince(location.timestamp) >= -2,
              receivedAt.timeIntervalSince(location.timestamp) <= 15,
              location.timestamp >= intervalStart.date else { return }
        let point = WalkingRoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                      recordedAt: location.timestamp, accuracyMetres: location.horizontalAccuracy)
        var segments = session?.routeSegments ?? []
        if let last = segments.last?.points.last {
            let gap = point.recordedAt.timeIntervalSince(last.recordedAt)
            guard gap > 0 else { return }
            if gap > 30 { needsRouteSegment = true }
            if !needsRouteSegment {
                let distance = location.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
                if distance / gap > 5 {
                    needsRouteSegment = true
                    return
                }
                guard distance >= 3 else { return }
            }
        }
        if needsRouteSegment || segments.isEmpty {
            segments.append(WalkingRouteSegment(points: [point]))
            needsRouteSegment = false
        } else {
            segments[segments.count - 1].points.append(point)
        }
        session?.routeSegments = segments
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
