import SwiftUI

struct WalkingReminderSettingsView: View {
    @State private var model = WalkingReminderViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var settingsFailed = false
    var body: some View {
        Form {
            Section {
                Label("A reminder, on your schedule", systemImage: "bell.badge")
                    .font(.headline)
                Toggle("Daily reminder", isOn: Binding(get: { model.isEnabled }, set: { enabled in
                    Task { await model.setEnabled(enabled) }
                }))
                DatePicker("Reminder time", selection: Binding(get: {
                    Calendar.current.date(bySettingHour: model.hour, minute: model.minute, second: 0, of: .now) ?? .now
                }, set: { date in
                    model.hour = Calendar.current.component(.hour, from: date)
                    model.minute = Calendar.current.component(.minute, from: date)
                }), displayedComponents: .hourAndMinute)
                Button("Save reminder time") { Task { await model.saveTime() } }
            } footer: {
                Text("One reminder each day at your chosen local time. Follow the walking plan provided by your clinician. This reminder does not start a walking session.")
            }
            Section {
                Button { Task { await model.sendTest() } } label: {
                    Label("Send test notification", systemImage: "bell.and.waves.left.and.right")
                }
                Text("Schedules a demonstration notification in five seconds. It can appear while the app is open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = model.message { Section { Label(message, systemImage: "checkmark.circle").font(.subheadline) } }
            if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
            Section("iOS notification access") {
                LabeledContent("Permission", value: permissionText)
                Button("Open iOS settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url) { settingsFailed = !($0) }
                }
                Text("Focus, Scheduled Summary and banner settings can change when notifications appear. Reminders are local to this device; hospital push alerts are not connected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(model.isBusy)
        .overlay { if model.isBusy { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
        .scrollContentBackground(.hidden).background(CardioSafeTheme.background(for: scheme))
        .tint(scheme == .dark ? .cyan : CardioSafeTheme.teal)
        .navigationTitle("Walking reminders").navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
        .alert("Settings couldn’t open", isPresented: $settingsFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("Open iOS Settings → Notifications → CardioSafe.") }
    }
    private var permissionText: String {
        switch model.authorization {
        case .notDetermined: "Not requested"
        case .allowed: "Allowed"
        case .denied: "Off in iOS Settings"
        }
    }
}
