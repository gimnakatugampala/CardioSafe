import SwiftUI

enum CardioSafeTheme {
    static let navy = Color(red: 0.055, green: 0.13, blue: 0.25)
    static let teal = Color(red: 0.02, green: 0.35, blue: 0.58)
    static let alert = Color(red: 0.72, green: 0.16, blue: 0.21)

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.04, green: 0.07, blue: 0.12)
            : Color(red: 0.95, green: 0.96, blue: 0.98)
    }

    static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.08, green: 0.12, blue: 0.18) : .white
    }

    static func text(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.90, green: 0.93, blue: 0.97) : navy
    }
}
