import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedIntroduction") private var hasCompletedIntroduction = false
    @AppStorage("appearancePreference") private var appearance = "system"
    @State private var selection: AppTab = .home
    @State private var accountModel = AccountViewModel(service: FirebaseAccountService())
    @State private var showingEmergency = false
    @State private var showingWalkingSession = false
    @State private var dashboardViewModel: DashboardViewModel
    @State private var sessionViewModel: WalkingSessionViewModel

    init(viewModel: DashboardViewModel, sessionViewModel: WalkingSessionViewModel) {
        _dashboardViewModel = State(initialValue: viewModel)
        _sessionViewModel = State(initialValue: sessionViewModel)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.rawValue, systemImage: tab.symbol, value: tab) {
                    NavigationStack {
                        destination(for: tab)
                            .toolbar(.hidden, for: .tabBar)
                            .navigationTitle(tab == .home ? "" : tab.rawValue)
                            .toolbar(tab == .home ? .hidden : .visible, for: .navigationBar)
                            .toolbar {
                                ToolbarItem(placement: .primaryAction) {
                                    Button { showingEmergency = true } label: {
                                        Label("Emergency Help", systemImage: "sos.circle")
                                    }
                                    .tint(.red)
                                }
                            }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomNavigation }
        .fullScreenCover(isPresented: $showingWalkingSession) {
            WalkingSessionView(viewModel: sessionViewModel)
        }
        .tint(CardioSafeTheme.teal)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .sheet(isPresented: $showingEmergency) { EmergencyHelpView() }
        .fullScreenCover(isPresented: Binding(get: { !hasCompletedIntroduction }, set: { _ in })) {
            OnboardingView(account: accountModel.account, onFinish: {
                hasCompletedIntroduction = true
            }, onSetUpProfile: {
                selection = .profile
                hasCompletedIntroduction = true
            })
        }
        .task {
            await accountModel.restore()
            await dashboardViewModel.loadWalkingPlan()
            await sessionViewModel.loadHistory()
        }
    }

    private var bottomNavigation: some View {
        HStack(alignment: .center, spacing: 0) {
            navigationButton(.home)
            navigationButton(.care)
            Button {
                selection = .walk
                if sessionViewModel.isActive || sessionViewModel.start(plan: dashboardViewModel.snapshot.walkingPlan) {
                    showingWalkingSession = true
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(CardioSafeTheme.navy, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 2))
                    Text(sessionViewModel.isActive ? "Resume" : "Walk")
                        .font(.caption2.bold())
                        .foregroundStyle(CardioSafeTheme.teal)
                }
                .frame(maxWidth: .infinity, minHeight: 76)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sessionViewModel.isActive ? "Return to walking session" : "Start walking")
            .accessibilityHint("Opens the full-screen walking map")
            navigationButton(.records)
            navigationButton(.profile)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.primary.opacity(0.06)))
        .padding(.horizontal, 12).padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    private func navigationButton(_ tab: AppTab) -> some View {
        Button { selection = tab } label: {
            VStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 21, weight: selection == tab ? .semibold : .regular))
                Text(tab.rawValue).font(.caption2.weight(selection == tab ? .semibold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selection == tab ? CardioSafeTheme.teal : .secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        if tab == .home {
            DashboardView(
                viewModel: dashboardViewModel,
                sessionViewModel: sessionViewModel,
                onSelectTab: { selection = $0 },
                onEmergency: { showingEmergency = true }
            )
        } else if tab == .profile {
            AccountView(model: accountModel, sessionModel: sessionViewModel)
        } else if tab == .care {
            CareFinderView()
        } else if tab == .records {
            RecordsView(sessionModel: sessionViewModel)
        } else if tab == .walk {
            WalkingOverviewView(viewModel: dashboardViewModel, sessionViewModel: sessionViewModel)
        } else {
            ContentUnavailableView(tab.rawValue, systemImage: tab.symbol,
                                   description: Text(tab.explanation))
        }
    }
}

#Preview {
    ContentView(
        viewModel: DashboardViewModel(planStore: CoreDataWalkingPlanStore(inMemory: true), ownerID: "preview"),
        sessionViewModel: WalkingSessionViewModel()
    )
}
