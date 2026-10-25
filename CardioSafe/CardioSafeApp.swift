//
//  CardioSafeApp.swift
//  CardioSafe
//
//  Created by Gimna Katugampala on 2026-10-16.
//

import SwiftUI

@main
struct CardioSafeApp: App {
    init() { FirebaseSetup.configure() }
    @State private var dashboardViewModel = DashboardViewModel(
        planStore: CoreDataWalkingPlanStore(), ownerID: "local-device", healthService: HealthKitDashboardService()
    )
    @State private var walkingSessionViewModel = WalkingSessionViewModel(store: CoreDataWalkingSessionStore(), ownerID: "local-device")
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: dashboardViewModel, sessionViewModel: walkingSessionViewModel)
        }
    }
}
