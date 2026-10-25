//
//  CardioSafeApp.swift
//  CardioSafe
//
//  Created by Gimna Katugampala on 2026-10-16.
//

import SwiftUI
import UserNotifications

@main
struct CardioSafeApp: App {
    init() {
        FirebaseSetup.configure()
        UNUserNotificationCenter.current().delegate = WalkingNotificationDelegate.shared
    }
    @Environment(\.scenePhase) private var scenePhase
    @State private var appLock = AppLockViewModel()
    @State private var dispatchDemo = DispatchDemoViewModel()
    @State private var dashboardViewModel = DashboardViewModel(
        planStore: CoreDataWalkingPlanStore(), ownerID: "local-device", healthService: HealthKitDashboardService()
    )
    @State private var walkingSessionViewModel = WalkingSessionViewModel(store: CoreDataWalkingSessionStore(), ownerID: "local-device")
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: dashboardViewModel, sessionViewModel: walkingSessionViewModel)
                .environment(dispatchDemo)
                .environment(appLock)
                .accessibilityHidden(appLock.needsShield)
                .background {
                    AppLockShield(model: appLock, isVisible: appLock.needsShield)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active: appLock.becameActive()
                    case .inactive: appLock.becameInactive()
                    case .background: appLock.enteredBackground()
                    @unknown default: appLock.becameInactive()
                    }
                }
        }
    }
}
