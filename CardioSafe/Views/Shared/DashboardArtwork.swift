import SwiftUI

struct RecoveryMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width * 0.24, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.84))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.40))
        path.addLine(to: CGPoint(x: rect.width * 0.83, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.52))
        return path
    }
}

