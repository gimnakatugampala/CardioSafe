import SwiftUI
import UIKit

struct AccountView: View {
    let model: AccountViewModel
    let sessionModel: WalkingSessionViewModel
    @State private var showingSignIn = false
    @State private var displayName = ""
    @State private var emergencyContactName = ""
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 60
    @Environment(\.colorScheme) private var scheme

    private var surface: Color { CardioSafeTheme.surface(for: scheme) }
    private var accent: Color { CardioSafeTheme.accent(for: scheme) }

    var body: some View {
        Form {
            headerSection
            if let account = model.account {
                signedInSections(account)
            } else {
                guestSections
            }
            if let message = model.message { Section { Text(message).font(.subheadline) } }
            if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
        }
        .frame(maxWidth: 900).frame(maxWidth: .infinity)
        .scrollContentBackground(.hidden)
        .background(CardioSafeTheme.background(for: scheme))
        .tint(accent)
        .disabled(model.isBusy)
        .overlay { if model.isBusy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .overlay(alignment: .top) { noticeBanner }
        .onChange(of: model.notice?.id) { _, _ in
            if let notice = model.notice { UIAccessibility.post(notification: .announcement, argument: notice.text) }
        }
        .task(id: model.notice?.id) {
            guard model.notice != nil else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            model.dismissNotice()
        }
        .onAppear { loadProfileSummary() }
        .onChange(of: model.account) { _, _ in loadProfileSummary() }
        .onReceive(NotificationCenter.default.publisher(for: .accountDataRestored)) { _ in loadProfileSummary() }
        .sheet(isPresented: $showingSignIn) { AccountSignInView(model: model) }
    }

    // MARK: Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                if let account = model.account {
                    HStack(spacing: 16) {
                        Text(initials(for: account))
                            .font(.title2.bold()).foregroundStyle(.white)
                            .frame(width: avatarSize, height: avatarSize)
                            .background(CardioSafeTheme.teal, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName.isEmpty ? account.email : displayName)
                                .font(.title3.weight(.bold)).lineLimit(2)
                            if !displayName.isEmpty {
                                Text(account.email).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        badge(account.role == .staff ? "Hospital staff" : "Patient",
                              symbol: account.role == .staff ? "building.2" : "person.fill", tint: accent)
                        badge(account.isEmailVerified ? "Email verified" : "Email not verified",
                              symbol: account.isEmailVerified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                              tint: account.isEmailVerified ? .green : .orange)
                    }
                    if account.role == .patient {
                        Divider()
                        Label(emergencyContactName.isEmpty
                              ? "No emergency contact added"
                              : "Emergency contact: \(emergencyContactName)",
                              systemImage: emergencyContactName.isEmpty ? "person.crop.circle.badge.questionmark" : "phone.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(emergencyContactName.isEmpty ? Color.secondary : CardioSafeTheme.text(for: scheme))
                    }
                } else {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44)).foregroundStyle(CardioSafeTheme.teal)
                            .frame(width: avatarSize, height: avatarSize)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You’re using CardioSafe as a guest").font(.title3.weight(.bold))
                            Text("Sign in to sync your records and see hospital queues.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Button { showingSignIn = true } label: {
                        HStack {
                            Text("Sign in or create account").fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .padding(.horizontal, 16).frame(minHeight: 50)
                        .foregroundStyle(.white)
                        .background(CardioSafeTheme.teal.opacity(model.isConfigured ? 1 : 0.45),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isConfigured)
                    if !model.isConfigured {
                        Text("Account services aren’t connected on this installation yet.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.05)))
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    // MARK: Signed in

    @ViewBuilder
    private func signedInSections(_ account: AppAccount) -> some View {
        Section("Your information") {
            NavigationLink { PatientProfileView(accountID: account.id).id(account.id) } label: {
                rowLabel("My details", subtitle: "Personal details and emergency contact",
                         symbol: "person.text.rectangle", tint: .blue)
            }
            if account.role == .patient {
                NavigationLink { AccountSyncView() } label: {
                    rowLabel("Account sync", subtitle: "Backup status and conflicts",
                             symbol: "icloud", tint: .cyan)
                }
            }
        }

        Section("Preferences") {
            NavigationLink { AppSettingsView() } label: {
                rowLabel("Settings", subtitle: "Appearance, app lock, permissions",
                         symbol: "gearshape", tint: .gray)
            }
            NavigationLink { WalkingVoiceControlsView() } label: {
                rowLabel("Voice & accessibility", subtitle: "Siri shortcuts, read aloud, VoiceOver",
                         symbol: "speaker.wave.2", tint: .purple)
            }
        }

        Section("Account") {
            DisclosureGroup {
                LabeledContent("Email", value: account.email)
                LabeledContent("Role", value: account.role == .staff ? "Hospital staff" : "Patient")
                LabeledContent("Email verified", value: account.isEmailVerified ? "Yes" : "Not yet")
                if !account.isEmailVerified {
                    Button { Task { await model.sendVerification() } } label: {
                        Label(model.isBusy ? "Sending…" : "Send verification email", systemImage: "envelope.badge")
                    }
                }
                Button("Refresh account") { Task { await model.restore() } }
            } label: {
                rowLabel("Account & verification", subtitle: account.email,
                         symbol: "checkmark.shield", tint: .green)
            }
            if account.role == .patient {
                NavigationLink { AccountDataControlsView() } label: {
                    rowLabel("Account & data controls", subtitle: "Remove PDFs or delete your account",
                             symbol: "lock.shield", tint: .orange)
                }
            }
        }

        if account.canManageQueues {
            Section("Hospital staff") {
                NavigationLink { StaffHospitalListView(account: account) } label: {
                    rowLabel("Hospital workspace", subtitle: "SOS requests and department queues",
                             symbol: "building.2", tint: CardioSafeTheme.teal)
                }
            }
        } else if account.role == .staff {
            Section {
                Text("Staff access requires a verified email and a hospital assignment.").font(.subheadline)
            }
        }

        Section {
            Button("Sign out", role: .destructive) { model.signOut() }
                .disabled(sessionModel.isActive)
        } footer: {
            if sessionModel.isActive { Text("Finish your active walk before signing out.") }
        }
    }

    // MARK: Guest

    @ViewBuilder
    private var guestSections: some View {
        Section("Preferences") {
            NavigationLink { AppSettingsView() } label: {
                rowLabel("Settings", subtitle: "Appearance, app lock, permissions",
                         symbol: "gearshape", tint: .gray)
            }
            NavigationLink { WalkingVoiceControlsView() } label: {
                rowLabel("Voice & accessibility", subtitle: "Siri shortcuts, read aloud, VoiceOver",
                         symbol: "speaker.wave.2", tint: .purple)
            }
        }
    }

    // MARK: Notice banner

    @ViewBuilder private var noticeBanner: some View {
        if let notice = model.notice {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(notice.isError ? CardioSafeTheme.alert : CardioSafeTheme.teal)
                Text(notice.text).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                Button { model.dismissNotice() } label: {
                    Image(systemName: "xmark").font(.caption.bold()).frame(width: 44, height: 44)
                }.accessibilityLabel("Dismiss notification")
            }
            .padding(16)
            .background(surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(CardioSafeTheme.teal.opacity(0.18), lineWidth: 1) }
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
            .padding(.horizontal, 16).padding(.top, 8)
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: Helpers

    private func rowLabel(_ title: String, subtitle: String? = nil, symbol: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold)).foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func initials(for account: AppAccount) -> String {
        let source = displayName.isEmpty ? account.email : displayName
        let words = source.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" || $0 == "_" || $0 == "-" })
        let letters = words.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }
        return letters.isEmpty ? "?" : letters.joined()
    }

    private func loadProfileSummary() {
        guard let account = model.account, account.role == .patient else {
            displayName = ""; emergencyContactName = ""; return
        }
        let profile = try? LocalPatientProfileStore().load(accountID: account.id)
        displayName = profile?.fullName ?? ""
        emergencyContactName = profile?.emergencyContactName ?? ""
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
    @Environment(\.dynamicTypeSize) private var typeSize
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
                    if typeSize.isAccessibilitySize {
                        Picker("Account action", selection: $registering) {
                            Text("Sign in").tag(false)
                            Text("Create account").tag(true)
                        }.pickerStyle(.menu)
                    } else {
                        HStack(spacing: 4) {
                            accountTab("Sign in", icon: "person.crop.circle", registration: false)
                            accountTab("Create account", icon: "person.crop.circle.badge.plus", registration: true)
                        }
                        .padding(5)
                        .background(CardioSafeTheme.teal.opacity(0.07), in: Capsule())
                        .overlay { Capsule().stroke(CardioSafeTheme.teal.opacity(0.12), lineWidth: 1) }
                    }

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
                Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
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
                if !typeSize.isAccessibilitySize {
                    Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22).accessibilityHidden(true)
                }
                content().accessibilityLabel(title)
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
