import SwiftUI
import AppIntents
import AVFoundation

struct WalkingVoiceControlsView: View {
    @Environment(WalkingSessionViewModel.self) private var session
    @State private var testMessage: String?
    @State private var speaker = AVSpeechSynthesizer()
    var body: some View {
        List {
            Section("Ask Siri") {
                Text("Start walking with CardioSafe")
                Text("Take a rest with CardioSafe")
                Text("Resume walking with CardioSafe")
                ShortcutsLink()
            }
            Section {
                Text("Siri opens CardioSafe. Unlock the app within 60 seconds to apply the action. These shortcuts never create SOS requests or finish/delete a walk.")
                Text("Siri availability depends on the device and iOS settings. You can also run these actions through Apple Shortcuts.")
            }.font(.footnote)
            if session.healthModel.supportsSimulatorFeed {
                Section("Simulator shortcut check") {
                    Button("Try Start walking action") { submit(.start) }
                    Button("Try Take a rest action") { submit(.rest) }
                    Button("Try Resume walking action") { submit(.resume) }
                    if let testMessage { Text(testMessage).font(.caption) }
                    Text("Runs the same command handoff as the Siri shortcuts. Siri speech recognition itself depends on simulator/device support.").font(.caption)
                }
            }
            Section("Spoken status") {
                Button("Read my walking status aloud") {
                    let timing = session.timing()
                    let text = session.isActive
                        ? "\(session.phase == .resting ? "Resting" : "Walking"). Walking time \(Int(timing.walkingSeconds)) seconds. Total rest \(Int(timing.restingSeconds)) seconds."
                        : "No walking session is active."
                    speaker.stopSpeaking(at: .immediate)
                    speaker.speak(AVSpeechUtterance(string: text))
                }
                Text("Speaks only walking and rest time. It does not read health measurements or personal details aloud.").font(.footnote)
            }
        }.navigationTitle("Voice & Siri").navigationBarTitleDisplayMode(.inline)
        .onDisappear { speaker.stopSpeaking(at: .immediate) }
    }
    private func submit(_ action: WalkingVoiceAction) {
        do { try WalkingVoiceQueue.submit(action); testMessage = "Action handed to CardioSafe." }
        catch { testMessage = "The action could not be queued. Please retry." }
    }
}
