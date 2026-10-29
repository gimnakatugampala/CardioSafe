import Foundation
import AppIntents

enum WalkingVoiceAction: String, AppEnum, Codable, CaseIterable {
    case start, rest, resume
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Walking action"
    static var caseDisplayRepresentations: [WalkingVoiceAction: DisplayRepresentation] = [
        .start: "Start walking", .rest: "Take a rest", .resume: "Resume walking"]
}
struct WalkingVoiceRequest: Codable {
    let action: WalkingVoiceAction
    let owner: String
    let date: Date
}
enum WalkingVoiceQueue {
    static let key = "walkingVoiceRequest"
    static func submit(_ action: WalkingVoiceAction, defaults: UserDefaults = .standard, now: Date = .now) throws {
        let request = WalkingVoiceRequest(action: action, owner: defaults.string(forKey: "walkingVoiceOwner") ?? "guest", date: now)
        defaults.set(try JSONEncoder().encode(request), forKey: key)
    }
    static func take(owner: String, defaults: UserDefaults = .standard, now: Date = .now) -> WalkingVoiceAction? {
        guard let data = defaults.data(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        guard let request = try? JSONDecoder().decode(WalkingVoiceRequest.self, from: data), request.owner == owner,
              (0...60).contains(now.timeIntervalSince(request.date)) else { return nil }
        return request.action
    }
}
struct WalkingVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Control walking"
    static var description = IntentDescription("Open CardioSafe to start, pause for rest, or resume a walk. Unlock the app to apply the action.")
    static var openAppWhenRun = true
    @Parameter(title: "Action") var action: WalkingVoiceAction
    init() { action = .start }
    init(action: WalkingVoiceAction) { self.action = action }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try WalkingVoiceQueue.submit(action)
        return .result(dialog: "Opening CardioSafe. Unlock the app to apply your walking action.")
    }
}
struct CardioSafeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WalkingVoiceIntent(action: .start), phrases: ["Start walking with \(.applicationName)"], shortTitle: "Start walking", systemImageName: "figure.walk")
        AppShortcut(intent: WalkingVoiceIntent(action: .rest), phrases: ["Take a rest with \(.applicationName)"], shortTitle: "Take a rest", systemImageName: "pause.circle")
        AppShortcut(intent: WalkingVoiceIntent(action: .resume), phrases: ["Resume walking with \(.applicationName)"], shortTitle: "Resume walking", systemImageName: "play.circle")
    }
}

@MainActor enum WalkingVoiceExecutor {
    static func apply(_ action: WalkingVoiceAction, session: WalkingSessionViewModel, plan: WalkingPlan?) -> Bool {
        switch action {
        case .start: return session.isActive || session.start(plan: plan)
        case .rest: return session.beginRest()
        case .resume: return session.resume()
        }
    }
}
