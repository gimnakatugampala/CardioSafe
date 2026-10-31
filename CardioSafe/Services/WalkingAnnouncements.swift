import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class WalkingAnnouncements {
    static let shared = WalkingAnnouncements()
    private let speaker = AVSpeechSynthesizer()

    func started() {
        announce("Walk started.")
    }

    func finished(walkingSeconds: TimeInterval, restingSeconds: TimeInterval) {
        announce("Walk finished. Walking time \(duration(walkingSeconds)). Resting time \(duration(restingSeconds)).")
    }

    private func announce(_ text: String) {
        guard UserDefaults.standard.object(forKey: "walkingSpokenAnnouncementsEnabled") as? Bool ?? true else { return }
        #if canImport(UIKit)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }
        #endif
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        speaker.speak(utterance)
    }

    private func duration(_ value: TimeInterval) -> String {
        let seconds = Int(max(0, value).rounded(.down))
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes == 0 { return "\(seconds) \(seconds == 1 ? "second" : "seconds")" }
        let text = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        return remainder == 0 ? text : "\(text), \(remainder) \(remainder == 1 ? "second" : "seconds")"
    }
}
