import SwiftUI

struct WalkingOverviewView: View {
    let viewModel: DashboardViewModel
    let sessionViewModel: WalkingSessionViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingPlanSetup = false
    @State private var showingWalkingMap = false
    @State private var showingSession = false

    private var surface: Color { CardioSafeTheme.surface(for: colorScheme) }
    private var plan: WalkingPlan? {
        sessionViewModel.isActive ? sessionViewModel.session?.plan : viewModel.snapshot.walkingPlan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                primaryButton(sessionViewModel.isActive ? "Return to walk" : "Start walking",
                              symbol: sessionViewModel.isActive ? "arrow.up.right" : "play.fill") {
                    if sessionViewModel.isActive || sessionViewModel.start(plan: viewModel.snapshot.walkingPlan) {
                        showingSession = true
                    }
                }
                Text(sessionViewModel.isActive ? "Your session is still running." : "Tap to start. Add a walking target whenever you need one.")
                    .font(.subheadline).foregroundStyle(.secondary)
                planSection
                HStack(spacing: 16) {
                    Button { showingWalkingMap = true } label: {
                        Label("Explore map", systemImage: "map")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    NavigationLink {
                        WalkingHistoryView(viewModel: sessionViewModel)
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                if sessionViewModel.hasSummary { recentSummary }
                if let error = sessionViewModel.saveError {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Retry saving walks") { Task { await sessionViewModel.savePendingSessions() } }
                }
                DisclosureGroup("About walking tracking") { WalkingModeNote().padding(.top, 10) }
                    .font(.subheadline).padding(.horizontal, 2)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(20).frame(maxWidth: .infinity)
        }
        .background(CardioSafeTheme.background(for: colorScheme))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPlanSetup) {
            WalkingPlanSetupView(plan: viewModel.snapshot.walkingPlan) { plan in
                try await viewModel.saveWalkingPlan(plan)
            }
        }
        .sheet(isPresented: $showingWalkingMap) { WalkingMapView() }
        .fullScreenCover(isPresented: $showingSession) {
            WalkingSessionView(viewModel: sessionViewModel)
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Your walking plan", systemImage: "figure.walk")
                    .font(.headline)
                Spacer(minLength: 4)
                if plan != nil && !sessionViewModel.isActive && viewModel.planLoadError == nil {
                    Button("Edit") { showingPlanSetup = true }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
            }
            if viewModel.isLoadingPlan {
                ProgressView("Loading your saved plan…")
            } else if let error = viewModel.planLoadError, !sessionViewModel.isActive {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Retry loading plan") { Task { await viewModel.loadWalkingPlan() } }
                    .buttonStyle(.borderedProminent)
            } else if let plan {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 18) { planMetrics(plan) }
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        planMetrics(plan)
                    }
                }
                Text(sessionViewModel.isActive
                     ? "This session uses the plan you started with."
                     : "Targets entered from your clinician’s plan.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()

            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Walking target · Optional").font(.title3.weight(.semibold))
                    Text("You can walk without a target, or add the duration and rest interval from your clinician’s plan.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button("Add walking plan") { showingPlanSetup = true }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private func planMetrics(_ plan: WalkingPlan) -> some View {
        WalkingMetric(title: "Walking target", value: "\(plan.walkingMinutes)", unit: "minutes", symbol: "figure.walk")
        WalkingMetric(title: "Rest per break", value: plan.restMinutesPerBreak.map(String.init) ?? "Not set",
                      unit: plan.restMinutesPerBreak == nil ? "optional" : "minutes", symbol: "pause.circle")
    }

    private func primaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Image(systemName: symbol)
            }
            .font(.subheadline.bold()).foregroundStyle(.white)
            .padding(17).background(CardioSafeTheme.navy, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }

    private var recentSummary: some View {
        Button { showingSession = true } label: {
            HStack(spacing: 13) {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(CardioSafeTheme.teal)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your latest session").font(.subheadline.bold())
                    Text("Review walking time and rest periods").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(18).background(surface, in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
    }
}
