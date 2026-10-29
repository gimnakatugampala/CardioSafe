import SwiftUI

struct WalkingHistoryView: View {
    let viewModel: WalkingSessionViewModel
    var title = "Walking history"
    @Environment(\.colorScheme) private var scheme
    @State private var selectedSession: WalkingSession?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Label("YOUR WALKING RECORD", systemImage: "figure.walk")
                        .font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(CardioSafeTheme.accent(for: scheme))
                    Text("Every walk counts.").font(.title2.bold())
                    HStack(alignment: .top, spacing: 16) {
                        metric("Walks", value: "\(viewModel.completedSessions.count)")
                        metric("Walking", value: viewModel.durationText(viewModel.completedSessions.reduce(0) { $0 + $1.walkingSeconds }))
                        metric("Resting", value: viewModel.durationText(viewModel.completedSessions.reduce(0) { $0 + $1.restingSeconds }))
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
            Section("Completed walks") {
            ForEach(viewModel.completedSessions) { session in
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
