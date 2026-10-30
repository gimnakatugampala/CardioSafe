import SwiftUI

struct WalkingHistoryView: View {
    let viewModel: WalkingSessionViewModel
    var title = "Walking history"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedSession: WalkingSession?
    @State private var period: Period = .all
    @State private var sort: Sort = .newest

    enum Period: String, CaseIterable, Identifiable {
        case all = "All time", week = "Last 7 days", month = "Last 30 days"
        var id: String { rawValue }
        var days: Int? { self == .week ? 7 : (self == .month ? 30 : nil) }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case newest = "Newest first", oldest = "Oldest first", longest = "Longest walk", farthest = "Farthest"
        var id: String { rawValue }
    }
    private var visibleSessions: [WalkingSession] {
        var items = viewModel.completedSessions
        if let days = period.days, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) {
            items = items.filter { $0.startedAt >= cutoff }
        }
        switch sort {
        case .newest: return items.sorted { $0.startedAt > $1.startedAt }
        case .oldest: return items.sorted { $0.startedAt < $1.startedAt }
        case .longest: return items.sorted { $0.walkingSeconds > $1.walkingSeconds }
        case .farthest: return items.sorted { $0.routeDistanceMetres > $1.routeDistanceMetres }
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Label("YOUR WALKING RECORD", systemImage: "figure.walk")
                        .font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(CardioSafeTheme.accent(for: scheme))
                    Text("Every walk counts.").font(.title2.bold())
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))) {
                        metric("Walks", value: "\(viewModel.completedSessions.count)")
                        metric("Walking", value: viewModel.durationText(viewModel.completedSessions.reduce(0) { $0 + $1.walkingSeconds }))
                        metric("Resting", value: viewModel.durationText(viewModel.completedSessions.reduce(0) { $0 + $1.restingSeconds }))
                        metric("Distance", value: WalkingSession.distanceText(viewModel.completedSessions.reduce(0) { $0 + $1.routeDistanceMetres }))
                    }
                    Label("Backup status is available in Profile → Account sync", systemImage: "icloud")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 10)
            }
            if viewModel.isLoadingHistory {
                ProgressView("Loading walks…")
            }
            if let error = viewModel.historyError {
                Section {
                    Text(error)
                    Button("Retry loading") { Task { await viewModel.loadHistory() } }
                }
            }
            if let error = viewModel.saveError {
                Section {
                    Text(error)
                    Button("Retry saving") { Task { await viewModel.savePendingSessions() } }
                }
            }
            if viewModel.completedSessions.isEmpty && !viewModel.isLoadingHistory && viewModel.historyError == nil {
                ContentUnavailableView("Your walks will appear here", systemImage: "figure.walk",
                                       description: Text("Finish a walking session to keep its walking time and rest breaks."))
            }
            if viewModel.completedSessions.count > 1 {
                Section {
                    Picker("Period", selection: $period) { ForEach(Period.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Sort by", selection: $sort) { ForEach(Sort.allCases) { Text($0.rawValue).tag($0) } }
                }
            }
            if visibleSessions.isEmpty && !viewModel.completedSessions.isEmpty {
                ContentUnavailableView("No walks in this period", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("Choose a longer period to see earlier walks."))
            }
            Section("Completed walks (\(visibleSessions.count))") {
            ForEach(visibleSessions) { session in
                Button { selectedSession = session } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(session.startedAt, format: .dateTime.day().month(.abbreviated).year())
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        Text(session.startedAt, format: .dateTime.hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Walk \(viewModel.durationText(session.walkingSeconds)) · Rest \(viewModel.durationText(session.restingSeconds))")
                            .font(.subheadline).monospacedDigit()
                        if session.routeDistanceMetres > 0 || session.healthSnapshot?.steps != nil {
                            HStack(spacing: 12) {
                                if session.routeDistanceMetres > 0 {
                                    Label(WalkingSession.distanceText(session.routeDistanceMetres), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                }
                                if let pace = session.averagePaceText { Label(pace, systemImage: "speedometer") }
                                if let steps = session.healthSnapshot?.steps { Label("\(steps) steps", systemImage: "shoeprints.fill") }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        if session.isSimulated {
                            Label("Simulated journey", systemImage: "testtube.2").font(.caption).foregroundStyle(.secondary)
                        }
                        if !viewModel.savedSessionIDs.contains(session.id) {
                            Label("Not saved yet", systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 8)
                    .foregroundStyle(CardioSafeTheme.text(for: scheme))
                }
            }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CardioSafeTheme.background(for: scheme))
        .refreshable { await viewModel.loadHistory() }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadHistory() }
        .sheet(item: $selectedSession, onDismiss: { Task { await viewModel.loadHistory() } }) { session in
            SavedWalkSummary(model: viewModel.summaryModel(for: session))
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.headline).monospacedDigit().foregroundStyle(CardioSafeTheme.text(for: scheme))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SavedWalkSummary: View {
    @State private var model: WalkingSessionViewModel

    init(model: WalkingSessionViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View { WalkingSessionView(viewModel: model) }
}
