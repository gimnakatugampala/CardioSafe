import SwiftUI

struct AccountSyncView: View {
    @Environment(FirebaseAccountSync.self) private var sync
    var body: some View {
        List {
            Section("Account backup") {
                Label(sync.status, systemImage: sync.busy ? "arrow.triangle.2.circlepath" : "icloud")
                if sync.busy { ProgressView("Syncing records…") }
                Button("Sync now") { Task { await sync.start(owner: sync.ownerID) } }.disabled(sync.busy || sync.ownerID == nil)
                if let error = sync.migrationError {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                    Button("Retry linking existing device records") {
                        Task {
                            do {
                                if let owner = sync.ownerID { try await LegacyAccountMigration.claim(for: owner) }
                                sync.migrationError = nil; sync.sync()
                            } catch { sync.migrationError = "Existing records could not be linked. Original files are preserved." }
                        }
                    }
                }
            }
            if !LegacyAccountMigration.hasClaimedRecords, let owner = sync.ownerID {
                Section("Existing device records") {
                    Text("One-time import: link this phone’s older device-only walks, documents and reminders to this account. They cannot then be claimed by another account on this phone.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Link existing records to this account") {
                        LegacyAccountMigration.approve(owner: owner)
                        Task {
                            do { try await LegacyAccountMigration.claim(for: owner); sync.migrationError = nil; sync.sync() }
                            catch { sync.migrationError = "Existing records could not be linked. Original files are preserved." }
                        }
                    }
                }
            }
            Section("What follows your account") {
                Label("Profile and emergency contact", systemImage: "person.text.rectangle")
                Label("Walks, rest periods and routes", systemImage: "figure.walk")
                Label("SOS recovery and journey summaries", systemImage: "cross.case")
                Label("Walking targets and planned rest", systemImage: "figure.walk")
                Label("Appearance preference", systemImage: "circle.lefthalf.filled")
                Text("App lock, permissions and daily walking notification schedules stay specific to each device.")
                    .font(.footnote).foregroundStyle(.secondary)
                Label("Document names, reviewed text and reminders", systemImage: "doc.text")
                Text("PDF files stay on the phone where they were added. On another phone you can read the synced document text and reminders, but the PDF itself is unavailable.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Saved walk measurements are backed up with each session. The app does not upload your whole Apple Health library.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let message = sync.notificationStatus { Section("Reminder alerts") { Text(message).font(.footnote) } }
            if !sync.conflicts.isEmpty {
                Section("Edits need your choice") {
                    ForEach(sync.conflicts) { record in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(record.key == "walking-plan" ? "Walking plan" : record.key == "appearance" ? "Appearance preference" : record.kind == "activeSOS" ? "Active SOS recovery" : record.kind.capitalized).font(.headline)
                            Text("This record changed on another phone while this phone had unsynced edits.").font(.subheadline).foregroundStyle(.secondary)
                            Button("Keep this phone’s version") { Task { await sync.resolve(record, keepLocal: true) } }
                            Button("Use the cloud version") { Task { await sync.resolve(record, keepLocal: false) } }
                        }
                    }
                }
            }
            Section {
                Text("Only your signed-in account can read these backups. Keep your account details available when switching phones.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Account sync").navigationBarTitleDisplayMode(.inline)
    }
}
