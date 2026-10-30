import SwiftUI

struct HospitalWorkspaceView: View {
    let model: AccountViewModel
    @State private var selection = 0
    @State private var selectedHospital = ""
    @State private var showingAccount = false
    var body: some View {
        Group {
            if let account = model.account, account.canManageQueues {
                let hospital = account.hospitalIDs.contains(selectedHospital) ? selectedHospital : account.hospitalIDs[0]
                TabView(selection: $selection) {
                    Tab("Overview", systemImage: "building.2", value: 0) {
                        NavigationStack {
                            HospitalOverviewView(account: account, hospitalID: hospital, selectedHospital: $selectedHospital,
                                                 openRequests: { selection = 1 }, openQueues: { selection = 2 })
                        }
                    }
                    Tab("SOS requests", systemImage: "sos.circle", value: 1) {
                        NavigationStack { FacilityRequestsView(hospitalID: hospital).id(hospital) }
                    }
                    Tab("Queues", systemImage: "person.3", value: 2) {
                        NavigationStack { StaffDepartmentView(hospitalID: hospital, account: account).id(hospital) }
                    }
                    Tab("Account", systemImage: "person.crop.circle", value: 3) {
                        HospitalAccountView(model: model, showsDone: false)
                    }
                }.toolbar(.visible, for: .tabBar)
            } else {
                NavigationStack {
                    ContentUnavailableView {
                        Label("Hospital access pending", systemImage: "building.2.crop.circle")
                    } description: {
                        Text("Verify your email and ask your administrator for a hospital assignment.")
                    } actions: {
                        Button("Open hospital account") { showingAccount = true }.buttonStyle(.borderedProminent)
                    }.navigationTitle("Hospital workspace")
                }
            }
        }
        .sheet(isPresented: $showingAccount) { HospitalAccountView(model: model) }
    }
}

struct HospitalAccountView: View {
    let model: AccountViewModel
    var showsDone = true
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLockViewModel.self) private var appLock
    @Environment(\.openURL) private var openURL
    @AppStorage("appearancePreference") private var appearance = "system"
    var body: some View {
        NavigationStack {
            Form {
                if let account = model.account {
                    Section("Hospital staff account") {
                        Label(account.email, systemImage: "person.crop.circle")
                        LabeledContent("Account type", value: "Hospital staff")
                        LabeledContent("Email verified", value: account.isEmailVerified ? "Yes" : "Not yet")
                        LabeledContent("Assigned hospitals", value: "\(account.hospitalIDs.count)")
                        Button("Refresh access") { Task { await model.restore() } }.disabled(model.isBusy)
                        if !account.isEmailVerified {
                            Button("Send verification email") { Task { await model.sendVerification() } }.disabled(model.isBusy)
                        }
                        if let notice = model.notice { Text(notice.text).font(.footnote) }
                        if let error = model.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                    }
                    Section("Workspace access") {
                        Text("Hospital access is assigned by an administrator. This workspace contains SOS requests and hospital queues.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Settings") {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    Toggle("App lock", isOn: Binding(get: { appLock.isEnabled }, set: { enabled in
                        Task { await appLock.setEnabled(enabled) }
                    })).disabled(appLock.isBusy)
                    if let error = appLock.errorMessage { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    Button("Notification settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Section("About") {
                    Text("Prototype using sample hospital data").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Sign out", role: .destructive) { model.signOut(); if model.account == nil { dismiss() } }
                        .disabled(model.isBusy)
                }
            }
            .navigationTitle("Hospital account").navigationBarTitleDisplayMode(.inline)
            .toolbar { if showsDone { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
        }
    }
}
