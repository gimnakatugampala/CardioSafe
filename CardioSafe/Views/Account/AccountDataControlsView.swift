import SwiftUI
import FirebaseAuth

struct AccountDataControlsView: View {
    @Environment(WalkingSessionViewModel.self) private var session
    @Environment(DispatchDemoViewModel.self) private var dispatch
    @State private var model = AccountDeletionViewModel.shared
    @State private var password = ""
    @State private var confirmation = ""
    @State private var confirmingDelete = false
    @State private var confirmingPDFs = false
    @State private var localMessage: String?
    @State private var recoveryEmail = ""
    private var blocked: Bool { session.isActive || session.isSaving || session.isLoadingHistory || session.needsRecoveryDecision || dispatch.isActive || dispatch.isRestoring }
    var body: some View {
        Form {
            if model.completed {
                Section("Account deleted") { Text(model.message ?? "Close and reopen CardioSafe.") }
            } else {
                if model.pendingOwner == nil {
                    Section("Local PDF copies") {
                        Text("Remove downloaded/scanned PDF files for this account from this phone. Synced document text and reminders remain. PDFs cannot be restored from Firebase on the current plan.")
                        Button("Remove local PDF copies", role: .destructive) { confirmingPDFs = true }.disabled(blocked)
                        if let localMessage { Text(localMessage).font(.footnote) }
                    }
                }
                Section("Delete patient account") {
                    Text("Permanently deletes sign-in, private Firebase backups, and this account’s records and PDFs on this phone. Apple Health samples, separate guest data, local copies on other devices and shared hospital request history are not deleted. A server deletion marker remains to prevent old devices recreating your backups.")
                        .font(.footnote)
                    if model.pendingOwner != nil {
                        Text("Deletion already started. Sync stays paused until it finishes; do not switch accounts.").foregroundStyle(.orange)
                    }
                    if model.pendingOwner != nil && Auth.auth().currentUser == nil {
                        TextField("Patient account email", text: $recoveryEmail).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Sign in to finish deletion") {
                            Task {
                                do {
                                    _ = try await FirebaseAccountService().signIn(email: recoveryEmail, password: password)
                                    localMessage = "Signed in. Confirm deletion to finish."
                                } catch { localMessage = "Sign-in failed. Check the account email and password." }
                            }
                        }.disabled(password.isEmpty || recoveryEmail.isEmpty || model.busy)
                        if let localMessage { Text(localMessage).font(.caption) }
                    }
                    SecureField("Current account password", text: $password).textContentType(.password)
                    TextField("Type DELETE to confirm", text: $confirmation).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    if blocked { Text("Finish your walk and complete/cancel your SOS first.").foregroundStyle(.secondary) }
                    Button(model.busy ? "Deleting…" : "Permanently delete account", role: .destructive) { confirmingDelete = true }
                        .disabled(blocked || model.busy || password.isEmpty || confirmation != "DELETE")
                    if model.busy { ProgressView() }
                    if let message = model.message { Text(message).font(.footnote) }
                    if let error = model.error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
        }
        .navigationTitle("Account & data").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Permanently delete this patient account and its private backups?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account permanently", role: .destructive) {
                Task { await model.erase(password: password); password = ""; confirmation = "" }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove this account’s PDF files from this phone?", isPresented: $confirmingPDFs, titleVisibility: .visible) {
            Button("Remove PDF files", role: .destructive) {
                do {
                    guard let owner = Auth.auth().currentUser?.uid else { throw AccountDeletionError.signIn }
                    let count = try AccountLocalDataCleaner.removePDFs(owner: owner)
                    localMessage = "Removed \(count) PDF files. Synced document text is kept."
                } catch { localMessage = "PDF files could not be removed. Please retry." }
            }
            Button("Cancel", role: .cancel) {}
        }
        .interactiveDismissDisabled(model.busy || model.pendingOwner != nil)
        .onDisappear { password = "" }
    }
}
