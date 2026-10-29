import SwiftUI
import UIKit

struct AccountView: View {
    let model: AccountViewModel
    let sessionModel: WalkingSessionViewModel
    @State private var showingSignIn = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48)).foregroundStyle(CardioSafeTheme.teal)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.account == nil ? "Your care, connected" : "Your CardioSafe account")
                            .font(.title3.weight(.bold))
                        Text(model.account == nil ? "Manage your account and walking activity." : "Manage access, verification and activity.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 10)
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            if let account = model.account {
                if account.role == .patient {
                    Section {
                        NavigationLink { AccountSyncView() } label: { Label("Account sync", systemImage: "icloud") }
                    }
                }
                Section {
                    NavigationLink { PatientProfileView(accountID: account.id).id(account.id) } label: {
                        Label("My details", systemImage: "person.text.rectangle")
                    }
                    Text("Personal details and emergency contact · Synced to your account")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup("Account & verification") {
                    LabeledContent("Email", value: account.email)
                    LabeledContent("Role", value: account.role == .staff ? "Hospital staff" : "Patient")
                    LabeledContent("Email verified", value: account.isEmailVerified ? "Yes" : "Not yet")
                    if !account.isEmailVerified {
                        Button { Task { await model.sendVerification() } } label: {
                            Label(model.isBusy ? "Sending…" : "Send verification email", systemImage: "envelope.badge")
                        }
                    }
                    Button("Refresh account") { Task { await model.restore() } }
                    }
                }
                if account.canManageQueues {
                    Section("Hospital staff") {
                        NavigationLink("Hospital workspace") { StaffHospitalListView(account: account) }
                    }
                } else if account.role == .staff {
                    Section { Text("Staff access requires a verified email and a hospital assignment.").font(.subheadline) }
                }
                if account.role == .patient {
                    Section { NavigationLink("Account & data controls") { AccountDataControlsView() } }
                }
                Section {
                    Button("Sign out", role: .destructive) { model.signOut() }
                        .disabled(sessionModel.isActive)
                    if sessionModel.isActive { Text("Finish your active walk before signing out.").font(.caption) }
                }
            } else {
                Section("Account") {
                    Text("Sign in to access hospital queue updates.")
                    Button { showingSignIn = true } label: {
                        HStack {
                            Text("Sign in or create account").fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }.padding(.vertical, 8)
                    }.tint(CardioSafeTheme.accent(for: scheme))
                        .disabled(!model.isConfigured)
                    if !model.isConfigured {
                        Text("Account services aren’t connected on this installation yet.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                NavigationLink { AppSettingsView() } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            if let message = model.message { Section { Text(message).font(.subheadline) } }
            if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
        }
        .scrollContentBackground(.hidden)
        .background(CardioSafeTheme.background(for: scheme))
        .tint(CardioSafeTheme.accent(for: scheme))
        .disabled(model.isBusy)
        .overlay { if model.isBusy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(notice.isError ? CardioSafeTheme.alert : CardioSafeTheme.teal)
                    Text(notice.text).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                    Button { model.dismissNotice() } label: {
                        Image(systemName: "xmark").font(.caption.bold()).frame(width: 28, height: 28)
                    }.accessibilityLabel("Dismiss notification")
                }
                .padding(16)
                .background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(CardioSafeTheme.teal.opacity(0.18), lineWidth: 1) }
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                .padding(.horizontal, 16).padding(.top, 8)
                .accessibilityElement(children: .contain)
            }
        }
        .onChange(of: model.notice?.id) { _, _ in
            if let notice = model.notice { UIAccessibility.post(notification: .announcement, argument: notice.text) }
        }
        .task(id: model.notice?.id) {
            guard model.notice != nil else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            model.dismissNotice()
        }
        .sheet(isPresented: $showingSignIn) { AccountSignInView(model: model) }
    }
}

