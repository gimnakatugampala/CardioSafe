import Foundation
import Observation

/// A non-clinical coursework trigger; it never diagnoses a medical emergency.
@MainActor @Observable final class AutomaticSOSViewModel {
    enum State: Equatable { case off, monitoring, countdown, submitted }
    private(set) var state: State = .off
    private(set) var secondsRemaining = 20
    private var armedAt: Date?
    private var firstHigh: Date?
    private var lastSample: Date?
    private var deadline: Date?
    var enabled: Bool { state == .monitoring || state == .countdown }
    func setEnabled(_ enabled: Bool, now: Date = .now) {
        state = enabled ? .monitoring : .off
        armedAt = enabled ? now : nil
        firstHigh = nil; lastSample = nil; deadline = nil; secondsRemaining = 20
    }
    /// Returns true exactly once when a foreground countdown expires.
    func tick(bpm: Double?, sampleDate: Date?, eligible: Bool, busy: Bool, now: Date = .now) -> Bool {
        guard enabled else { return false }
        guard eligible, !busy else { setEnabled(false); return false }
        guard let bpm, bpm.isFinite, bpm > 0, bpm <= 300, let sampleDate, let armedAt,
              sampleDate >= armedAt, (-2...30).contains(now.timeIntervalSince(sampleDate)) else {
            firstHigh = nil; deadline = nil; state = .monitoring; secondsRemaining = 20
            return false
        }
        if lastSample == nil || sampleDate > lastSample! {
            lastSample = sampleDate
            if bpm < 140 {
                firstHigh = nil; deadline = nil; state = .monitoring; secondsRemaining = 20
                return false
            }
            if let firstHigh, sampleDate.timeIntervalSince(firstHigh) >= 10, deadline == nil {
                deadline = now.addingTimeInterval(20); state = .countdown
            } else if firstHigh == nil { firstHigh = sampleDate }
        }
        guard let deadline else { return false }
        secondsRemaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
        guard now >= deadline else { return false }
        state = .submitted; self.deadline = nil
        return true
    }
}
