import SwiftUI

struct ContentView: View {
    @State private var selection: AppTab = .home
    @State private var showingEmergency = false
    @State private var dashboardViewModel = DashboardViewModel()

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.rawValue, systemImage: tab.symbol, value: tab) {
                    NavigationStack {
                        destination(for: tab)
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
        .tabViewStyle(.sidebarAdaptable)
        .tint(CardioSafeTheme.teal)
        .sheet(isPresented: $showingEmergency) { EmergencyHelpView() }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        if tab == .home {
            DashboardView(
                viewModel: dashboardViewModel,
                onSelectTab: { selection = $0 },
                onEmergency: { showingEmergency = true }
            )
        } else if tab == .walk {
            WalkingOverviewView(viewModel: dashboardViewModel)
        } else {
            ContentUnavailableView(tab.rawValue, systemImage: tab.symbol,
                                   description: Text(tab.explanation))
        }
    }
}

#Preview {
    ContentView()
}
