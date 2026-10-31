import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedIntroduction") private var hasCompletedIntroduction = false
    @AppStorage("appearancePreference") private var appearance = "system"
    @Environment(DispatchDemoViewModel.self) private var dispatch
    @Environment(AppLockViewModel.self) private var appLock
    @State private var shouldShowRestoredSOS = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var facilityAlerts = FacilitySOSAlerts()
    @State private var notificationRouter = SOSNotificationRouter.shared
    @State private var notificationDestination: SOSNotificationRoute?
    @State private var documentRouter = DocumentReminderRouter.shared
    @State private var reminderDestination: DocumentReminderRoute?
    @State private var selection: AppTab = .home
    @State private var accountModel = AccountViewModel(service: FirebaseAccountService())
    @State private var accountRestored = false
    @State private var dataReadyID: String?
    @State private var accountSync = FirebaseAccountSync.shared
    @State private var showingEmergency = false
    @State private var showingEmergencyContacts = false
    @State private var showingWalkingSession = false
    @State private var dashboardViewModel: DashboardViewModel
    @State private var sessionViewModel: WalkingSessionViewModel

    init(viewModel: DashboardViewModel, sessionViewModel: WalkingSessionViewModel) {
        _dashboardViewModel = State(initialValue: viewModel)
        _sessionViewModel = State(initialValue: sessionViewModel)
    }

    private var accountDataKey: String { "\(accountModel.account?.id ?? "guest")-\(accountModel.account?.role.rawValue ?? "guest")" }

    var body: some View { accountLifecycle }

    private var workspace: some View {
        VStack(spacing: 0) {
            if dataReadyID == accountDataKey, accountModel.account?.usesHospitalWorkspace != true {
                if sessionViewModel.needsRecoveryDecision { recoveryBanner }
                else if let error = sessionViewModel.recoveryError {
                    Label(error, systemImage: "exclamationmark.circle").font(.footnote).padding()
                }
            }
            if AccountDeletionViewModel.shared.blocksDataAccess {
                NavigationStack { AccountDataControlsView() }
            } else if !accountRestored || dataReadyID != accountDataKey {
                ProgressView("Opening CardioSafe…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if accountModel.account?.usesHospitalWorkspace == true {
                HospitalWorkspaceView(model: accountModel)
            } else {
                patientTabs.id(accountModel.account?.id ?? "guest")
            }
        }
        .environment(sessionViewModel)
        .environment(facilityAlerts)
        .environment(accountSync)
        .fullScreenCover(isPresented: $showingWalkingSession) {
            WalkingSessionView(viewModel: sessionViewModel, allowsAutomaticSOS: accountModel.account?.role == .patient)
        }
        .safeAreaInset(edge: .top) {
            if !showingWalkingSession { AutomaticSOSBanner(model: sessionViewModel.automaticSOS) }
        }
        .tint(CardioSafeTheme.accent(for: scheme))
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }

    private var routedContent: some View {
        workspace
        .sheet(isPresented: $showingEmergency) { EmergencyHelpView() }
        .sheet(isPresented: $showingEmergencyContacts) { EmergencyContactView() }
        .sheet(item: $notificationDestination) { route in
            NavigationStack {
                if route.isAllowed(for: accountModel.account), !appLock.needsShield {
                    FacilityRequestsView(hospitalID: route.hospitalID)
                        .toolbar { ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { notificationDestination = nil }
                        } }
                } else {
                    ContentUnavailableView("Staff access required", systemImage: "lock", description: Text("Unlock CardioSafe and sign in with assigned hospital staff access."))
                }
            }
        }
        .onChange(of: showingEmergency) { _, showing in if !showing { presentNotificationIfPossible() } }
        .onChange(of: showingWalkingSession) { _, showing in if !showing { presentNotificationIfPossible() } }
        .sheet(item: $reminderDestination) { route in
            NavigationStack {
                if route.ownerID == (accountModel.account?.id ?? "guest"), accountModel.account?.usesHospitalWorkspace != true, !appLock.needsShield {
                    ReminderDocumentDestination(documentID: route.documentID)
                } else {
                    ContentUnavailableView("Account changed", systemImage: "lock")
                }
            }
        }
        .onChange(of: documentRouter.pending) { _, _ in presentDocumentReminderIfPossible() }
        .onChange(of: dataReadyID) { _, _ in presentDocumentReminderIfPossible() }
        .onChange(of: showingEmergencyContacts) { _, _ in presentDocumentReminderIfPossible() }
        .onChange(of: showingEmergency) { _, _ in presentDocumentReminderIfPossible() }
        .onChange(of: showingWalkingSession) { _, _ in presentDocumentReminderIfPossible() }
        .onChange(of: appLock.needsShield) { _, _ in presentDocumentReminderIfPossible() }
        .onChange(of: hasCompletedIntroduction) { _, _ in presentDocumentReminderIfPossible() }
    }

    private var accountLifecycle: some View {
        routedContent
        .task(id: scenePhase) {
            while !Task.isCancelled {
                if AccountDeletionViewModel.shared.blocksDataAccess {
                    sessionViewModel.automaticSOS.setEnabled(false)
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    continue
                }
                let eligible = scenePhase == .active && !appLock.needsShield && sessionViewModel.isActive
                    && accountModel.account?.role == .patient && dataReadyID == accountDataKey
                if scenePhase == .active, !appLock.needsShield, dataReadyID == accountDataKey,
                   accountModel.account?.usesHospitalWorkspace != true,
                   let action = WalkingVoiceQueue.take(owner: accountModel.account?.id ?? "guest") {
                    _ = WalkingVoiceExecutor.apply(action, session: sessionViewModel, plan: dashboardViewModel.snapshot.walkingPlan)
                    if sessionViewModel.isActive { showingWalkingSession = true }
                }
                let health = sessionViewModel.healthModel
                if sessionViewModel.automaticSOS.tick(bpm: health.heartRate, sampleDate: health.heartRateDate,
                    eligible: eligible, busy: dispatch.isActive || dispatch.isRestoring) {
                    dispatch.start()
                    if !showingWalkingSession { showingEmergency = true }
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { sessionViewModel.checkpoint(); sessionViewModel.automaticSOS.setEnabled(false) }
        }
        .onChange(of: appLock.needsShield) { _, shield in
            if shield { sessionViewModel.automaticSOS.setEnabled(false) }
        }
        .onChange(of: notificationRouter.pending) { _, _ in presentNotificationIfPossible() }
        .onChange(of: accountModel.account) { _, account in
            facilityAlerts.configure(account: account)
            sessionViewModel.automaticSOS.setEnabled(false)
            showingEmergency = false
            showingWalkingSession = false
            selection = .home
            showingEmergencyContacts = false
            notificationDestination = nil
            reminderDestination = nil
            presentNotificationIfPossible()
        }
        .fullScreenCover(isPresented: Binding(get: { accountRestored && !hasCompletedIntroduction && accountModel.account?.usesHospitalWorkspace != true }, set: { _ in })) {
            OnboardingView(account: accountModel.account, onFinish: {
                hasCompletedIntroduction = true
            }, onSetUpProfile: {
                selection = .profile
                hasCompletedIntroduction = true
            })
        }
        .task(id: "\(accountRestored)-\(accountDataKey)") {
            guard accountRestored, !AccountDeletionViewModel.shared.blocksDataAccess else { return }
            let account = accountModel.account
            let owner: String? = account?.usesHospitalWorkspace == false ? account?.id : nil
            dataReadyID = nil
            AccountDataScope.ownerID = owner
            if (UserDefaults.standard.string(forKey: "walkingVoiceOwner") ?? "guest") != (owner ?? "guest") {
                UserDefaults.standard.removeObject(forKey: WalkingVoiceQueue.key)
            }
            UserDefaults.standard.set(owner ?? "guest", forKey: "walkingVoiceOwner")
            await sessionViewModel.useAccount(owner ?? "guest")
            do {
                if let owner {
                    if ProcessInfo.processInfo.arguments.contains("-ImportExistingDeviceRecords") { LegacyAccountMigration.approve(owner: owner) }
                    try await LegacyAccountMigration.claim(for: owner)
                    try await LegacyAccountMigration.claimWalkingPlan(for: owner)
                }
            }
            catch { accountSync.migrationError = "Some existing device records couldn’t be linked. Original records are preserved; retry from Account sync." }
            guard !Task.isCancelled else { return }
            await accountSync.start(owner: owner)
            guard !Task.isCancelled else { return }
            do {
                let preferences = AccountAppearanceStore()
                if let owner { try preferences.migrateExistingChoice(owner: owner) }
                appearance = try preferences.load(owner: owner)
            }
            catch { appearance = "system"; accountSync.migrationError = "Appearance could not be restored. Retry Account sync." }
            await dashboardViewModel.useAccount(owner ?? "guest")
            guard !Task.isCancelled else { return }
            await sessionViewModel.loadHistory()
            dataReadyID = accountDataKey
            showingEmergency = false
            shouldShowRestoredSOS = false
            let patientID = accountModel.account?.usesHospitalWorkspace == true ? nil : accountModel.account?.id
            let shouldResume = await dispatch.restoreForAccount(ownerID: patientID)
            guard !Task.isCancelled else { return }
            shouldShowRestoredSOS = shouldResume
            presentRestoredSOSIfPossible()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountDataRestored)) { notification in
            guard !AccountDeletionViewModel.shared.blocksDataAccess,
                  notification.object as? String == accountModel.account?.id else { return }
            Task {
                await sessionViewModel.loadHistory()
                if let account = accountModel.account, !account.usesHospitalWorkspace {
                    let owner = account.id
                    await dashboardViewModel.refreshSyncedWalkingPlan(for: owner)
                    guard owner == accountModel.account?.id else { return }
                    do { appearance = try AccountAppearanceStore().load(owner: owner) }
                    catch { accountSync.migrationError = "Appearance could not be restored. Retry Account sync." }
                }
            }
        }
        .onChange(of: appLock.needsShield) { _, _ in presentRestoredSOSIfPossible(); presentNotificationIfPossible() }
        .onChange(of: hasCompletedIntroduction) { _, _ in presentRestoredSOSIfPossible(); presentNotificationIfPossible() }
        .task {
            await accountModel.restore()
            accountRestored = true
            facilityAlerts.configure(account: accountModel.account)
            presentNotificationIfPossible()
        }
    }

    private var recoveryBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Unfinished walk found", systemImage: "figure.walk.circle").font(.headline)
            if let date = sessionViewModel.recoveryCheckpoint {
                Text("Saved through \(date.formatted(.dateTime.day().month().hour().minute().second())). Time and movement after that point were not recorded.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Button("Resume walk") {
                    if sessionViewModel.resumeRecoveredWalk() { showingWalkingSession = true }
                }.buttonStyle(.borderedProminent)
                Button("Finish and save") {
                    if sessionViewModel.finishRecoveredWalk() { showingWalkingSession = true }
                }.buttonStyle(.bordered)
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(CardioSafeTheme.surface(for: scheme))
    }

    @ViewBuilder private var patientTabs: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                List {
                    Section("CardioSafe") {
                        ForEach(AppTab.allCases) { tab in
                            Button { selection = tab } label: {
                                Label(tab.rawValue, systemImage: tab.symbol)
                                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            }
                            .listRowBackground(selection == tab ? CardioSafeTheme.accent(for: scheme).opacity(0.14) : Color.clear)
                            .accessibilityAddTraits(selection == tab ? .isSelected : [])
                        }
                    }
                    Section {
                        Button {
                            selection = .walk
                            if sessionViewModel.isActive || sessionViewModel.start(plan: dashboardViewModel.snapshot.walkingPlan) {
                                showingWalkingSession = true
                            }
                        } label: {
                            Label(sessionViewModel.isActive ? "Return to walk" : "Start walking", systemImage: "figure.walk.circle.fill")
                                .font(.headline).padding(.vertical, 6)
                        }
                        Button { showingEmergencyContacts = true } label: {
                            Label("Emergency Help", systemImage: "sos.circle").foregroundStyle(.red)
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("CardioSafe")
                .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 290)
            } detail: {
                NavigationStack {
                    destination(for: selection)
                        .navigationTitle(selection == .home ? "" : selection.rawValue)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button { showingEmergencyContacts = true } label: {
                                    Label("Emergency Help", systemImage: "sos.circle")
                                }.tint(.red)
                            }
                        }
                }.id(selection)
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            compactPatientTabs
        }
    }

    private var compactPatientTabs: some View {
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
                                    Button { showingEmergencyContacts = true } label: {
                                        Label("Emergency Help", systemImage: "sos.circle")
                                    }
                                    .tint(.red)
                                }
                            }
                    }
                    // The custom bar must be inset *inside* each tab so scroll content
                    // (Home cards, lists, charts) stops above it instead of sliding underneath.
                    .safeAreaInset(edge: .bottom, spacing: 0) { bottomNavigation }
                }
            }
        }
    }

    private func presentNotificationIfPossible() {
        guard !appLock.needsShield, (hasCompletedIntroduction || accountModel.account?.usesHospitalWorkspace == true), !showingEmergency,
              !showingWalkingSession, let account = accountModel.account,
              let route = notificationRouter.pending else { return }
        notificationRouter.pending = nil
        guard route.isAllowed(for: account) else { return }
        selection = .profile
        notificationDestination = route
    }

    private func presentDocumentReminderIfPossible() {
        guard accountRestored, dataReadyID == accountDataKey, !appLock.needsShield, hasCompletedIntroduction,
              !showingEmergency, !showingEmergencyContacts, !showingWalkingSession,
              notificationDestination == nil, reminderDestination == nil,
              let route = documentRouter.pending else { return }
        documentRouter.pending = nil
        guard accountModel.account?.usesHospitalWorkspace != true,
              route.ownerID == (accountModel.account?.id ?? "guest") else { return }
        selection = .records
        reminderDestination = route
    }

    private func presentRestoredSOSIfPossible() {
        guard accountModel.account?.usesHospitalWorkspace != true, shouldShowRestoredSOS, !appLock.needsShield, hasCompletedIntroduction else { return }
        shouldShowRestoredSOS = false
        showingEmergency = true
    }

    @ViewBuilder private var bottomNavigation: some View {
        if typeSize.isAccessibilitySize {
            HStack(spacing: 16) {
                Menu {
                    ForEach([AppTab.home, .care, .records, .profile], id: \.self) { tab in
                        Button { selection = tab } label: { Label(tab.rawValue, systemImage: tab.symbol) }
                    }
                } label: {
                    Label(selection.rawValue, systemImage: "line.3.horizontal")
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityLabel("Navigate, \(selection.rawValue)")
                .accessibilityHint("Choose Home, Find Care, Records or Profile")
                Button {
                    selection = .walk
                    if sessionViewModel.isActive || sessionViewModel.start(plan: dashboardViewModel.snapshot.walkingPlan) {
                        showingWalkingSession = true
                    }
                } label: {
                    Image(systemName: "figure.walk").font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 56, height: 56)
                        .background(CardioSafeTheme.navy, in: Circle())
                }
                .accessibilityLabel(sessionViewModel.isActive ? "Return to walking session" : "Start walking")
            }
            .padding(16).foregroundStyle(CardioSafeTheme.accent(for: scheme))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 12).padding(.bottom, 4)
        } else {
            standardBottomNavigation
        }
    }

    private var standardBottomNavigation: some View {
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
                        .foregroundStyle(CardioSafeTheme.accent(for: scheme))
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
            .foregroundStyle(selection == tab ? CardioSafeTheme.accent(for: scheme) : .secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        if tab == .home {
            DashboardView(
                viewModel: dashboardViewModel,
                sessionViewModel: sessionViewModel,
                onSelectTab: { selection = $0 },
                onEmergency: { showingEmergency = true },
                onEmergencyContacts: { showingEmergencyContacts = true }
            )
        } else if tab == .profile {
            AccountView(model: accountModel, sessionModel: sessionViewModel)
        } else if tab == .care {
            CareFinderView()
        } else if tab == .records {
            RecordsView(sessionModel: sessionViewModel, ownerID: accountModel.account?.id)
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
