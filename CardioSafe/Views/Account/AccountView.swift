import SwiftUI

struct AccountView: View {
    let model: AccountViewModel
    let sessionModel: WalkingSessionViewModel
    @State private var showingSignIn = false
    var body: some View {
        Form {
            if let account = model.account {
                Section("Your account") {
                    LabeledContent("Email", value: account.email)
                    LabeledContent("Role", value: account.role == .staff ? "Hospital staff" : "Patient")
                    LabeledContent("Email verified", value: account.isEmailVerified ? "Yes" : "Not yet")
                    if !account.isEmailVerified {
                        Button("Send verification email") { Task { await model.sendVerification() } }
                    }
                    Button("Refresh account") { Task { await model.restore() } }
                }
                if account.canManageQueues {
                    Section("Hospital staff") {
                        NavigationLink("Manage department queues") { StaffHospitalListView(account: account) }
                    }
                } else if account.role == .staff {
                    Section { Text("Staff access requires a verified email and a hospital assignment.").font(.subheadline) }
                }
                Section {
                    Button("Sign out", role: .destructive) { model.signOut() }
                        .disabled(sessionModel.isActive)
                    if sessionModel.isActive { Text("Finish your active walk before signing out.").font(.caption) }
                }
            } else {
                Section("Account") {
                    Text("Sign in to access hospital queue updates.")
                    Button("Sign in or create account") { showingSignIn = true }
                        .disabled(!model.isConfigured)
                    if !model.isConfigured {
                        Text("Account services aren’t connected on this installation yet.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Walking") {
                NavigationLink("Walking plan and history") {
                    WalkingAccountLinks(sessionModel: sessionModel)
                }
                Text("Walking and health records currently stay on this device; cloud account sync is not enabled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = model.message { Section { Text(message).font(.subheadline) } }
            if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
        }
        .disabled(model.isBusy)
        .overlay { if model.isBusy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .sheet(isPresented: $showingSignIn) { AccountSignInView(model: model) }
    }
}

private struct WalkingAccountLinks: View {
    let sessionModel: WalkingSessionViewModel
    var body: some View {
        List {
            NavigationLink("Walking history") { WalkingHistoryView(viewModel: sessionModel) }
            Text("Your walking plan is available from Walk after minimising a session.").font(.caption)
        }
        .navigationTitle("Walking").navigationBarTitleDisplayMode(.inline)
    }
}

struct AccountSignInView: View {
    let model: AccountViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var registering = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Account action", selection: $registering) {
                        Text("Sign in").tag(false); Text("Create account").tag(true)
                    }.pickerStyle(.segmented)
                    TextField("Email", text: $email).textContentType(.emailAddress)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(registering ? .newPassword : .password)
                }
                if registering { Section { Text("New accounts start as patients. Hospital staff access is assigned by an administrator.").font(.caption) } }
                if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(model.isBusy ? "Please wait…" : (registering ? "Create patient account" : "Sign in")) {
                        Task {
                            if await model.authenticate(email: email, password: password, registering: registering) {
                                password = ""; dismiss()
                            }
                        }
                    }.disabled(model.isBusy || !model.isConfigured)
                }
            }
            .disabled(model.isBusy)
            .navigationTitle(registering ? "Create account" : "Welcome back").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { password = ""; dismiss() }.disabled(model.isBusy) } }
            .interactiveDismissDisabled(model.isBusy)
        }
    }
}
