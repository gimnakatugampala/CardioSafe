import SwiftUI

struct WalkingHistoryView: View {
    let viewModel: WalkingSessionViewModel
    @State private var selectedSession: WalkingSession?

    var body: some View {
        List {
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
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Walking history")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadHistory() }
        .sheet(item: $selectedSession, onDismiss: { Task { await viewModel.loadHistory() } }) { session in
            SavedWalkSummary(model: viewModel.summaryModel(for: session))
        }
    }
}

private struct SavedWalkSummary: View {
    @State private var model: WalkingSessionViewModel

    init(model: WalkingSessionViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View { WalkingSessionView(viewModel: model) }
}
