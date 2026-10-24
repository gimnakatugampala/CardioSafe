import Foundation

struct WalkingSessionInstant {
    let date: Date
    let monotonicSeconds: TimeInterval
}

@MainActor
protocol WalkingSessionClock {
    func read() -> WalkingSessionInstant
}

@MainActor
struct SystemWalkingSessionClock: WalkingSessionClock {
    private let reference = ContinuousClock.now

    func read() -> WalkingSessionInstant {
        let elapsed = reference.duration(to: ContinuousClock.now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
        return WalkingSessionInstant(date: Date(), monotonicSeconds: seconds)
    }
}
