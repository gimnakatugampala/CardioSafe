import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home", walk = "Walk", care = "Find Care", records = "Records", profile = "Profile"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: "house"
        case .walk: "figure.walk"
        case .care: "cross.case"
        case .records: "doc.text"
        case .profile: "person.crop.circle"
        }
    }
    var explanation: String {
        switch self {
        case .home: "Your recovery dashboard."
        case .walk: "Walking plans and session tracking are not set up yet. Your plan will use the duration provided by your clinician."
        case .care: "Facility search and live department queues are not connected yet."
        case .records: "Document scanning, saved records and reminders are not set up yet."
        case .profile: "Account sign-in, privacy settings and permissions are not set up yet."
        }
    }
}

