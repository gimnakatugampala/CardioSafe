import SwiftUI

struct WalkingSavedHealthView: View {
    let snapshot: WalkingHealthSnapshot?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Health readings", systemImage: "heart.text.clipboard").font(.headline)
            if let snapshot {
                if snapshot.isSimulatorTestData == true {
                    Label("Simulator test readings", systemImage: "testtube.2").font(.subheadline.weight(.semibold))
                }
                row("Session steps", value: snapshot.steps.map(String.init) ?? "Unavailable", source: snapshot.isSimulatorTestData == true ? "HealthKit · simulated session" : "iPhone motion")
                row("Motion distance", value: snapshot.motionDistanceMetres.map { String(format: "%.2f km", $0 / 1000) } ?? "Unavailable", source: snapshot.isSimulatorTestData == true ? "HealthKit · simulated session" : "iPhone motion")
                if let date = snapshot.motionUpdatedAt {
                    timestamp("Motion data through", date: date)
                }
                Divider()
                row("Last heart rate", value: snapshot.lastHeartRateBPM.map { String(format: "%.0f bpm", $0) } ?? "Unavailable", source: "Apple Health")
                if let date = snapshot.heartRateRecordedAt {
                    timestamp("Sample recorded", date: date)
                }
                row("Active energy", value: snapshot.activeKilocalories.map { String(format: "%.0f kcal", $0) } ?? "Unavailable", source: "Apple Health · session")
                if let date = snapshot.energyThrough {
                    timestamp("Energy queried through", date: date)
                }
                Text("Last readings received before finishing. Sensor and sync delays may leave out the final part of your walk. Motion totals include movement during rest; heart rate is a single sample, not an average.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No health readings were saved with this walk.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(CardioSafeTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 18))
    }

    private func row(_ title: String, value: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: value).font(.subheadline)
            Text(source).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func timestamp(_ title: String, date: Date) -> some View {
        Text("\(title): \(date.formatted(date: .abbreviated, time: .standard))")
            .font(.caption2).foregroundStyle(.secondary)
    }
}

#if DEBUG
#Preview("Saved health · example readings") {
    ScrollView {
        WalkingSavedHealthView(snapshot: WalkingHealthSnapshot(
            capturedAt: .now, steps: 1200, motionDistanceMetres: 850,
            motionUpdatedAt: .now.addingTimeInterval(-5), lastHeartRateBPM: 92,
            heartRateRecordedAt: .now.addingTimeInterval(-30), activeKilocalories: 42,
            energyThrough: .now.addingTimeInterval(-10)))
            .padding(20)
    }
}
#Preview("Saved health · unavailable") {
    WalkingSavedHealthView(snapshot: nil).padding(20)
}
#endif
