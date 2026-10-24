import Foundation

struct WalkingPlan: Equatable, Codable {
    let walkingMinutes: Int
    let restMinutesPerBreak: Int?
}
