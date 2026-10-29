import SwiftUI
import Charts

struct HealthHistoryView: View {
    @State private var model = HealthHistoryViewModel()
    @State private var metric = Metric.steps
    private enum Metric: String, CaseIterable { case steps = "Steps", heart = "Heart rate" }
    private func value(_ day: HealthHistoryDay) -> Double? { metric == .steps ? day.steps : day.averageHeartRate }
    private var readable: [HealthHistoryDay] { model.days.filter { value($0) != nil } }
    private var dateRange: ClosedRange<Date> {
        let start = model.days.first?.date ?? Calendar.current.startOfDay(for: .now)
        let last = model.days.last?.date ?? start
        let end = Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86400)
        return start...max(start, end)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Last 7 days").font(.title2.bold())
                Picker("Health metric", selection: $metric) {
                    ForEach(Metric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                if model.isLoading { ProgressView("Reading Apple Health…") }
                if let error = model.error {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry") { Task { await model.load() } }.frame(minHeight: 44)
                } else if !model.isLoading && readable.isEmpty {
                    ContentUnavailableView("No readable history", systemImage: "chart.bar.xaxis", description: Text("Allow Steps and Heart Rate in Apple Health. Data appears only for days with readable samples."))
                }
                if !readable.isEmpty {
                    Text(metric == .steps ? "Recorded daily steps" : "Average recorded heart rate · bpm").font(.headline)
                    Chart(model.days) { day in
                        if let value = value(day) {
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value(metric.rawValue, value))
                                .foregroundStyle(metric == .steps ? Color.teal : Color.pink)
                                .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("\(Int(value.rounded())) \(metric == .steps ? "steps" : "beats per minute, sample average")")
                        }
                    }
                    .chartXScale(domain: dateRange)
                    .chartXAxis { AxisMarks(values: model.days.map(\.date)) { AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
                    .frame(height: 230)
                }
                Text("Apple Health on this device · Missing readings are shown as unavailable, not zero. Heart rate is the average of available samples, not a resting-heart-rate measurement or continuous monitoring. Simulator test samples are included if present.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.days.reversed()) { day in
                    HStack {
                        Text(day.date, format: .dateTime.weekday(.wide).day().month())
                        Spacer()
                        Text(value(day).map { "\(Int($0.rounded())) \(metric == .steps ? "steps" : "bpm")" } ?? "Unavailable")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }.font(.subheadline).accessibilityElement(children: .combine)
                    Divider()
                }
            }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .navigationTitle("Health history").navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}
