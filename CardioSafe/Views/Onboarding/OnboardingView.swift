import SwiftUI

struct OnboardingView: View {
    let account: AppAccount?
    let onFinish: () -> Void
    let onSetUpProfile: () -> Void
    var showsProfileSetup = true
    @State private var model = OnboardingViewModel()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var accent: Color { scheme == .dark ? .cyan : CardioSafeTheme.teal }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 7) {
                        ForEach(0..<model.stepCount, id: \.self) { index in
                            Capsule().fill(index <= model.step ? accent : accent.opacity(0.15)).frame(height: 4)
                        }
                    }.accessibilityLabel("Introduction, step \(model.step + 1) of \(model.stepCount)")
                    Image(systemName: symbol)
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(accent).frame(width: 104, height: 104)
                        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 28))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CARDIOSAFE").font(.caption.weight(.bold)).tracking(2).foregroundStyle(accent)
                        Text(title).font(.largeTitle.bold()).tracking(-0.8).accessibilityAddTraits(.isHeader)
                        Text(subtitle).font(.body).foregroundStyle(.secondary)
                    }
                    if model.step == 0 {
                        detail("Your day, in focus", icon: "heart.text.clipboard", text: "See today’s steps, distance and the latest available heart rate from Apple Health.")
                        detail("Your history stays close", icon: "doc.text", text: "Open Records to revisit completed walks, rest breaks and available health readings saved on this device.")
                    } else if model.step == 1 {
                        detail("Health access is your choice", icon: "heart", text: "Use Request Health access on Home or connect Health during a walk. Readings depend on permission and available samples; a supported device supplies heart rate.")
                        detail("Location for your walking route", icon: "location", text: "Starting a walk may request location access. With permission, GPS records your route while the session is active, including in the background. Finish the walk to stop tracking.")
                        detail("Move and rest", icon: "pause.circle", text: "The centre Walk button starts a session. Rest pauses walking time; both walking time and rest breaks are saved when you finish.")
                    } else {
                        detail("Find care nearby", icon: "cross.case", text: "Explore hospitals on the map and view available department counts. Demo queues are labelled; counts do not predict treatment priority or waiting time.")
                        detail("Emergency help", icon: "sos.circle", text: "Hospital notifications and ambulance dispatch are not connected yet. CardioSafe does not currently request an ambulance.")
                        if showsProfileSetup {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Make your profile yours").font(.headline)
                            Text("Add your name and an optional emergency contact. Details stay on this device for your signed-in account.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let account {
                                NavigationLink { PatientProfileView(accountID: account.id) } label: {
                                    Label("Set up patient profile", systemImage: "person.text.rectangle")
                                }.buttonStyle(.bordered)
                            } else {
                                Button("Sign in and set up profile", action: onSetUpProfile).buttonStyle(.bordered)
                            }
                            Text("You can skip this and add details later in Profile.").font(.caption).foregroundStyle(.secondary)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(CardioSafeTheme.surface(for: scheme), in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(CardioSafeTheme.background(for: scheme))
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        if model.isLastStep { onFinish() }
                        else { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { model.next() } }
                    } label: {
                        HStack {
                            Text(model.isLastStep ? "Get started" : "Continue").font(.headline)
                            Image(systemName: "arrow.right")
                        }.frame(maxWidth: .infinity).padding(17)
                    }
                    .buttonStyle(.plain).foregroundStyle(scheme == .dark ? CardioSafeTheme.navy : .white)
                    .background(accent, in: RoundedRectangle(cornerRadius: 16))
                    if model.step > 0 { Button("Back") { model.back() }.padding(4) }
                }.padding(.horizontal, 24).padding(.vertical, 12)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                    .background(CardioSafeTheme.background(for: scheme))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Skip introduction", action: onFinish) }
            }
            .tint(accent)
            .navigationBarTitleDisplayMode(.inline)
        }.interactiveDismissDisabled()
    }
    private var symbol: String { ["heart.text.clipboard", "figure.walk", "cross.case"][model.step] }
    private var title: String { ["Your recovery,\nat your pace.", "Walk with\na clearer picture.", "Care, closer\nto you."][model.step] }
    private var subtitle: String { ["A daily view of your activity, walking sessions and nearby care.", "Understand what you share before you start tracking.", "Find hospitals and keep your personal details ready."][model.step] }
    private func detail(_ title: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
