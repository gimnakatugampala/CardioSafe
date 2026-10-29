import Foundation
import Testing
@testable import CardioSafe

@MainActor struct AutomaticSOSTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func tick(_ model: AutomaticSOSViewModel, _ seconds: Double, sample: Double, bpm: Double = 160, eligible: Bool = true, busy: Bool = false) -> Bool {
        model.tick(bpm: bpm, sampleDate: start.addingTimeInterval(sample), eligible: eligible, busy: busy,
                   now: start.addingTimeInterval(seconds))
    }
    @Test func distinctReadingsStartCountdownAndSubmitExactlyOnce() {
        let model = AutomaticSOSViewModel()
        model.setEnabled(true, now: start)
        #expect(!tick(model, 0, sample: 0))
        #expect(!tick(model, 10, sample: 0))
        #expect(model.state == .monitoring)
        #expect(!tick(model, 10, sample: 10))
        #expect(model.state == .countdown && model.secondsRemaining == 20)
        #expect(!tick(model, 29, sample: 10))
        #expect(model.secondsRemaining == 1)
        #expect(tick(model, 30, sample: 10))
        #expect(model.state == .submitted)
        #expect(!tick(model, 31, sample: 20))
    }
    @Test func cancellationNormalReadingsAndStaleSamplesPreventSubmission() {
        for interruption in ["cancel", "normal", "stale", "background", "busy"] {
            let model = AutomaticSOSViewModel(); model.setEnabled(true, now: start)
            _ = tick(model, 0, sample: 0); _ = tick(model, 10, sample: 10)
            switch interruption {
            case "cancel": model.setEnabled(false)
            case "normal": _ = tick(model, 15, sample: 15, bpm: 90)
            case "stale": _ = tick(model, 45, sample: 10)
            case "background": _ = tick(model, 15, sample: 10, eligible: false)
            default: _ = tick(model, 15, sample: 10, busy: true)
            }
            #expect(!tick(model, 46, sample: 10))
            #expect(model.state != .submitted)
        }
    }
    @Test func oldFutureAndInvalidSamplesCannotArmCountdown() {
        let model = AutomaticSOSViewModel(); model.setEnabled(true, now: start)
        for (time, sample, bpm) in [(0.0, -1.0, 160.0), (0, 5, 160), (0, 0, Double.nan), (0, 0, 400), (40, 0, 160)] {
            #expect(!tick(model, time, sample: sample, bpm: bpm))
            #expect(model.state == .monitoring)
        }
        model.setEnabled(false)
        #expect(!tick(model, 50, sample: 50))
    }
}
