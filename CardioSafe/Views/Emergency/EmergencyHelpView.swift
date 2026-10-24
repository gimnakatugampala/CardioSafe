import SwiftUI

struct EmergencyHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Emergency assistance") {
                    Label("Emergency calling is not connected in this build.", systemImage: "phone")
                    Text("For urgent assistance, use your phone to contact local emergency services directly.")
                }
                Section("Your location") { Text("Location is not connected yet.") }
                Section("CardioSafe Guardian") {
                    Text("Dispatch simulation is not set up yet.")
                    Text("No hospital has been notified and no ambulance has been requested.")
                }
            }
            .navigationTitle("Emergency Help")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
