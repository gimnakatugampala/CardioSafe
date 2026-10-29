//
//  CardioSafeApp.swift
//  CardioSafe
//
//  Created by Gimna Katugampala on 2026-10-16.
//

import SwiftUI
import UserNotifications
import FirebaseFirestore

@main
struct CardioSafeApp: App {
    init() {
        FirebaseSetup.configure()
        UNUserNotificationCenter.current().delegate = WalkingNotificationDelegate.shared
    }
    @State private var databaseReady = false
    @State private var databasePreparing = false
    @State private var startupError: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var arrivalReminder = HospitalArrivalViewModel()
    @State private var appLock = AppLockViewModel()
    @State private var dispatchDemo = DispatchDemoViewModel()
    @State private var dashboardViewModel = DashboardViewModel(
        planStore: AccountWalkingPlanStore(), ownerID: "guest", healthService: HealthKitDashboardService()
    )
    @State private var walkingSessionViewModel = WalkingSessionViewModel(store: AccountWalkingSessionStore(), ownerID: "guest")
    var body: some Scene {
        WindowGroup {
            Group {
            if !databaseReady {
                VStack {
                    if let startupError { Text(startupError); Button("Retry") { Task { await prepareDatabase() } } }
                    else { ProgressView("Preparing CardioSafe…") }
                }.task { await prepareDatabase() }
            } else {
            ContentView(viewModel: dashboardViewModel, sessionViewModel: walkingSessionViewModel)
                .environment(dispatchDemo)
                .environment(arrivalReminder)
                .environment(appLock)
                .accessibilityHidden(appLock.needsShield)
                .background {
                    AppLockShield(model: appLock, isVisible: appLock.needsShield)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active: appLock.becameActive(); arrivalReminder.refresh()
                    case .inactive: appLock.becameInactive()
                    case .background: appLock.enteredBackground()
                    @unknown default: appLock.becameInactive()
                    }
                }
            }
            }
        }
    }
    @MainActor private func prepareDatabase() async {
        guard !databasePreparing, !databaseReady else { return }
        databasePreparing = true
        defer { databasePreparing = false }
        startupError = nil
        do {
            if UserDefaults.standard.bool(forKey: "clearFirestoreAfterDeletion") {
                try await Firestore.firestore().clearPersistence()
                UserDefaults.standard.removeObject(forKey: "clearFirestoreAfterDeletion")
            }
            databaseReady = true
        } catch { startupError = "Device database cleanup could not finish. Close CardioSafe and retry." }
    }
}
