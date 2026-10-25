import SwiftUI

struct AppSettingsView: View {
    @AppStorage("appearancePreference") private var appearance = "system"
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    @State private var settingsError = false

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Light", systemImage: "sun.max").tag("light")
                    Label("Dark", systemImage: "moon").tag("dark")
                }
            } header: { Text("Display") } footer: {
                Text("System follows your iPhone’s appearance. Your choice is saved on this device.")
            }
            Section {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url) { opened in settingsError = !opened }
                } label: {
                    HStack {
                        Label("Open iOS settings", systemImage: "gear")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption)
                    }.padding(.vertical, 4)
                }
            } header: { Text("Permissions") } footer: {
                Text("Manage location and motion access in iOS Settings. Manage Health access in the Health app under your profile → Apps → CardioSafe. Available options depend on permissions already requested.")
            }
            Section("Your data") {
                Label("Walking records stay on this device", systemImage: "iphone")
                Text("Saved sessions include walking time, rest breaks, recorded routes and available health readings. Signing in does not upload or sync these records.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label("Hospital queues use Firebase", systemImage: "building.2")
                Text("Your account provides access to published department counts. Demonstration queues are labelled in Care Finder.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("App", value: "CardioSafe")
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
        .scrollContentBackground(.hidden)
        .background(CardioSafeTheme.background(for: scheme))
        .tint(CardioSafeTheme.teal)
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .alert("Settings couldn’t open", isPresented: $settingsError) {
            Button("OK", role: .cancel) {}
        } message: { Text("Open the Settings app on your iPhone and select CardioSafe.") }
    }
}
