import SwiftUI

struct WalkingHealthPanel: View {
    let model: WalkingHealthViewModel
    let gpsDistance: Double?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .leading)] : [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
                metric("Steps", value: model.steps.map(String.init) ?? "—", unit: "steps", symbol: "shoeprints.fill", note: "iPhone · this session")
                metric("Heart rate", value: model.heartRate.map { String(Int($0.rounded())) } ?? "—", unit: "bpm", symbol: "heart.fill", note: heartRateNote)
                metric("Distance", value: (model.distanceMetres ?? gpsDistance).map { String(format: "%.2f", $0 / 1000) } ?? "—", unit: "km", symbol: "point.bottomleft.forward.to.point.topright.scurvepath", note: model.distanceMetres != nil ? "iPhone · this session" : (gpsDistance != nil ? "GPS estimate" : "No readable distance"))
                metric("Active energy", value: model.activeKilocalories.map { String(Int($0.rounded())) } ?? "—", unit: "kcal", symbol: "flame.fill", note: "Apple Health · session")
            }
            if let message = model.motionMessage {
                Text(message).font(.caption2).foregroundStyle(.secondary)
            }
            if model.hasRequestedHealth {
                if let message = model.healthMessage {
                    Text(message).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await model.connectHealth() }
                } label: {
                    Label(model.isConnecting ? "Opening Apple Health…" : "Connect heart rate & energy", systemImage: "heart.text.clipboard")
                        .font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
                .disabled(model.isConnecting)
            }
            if let date = model.motionUpdatedAt {
                Text("Motion updated \(date, style: .relative) ago · Includes movement during rest")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var heartRateNote: String {
        guard let date = model.heartRateDate else { return "No readable sample" }
        let seconds = max(0, Int(Date.now.timeIntervalSince(date)))
        if seconds < 60 { return "Latest · \(seconds)s ago" }
        return "Older reading · \(seconds / 60)m ago"
    }

    private func metric(_ title: String, value: String, unit: String, symbol: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            Text(note).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
