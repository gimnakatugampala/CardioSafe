import SwiftUI

struct PasswordRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = PasswordRecoveryViewModel()
    @State private var email: String
    @Environment(\.colorScheme) private var scheme
    @FocusState private var emailFocused: Bool
    init(email: String) { _email = State(initialValue: email) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "lock.rotation").font(.largeTitle).foregroundStyle(CardioSafeTheme.teal)
                    Text("Reset your password.").font(.largeTitle.bold())
                    Text("Enter your CardioSafe email. Follow the link in the email to choose a new password, then return to sign in.")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Email address").font(.subheadline.bold())
                        TextField("you@example.com", text: $email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($emailFocused).submitLabel(.send)
                            .padding(16).background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 14))
                            .disabled(model.isSending)
                            .onSubmit { send() }
                    }
                    if let message = model.message {
                        Label(message, systemImage: "envelope.badge.shield.half.filled").font(.subheadline)
                            .accessibilityIdentifier("passwordResetStatus")
                    }
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(CardioSafeTheme.alert)
                            .accessibilityIdentifier("passwordResetError")
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = model.remainingSeconds(at: context.date)
                        Button(action: send) {
                            HStack {
                                if model.isSending { ProgressView().tint(.white) }
                                Text(model.isSending ? "Requesting…" : remaining > 0 ? "Try again in \(remaining)s" : "Send reset instructions")
                            }.font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent).tint(CardioSafeTheme.teal)
                        .disabled(model.isSending || remaining > 0)
                    }
                    Text("For email/password accounts. If nothing arrives, check the address and Spam folder. You can retry after one minute; email delivery may be delayed.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Back to sign in") { dismiss() }.frame(minHeight: 44).disabled(model.isSending)
                }.padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .background(CardioSafeTheme.background(for: scheme)).scrollDismissesKeyboard(.interactively)
            .navigationTitle("Password recovery").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(model.isSending) } }
            .interactiveDismissDisabled(model.isSending)
        }
    }
    private func send() { emailFocused = false; Task { await model.send(email: email) } }
}