struct AccountSignInView: View {
    let model: AccountViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var registering = false
    @State private var submitted = false
    @State private var showingPasswordRecovery = false
    @Namespace private var accountTabAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case email, password, confirmation }

    private var passwordMismatch: Bool {
        registering && !confirmPassword.isEmpty && password != confirmPassword
    }
    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty && (!registering || (password.count >= 8 && password == confirmPassword))
            && model.isConfigured && !model.isBusy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "heart.text.clipboard")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(CardioSafeTheme.teal)
                            .frame(width: 62, height: 62)
                            .background(CardioSafeTheme.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                        Text(registering ? "Start with your account." : "Welcome back.")
                            .font(.largeTitle.bold()).tracking(-0.8)
                        Text(registering ? "Connect with care and keep hospital updates close." : "Sign in to view hospital queues and manage your account.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        accountTab("Sign in", icon: "person.crop.circle", registration: false)
                        accountTab("Create account", icon: "person.crop.circle.badge.plus", registration: true)
                    }
                    .padding(5)
                    .background(CardioSafeTheme.teal.opacity(0.07), in: Capsule())
                    .overlay { Capsule().stroke(CardioSafeTheme.teal.opacity(0.12), lineWidth: 1) }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Account action")

                    VStack(alignment: .leading, spacing: 22) {
                        input("Email address", icon: "envelope") {
                            TextField("you@example.com", text: $email)
                                .textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focusedField, equals: .email).submitLabel(.next)
                                .onSubmit { focusedField = .password }
                        }
                        input("Password", icon: "lock") {
                            SecureField(registering ? "At least 8 characters" : "Enter your password", text: $password)
                                .textContentType(registering ? .newPassword : .password)
                                .focused($focusedField, equals: .password)
                                .submitLabel(registering ? .next : .go)
                                .onSubmit { if registering { focusedField = .confirmation } else { authenticate() } }
                        }
                        if registering {
                            input("Confirm password", icon: "lock.shield") {
                                SecureField("Re-enter your password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .confirmation).submitLabel(.go)
                                    .onSubmit { authenticate() }
                            }
                            if passwordMismatch {
                                Label("Passwords don’t match.", systemImage: "exclamationmark.circle")
                                    .font(.caption).foregroundStyle(CardioSafeTheme.alert)
                                    .accessibilityIdentifier("passwordMismatch")
                            }
                        }
                    }
                    if !registering {
                        Button("Forgot password?") { focusedField = nil; showingPasswordRecovery = true }
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }
                    if submitted, let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline).foregroundStyle(CardioSafeTheme.alert)
                    }
                    VStack(spacing: 16) {
                        Button(action: authenticate) {
                            HStack(spacing: 10) {
                                if model.isBusy { ProgressView().tint(.white) }
                                Text(model.isBusy ? "Please wait…" : (registering ? "Create patient account" : "Sign in"))
                                    .font(.headline)
                                if !model.isBusy { Image(systemName: "arrow.right") }
                            }.frame(maxWidth: .infinity).padding(.vertical, 17)
                        }
                        .buttonStyle(.plain).foregroundStyle(.white)
                        .background(CardioSafeTheme.teal.opacity(canSubmit ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 16))
                        .disabled(!canSubmit)
                        if registering {
                            Label("Patient account · Staff access is assigned by an administrator.", systemImage: "person.badge.shield.checkmark")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .background(CardioSafeTheme.background(for: scheme))
            .foregroundStyle(CardioSafeTheme.text(for: scheme))
            .scrollDismissesKeyboard(.interactively)
            .disabled(model.isBusy)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { clearPasswords(); dismiss() }.disabled(model.isBusy)
                }
            }
            .interactiveDismissDisabled(model.isBusy)
            .onChange(of: registering) { _, _ in clearPasswords(); submitted = false; focusedField = nil }
            .onDisappear { clearPasswords() }
            .sheet(isPresented: $showingPasswordRecovery) { PasswordRecoveryView(email: email) }
        }.tint(CardioSafeTheme.accent(for: scheme))
    }

    private func accountTab(_ title: String, icon: String, registration: Bool) -> some View {
        let selected = registering == registration
        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                registering = registration
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.subheadline.weight(.medium))
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.white : CardioSafeTheme.text(for: scheme).opacity(0.65))
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 4)
            .background {
                if selected {
                    Capsule().fill(CardioSafeTheme.teal)
                        .matchedGeometryEffect(id: "selectedAccountTab", in: accountTabAnimation)
                        .shadow(color: CardioSafeTheme.teal.opacity(0.18), radius: 5, y: 3)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func input<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
                content()
            }
            .padding(16)
            .background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1) }
        }
    }
    private func authenticate() {
        guard canSubmit else { return }
        submitted = true
        focusedField = nil
        Task {
            if await model.authenticate(email: email, password: password, registering: registering) {
                clearPasswords(); dismiss()
            }
        }
    }
    private func clearPasswords() { password = ""; confirmPassword = "" }
}
