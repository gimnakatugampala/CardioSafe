import SwiftUI

struct AppSettingsView: View {
    @AppStorage("appearancePreference") private var appearance = "system"
    @Environment(AppLockViewModel.self) private var appLock
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    @State private var settingsError = false
    @State private var appearanceError: String?
    @State private var showingIntroduction = false

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: Binding(get: { appearance }, set: { value in
                    do {
                        try AccountAppearanceStore().save(value, owner: AccountDataScope.ownerID)
                        appearance = value; appearanceError = nil
                    } catch { appearanceError = "Appearance could not be saved. Please retry." }
                })) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Light", systemImage: "sun.max").tag("light")
                    Label("Dark", systemImage: "moon").tag("dark")
                }
                if let appearanceError { Text(appearanceError).font(.caption).foregroundStyle(.red) }
            } header: { Text("Display") } footer: {
                Text("System follows your iPhone’s appearance. Patient accounts sync this choice across devices; guest choices stay on this device.")
            }
            Section {
                Toggle(isOn: Binding(get: { appLock.isEnabled }, set: { enabled in
                    Task { await appLock.setEnabled(enabled) }
                })) {
                    Label("App lock", systemImage: "faceid")
                }.disabled(appLock.isBusy)
                if appLock.isBusy { ProgressView("Authenticating…") }
                if let error = appLock.errorMessage { Text(error).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Privacy") } footer: {
                Text("Require Face ID, Touch ID or your device passcode after CardioSafe enters the background. Authentication is required to turn this on or off. Your active walk keeps tracking while locked.")
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
            Section {
                NavigationLink { WalkingReminderSettingsView() } label: {
                    Label("Walking reminders", systemImage: "bell.badge")
                }
            }
            Section {
                NavigationLink("Voice & Siri") { WalkingVoiceControlsView() }
            }
            Section("Your data") {
                Label("Walking records sync with your account", systemImage: "iphone")
                Text("Saved sessions include walking time, rest breaks, recorded routes and available health readings. Signed-in patient accounts back these records up privately to Firebase. PDFs remain local.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label("Hospital queues use Firebase", systemImage: "building.2")
                Text("Your account provides access to published department counts. Demonstration queues are labelled in Care Finder.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                Button { showingIntroduction = true } label: {
                    Label("Replay introduction", systemImage: "sparkles.rectangle.stack")
                }
            }
            Section("About") {
                LabeledContent("App", value: "CardioSafe")
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
        .scrollContentBackground(.hidden)
        .background(CardioSafeTheme.background(for: scheme))
        .tint(CardioSafeTheme.accent(for: scheme))
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingIntroduction) {
            OnboardingView(account: nil, onFinish: { showingIntroduction = false }, onSetUpProfile: { showingIntroduction = false }, showsProfileSetup: false)
        }
        .alert("Settings couldn’t open", isPresented: $settingsError) {
            Button("OK", role: .cancel) {}
        } message: { Text("Open the Settings app on your iPhone and select CardioSafe.") }
    }
}
