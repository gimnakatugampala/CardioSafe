import Foundation
import Observation

@MainActor
@Observable
final class WalkingPlanViewModel {
    var walkingMinutesText: String
    var includesPlannedRest: Bool
    var restMinutesText: String
    private(set) var attemptedSave = false

    init(plan: WalkingPlan? = nil) {
        walkingMinutesText = plan.map { String($0.walkingMinutes) } ?? ""
        includesPlannedRest = plan?.restMinutesPerBreak != nil
        restMinutesText = plan?.restMinutesPerBreak.map(String.init) ?? ""
    }

    var walkingError: String? {
        attemptedSave ? validationError(for: walkingMinutesText, field: "walking duration") : nil
    }

    var restError: String? {
        attemptedSave && includesPlannedRest
            ? validationError(for: restMinutesText, field: "rest duration") : nil
    }

    func submit() -> WalkingPlan? {
        attemptedSave = true
        guard validationError(for: walkingMinutesText, field: "walking duration") == nil,
              let walking = Int(clean(walkingMinutesText)) else { return nil }

        var rest: Int?
        if includesPlannedRest {
            guard validationError(for: restMinutesText, field: "rest duration") == nil,
                  let minutes = Int(clean(restMinutesText)) else { return nil }
            rest = minutes
        }
        return WalkingPlan(walkingMinutes: walking, restMinutesPerBreak: rest)
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validationError(for text: String, field: String) -> String? {
        let value = clean(text)
        if value.isEmpty { return "Enter the \(field) provided by your clinician." }
        guard value.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return "Use whole minutes without signs, symbols or decimals."
        }
        guard let minutes = Int(value), minutes <= Int.max / 60 else {
            return "This duration is too large. Check the number of minutes."
        }
        return minutes > 0 ? nil : "Enter a duration greater than zero."
    }
}
