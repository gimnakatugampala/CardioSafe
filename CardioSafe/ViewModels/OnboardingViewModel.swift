import Observation

@MainActor @Observable
final class OnboardingViewModel {
    private(set) var step = 0
    let stepCount = 3
    var isLastStep: Bool { step == stepCount - 1 }
    func next() { if !isLastStep { step += 1 } }
    func back() { if step > 0 { step -= 1 } }
}
