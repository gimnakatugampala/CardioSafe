import SwiftUI
import Charts

struct HealthHistoryView: View {
    @State private var model = HealthHistoryViewModel()
    @State private var metric = Metric.steps
    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Metric: String, CaseIterable, Identifiable {
        case steps = "Steps", heart = "Heart rate"
        var id: String { rawValue }
        var unit: String { self == .steps ? "steps" : "bpm" }
        var symbol: String { self == .steps ? "shoeprints.fill" : "heart.fill" }
    }

    private struct Stat {
        let title: String
        let value: String
        let unit: String
    }

    // MARK: Derived data

    private var calendar: Calendar { .current }
    private var surface: Color { CardioSafeTheme.surface(for: scheme) }
    private var ink: Color { CardioSafeTheme.text(for: scheme) }
    private var tint: Color {
        metric == .steps ? CardioSafeTheme.accent(for: scheme) : (scheme == .dark ? .pink : CardioSafeTheme.alert)
    }

    private func value(_ day: HealthHistoryDay) -> Double? { metric == .steps ? day.steps : day.averageHeartRate }
    private var readable: [HealthHistoryDay] { model.days.filter { value($0) != nil } }
    private var values: [Double] { readable.compactMap { value($0) } }
    private var average: Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }

    private var dateRange: ClosedRange<Date> {
        let start = model.days.first?.date ?? calendar.startOfDay(for: .now)
        let last = model.days.last?.date ?? start
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86400)
        return start...max(start, end)
    }

    private var yDomain: ClosedRange<Double> {
        let high = values.max() ?? 0
        switch metric {
        case .steps:
            return 0...max(1000, high * 1.2)
        case .heart:
            guard let low = values.min() else { return 40...120 }
            let lower = max(0, ((low - 10) / 10).rounded(.down) * 10)
            let upper = ((high + 10) / 10).rounded(.up) * 10
            return lower...max(upper, lower + 20)
        }
    }

    private var selectedDay: HealthHistoryDay? {
        guard let selectedDate else { return nil }
        return model.days.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var stats: [Stat] {
        guard !values.isEmpty, let average else { return [] }
        switch metric {
        case .steps:
            return [Stat(title: "Daily average", value: format(average), unit: "steps"),
                    Stat(title: "Best day", value: format(values.max() ?? 0), unit: "steps"),
                    Stat(title: "Total", value: format(values.reduce(0, +)), unit: "steps")]
        case .heart:
            return [Stat(title: "Average", value: format(average), unit: "bpm"),
                    Stat(title: "Lowest", value: format(values.min() ?? 0), unit: "bpm"),
                    Stat(title: "Highest", value: format(values.max() ?? 0), unit: "bpm")]
        }
    }

    private func format(_ value: Double) -> String { Int(value.rounded()).formatted() }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last 7 days").font(.title2.bold())
                    if !model.days.isEmpty {
                        Text("\(readable.count) of \(model.days.count) days have readable \(metric.rawValue.lowercased()) data")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Picker("Health metric", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)

                if model.isLoading { ProgressView("Reading Apple Health…") }
                if let error = model.error {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry") { Task { await model.load() } }.frame(minHeight: 44)
                } else if !model.isLoading && readable.isEmpty {
                    ContentUnavailableView("No readable history", systemImage: "chart.bar.xaxis",
                                           description: Text("Allow Steps and Heart Rate in Apple Health. Data appears only for days with readable samples."))
                }

                if !readable.isEmpty {
                    statsRow
                    chartCard
                }

                if !model.days.isEmpty { dailyBreakdown }

                Text("Apple Health on this device · Missing readings are shown as unavailable, not zero. Heart rate is the average of available samples, not a resting-heart-rate measurement or continuous monitoring.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .background(CardioSafeTheme.background(for: scheme))
        .tint(CardioSafeTheme.accent(for: scheme))
        .navigationTitle("Health history").navigationBarTitleDisplayMode(.inline)
        .onChange(of: metric) { _, _ in selectedDate = nil }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    // MARK: Summary tiles

    private var statsRow: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
            ForEach(stats, id: \.title) { stat in
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat.title).font(.caption).foregroundStyle(.secondary)
                    Text(stat.value).font(.title3.bold()).monospacedDigit()
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Text(stat.unit).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(surface, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(metric == .steps ? "Recorded daily steps" : "Average heart rate",
                      systemImage: metric.symbol)
                    .font(.headline).foregroundStyle(tint)
                Spacer()
                Text("Tap or drag a day").font(.caption2).foregroundStyle(.secondary)
            }
            chart
                .frame(height: typeSize.isAccessibilitySize ? 300 : 240)
        }
        .padding(16)
        .background(surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(ink.opacity(0.05)))
    }

    private var chart: some View {
        Chart {
            ForEach(model.days) { day in
                if let v = value(day) {
                    if metric == .steps {
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", v))
                            .foregroundStyle(tint.gradient)
                            .cornerRadius(6)
                            .opacity(isDimmed(day) ? 0.35 : 1)
                            .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                            .accessibilityValue("\(format(v)) steps")
                    } else {
                        AreaMark(x: .value("Day", day.date, unit: .day),
                                 yStart: .value("Baseline", yDomain.lowerBound),
                                 yEnd: .value("Heart rate", v))
                            .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Day", day.date, unit: .day), y: .value("Heart rate", v))
                            .foregroundStyle(tint)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Day", day.date, unit: .day), y: .value("Heart rate", v))
                            .foregroundStyle(tint)
                            .symbolSize(isDimmed(day) ? 40 : 90)
                            .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                            .accessibilityValue("\(format(v)) beats per minute, sample average")
                    }
                }
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("Avg \(format(average))").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if let day = selectedDay {
                RuleMark(x: .value("Selected", day.date, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .zIndex(-1)
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        callout(for: day)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: dateRange)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: model.days.map(\.date)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(number, format: .number.notation(.compactName))
                    }
                }
            }
        }
    }

    private func isDimmed(_ day: HealthHistoryDay) -> Bool {
        guard let selected = selectedDay else { return false }
        return !calendar.isDate(day.date, inSameDayAs: selected.date)
    }

    private func callout(for day: HealthHistoryDay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.caption2).foregroundStyle(.secondary)
            if let v = value(day) {
                Text("\(format(v)) \(metric.unit)").font(.caption.bold()).monospacedDigit()
            } else {
                Text("No data").font(.caption.bold())
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Daily list

    private var dailyBreakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Day by day").font(.headline).padding(.bottom, 12)
            let maximum = max(values.max() ?? 1, 1)
            ForEach(Array(model.days.reversed().enumerated()), id: \.element.id) { index, day in
                if index > 0 { Divider() }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.date, format: .dateTime.weekday(.wide).day().month())
                        if calendar.isDateInToday(day.date) {
                            Text("Today · so far").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let v = value(day), metric == .steps, !typeSize.isAccessibilitySize {
                        ProgressView(value: v, total: maximum).tint(tint).frame(width: 64)
                    }
                    Text(value(day).map { "\(format($0)) \(metric.unit)" } ?? "Unavailable")
                        .monospacedDigit().foregroundStyle(value(day) == nil ? .secondary : ink)
                }
                .font(.subheadline).padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .background(surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(ink.opacity(0.05)))
    }
}
