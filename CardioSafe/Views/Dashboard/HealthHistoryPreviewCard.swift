import SwiftUI
import Charts

struct HealthHistoryPreviewCard: View {
    let model: HealthHistoryViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    // MARK: Styling

    private var calendar: Calendar { .current }
    private var surface: Color { CardioSafeTheme.surface(for: scheme) }
    private var ink: Color { CardioSafeTheme.text(for: scheme) }
    private var stepColour: Color { CardioSafeTheme.accent(for: scheme) }
    private var heartColour: Color { scheme == .dark ? .pink : CardioSafeTheme.alert }

    // MARK: Derived data

    private var stepValues: [Double] { model.days.compactMap(\.steps) }
    private var heartValues: [Double] { model.days.compactMap(\.averageHeartRate) }
    private var averageSteps: Double? {
        stepValues.isEmpty ? nil : stepValues.reduce(0, +) / Double(stepValues.count)
    }
    private var averageHeart: Double? {
        heartValues.isEmpty ? nil : heartValues.reduce(0, +) / Double(heartValues.count)
    }
    private var today: HealthHistoryDay? {
        model.days.last(where: { calendar.isDateInToday($0.date) })
    }
    private var hasData: Bool { !stepValues.isEmpty || !heartValues.isEmpty }

    private var dateRange: ClosedRange<Date> {
        guard let first = model.days.first?.date, let last = model.days.last?.date else {
            let start = calendar.startOfDay(for: .now)
            return start...start.addingTimeInterval(86400)
        }
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86400)
        return first...max(first, end)
    }

    private var stepDomain: ClosedRange<Double> {
        0...max(1000, (stepValues.max() ?? 0) * 1.15)
    }

    private var heartDomain: ClosedRange<Double> {
        guard let low = heartValues.min(), let high = heartValues.max() else { return 40...120 }
        return max(0, low - 8)...(high + 8)
    }

    private func format(_ value: Double) -> String { Int(value.rounded()).formatted() }

    private var summary: String {
        guard hasData else { return "Health history, last 7 days. No readable data yet." }
        var parts = ["Health history, last 7 days."]
        if let averageSteps { parts.append("Average \(format(averageSteps)) steps per day.") }
        if let steps = today?.steps { parts.append("\(format(steps)) steps today so far.") }
        if let averageHeart { parts.append("Average heart rate \(format(averageHeart)) beats per minute.") }
        return parts.joined(separator: " ")
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(ink.opacity(0.05)))
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 12, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityHint("Opens your full health history")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Health history", systemImage: "chart.bar.xaxis")
                .font(.headline)
            Spacer(minLength: 4)
            Text("7 days").font(.caption).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var content: some View {
        if model.days.isEmpty && model.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Reading Apple Health…").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else if model.days.isEmpty, model.error != nil {
            Label("Couldn’t read your history. Tap to open it and retry.", systemImage: "exclamationmark.circle")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        } else if !hasData {
            VStack(alignment: .leading, spacing: 6) {
                Label("No readable history yet", systemImage: "heart.text.clipboard")
                    .font(.subheadline.weight(.semibold))
                Text("Allow Steps and Heart Rate in Apple Health. Days appear once readable samples exist.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        } else {
            readings
        }
    }

    // MARK: Readings

    private var readings: some View {
        VStack(alignment: .leading, spacing: 14) {
            (typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 8))) {
                stat("Today", value: today?.steps.map(format) ?? "—", unit: "steps so far", colour: stepColour)
                stat("Average", value: averageSteps.map(format) ?? "—", unit: "steps / day", colour: ink)
                stat("Heart rate", value: averageHeart.map(format) ?? "—", unit: "avg bpm", colour: heartColour)
            }

            if !stepValues.isEmpty { stepsChart }
            if !heartValues.isEmpty { heartTrend }

            Text("Missing days are shown as unavailable, not zero.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func stat(_ title: String, value: String, unit: String, colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
                .foregroundStyle(colour).lineLimit(1).minimumScaleFactor(0.7)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepsChart: some View {
        Chart {
            ForEach(model.days) { day in
                if let steps = day.steps {
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", steps))
                        .foregroundStyle(calendar.isDateInToday(day.date) ? stepColour : stepColour.opacity(0.35))
                        .cornerRadius(5)
                }
            }
            if let averageSteps {
                RuleMark(y: .value("Average", averageSteps))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
        .chartXScale(domain: dateRange)
        .chartYScale(domain: stepDomain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: model.days.map(\.date)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .font(.caption2)
        .frame(height: typeSize.isAccessibilitySize ? 150 : 110)
    }

    private var heartTrend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Average heart rate", systemImage: "heart.fill")
                .font(.caption.weight(.medium)).foregroundStyle(heartColour)
            Chart {
                ForEach(model.days) { day in
                    if let bpm = day.averageHeartRate {
                        LineMark(x: .value("Day", day.date, unit: .day), y: .value("Heart rate", bpm))
                            .foregroundStyle(heartColour)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Day", day.date, unit: .day), y: .value("Heart rate", bpm))
                            .foregroundStyle(heartColour)
                            .symbolSize(calendar.isDateInToday(day.date) ? 70 : 30)
                    }
                }
            }
            .chartXScale(domain: dateRange)
            .chartYScale(domain: heartDomain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 48)
        }
    }
}
