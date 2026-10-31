import SwiftUI
import MapKit

struct DashboardView: View {
    let viewModel: DashboardViewModel
    let sessionViewModel: WalkingSessionViewModel
    let onSelectTab: (AppTab) -> Void
    /// Kept so ContentView still compiles; the header SOS button is now the single emergency entry point.
    let onEmergency: () -> Void
    let onEmergencyContacts: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingWalkingMap = false
    @State private var showingSession = false
    @State private var history = HealthHistoryViewModel()

    private var surface: Color { CardioSafeTheme.surface(for: colorScheme) }
    private var ink: Color { CardioSafeTheme.text(for: colorScheme) }
    private var themeAccent: Color { CardioSafeTheme.accent(for: colorScheme) }
    // Used only on the navy hero, where the lighter cyan is readable.
    private let heroAccent = Color(red: 0.31, green: 0.79, blue: 0.86)

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hello"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                ViewThatFits(in: .horizontal) {
                    if horizontalSizeClass == .regular && !typeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 24) {
                            healthHistoryCard.frame(minWidth: 300)
                            walkingCard.frame(minWidth: 320)
                        }
                    }
                    VStack(spacing: 24) { healthHistoryCard; walkingCard }
                }
                careShortcuts
            }
            .frame(maxWidth: horizontalSizeClass == .regular ? 1200 : 900, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .background(CardioSafeTheme.background(for: colorScheme))
        .refreshable {
            await viewModel.refreshHealth()
            await history.load()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await viewModel.refreshHealth()
                await history.load()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .sheet(isPresented: $showingWalkingMap) { WalkingMapView() }
        .fullScreenCover(isPresented: $showingSession) { WalkingSessionView(viewModel: sessionViewModel) }
    }

    private var healthHistoryCard: some View {
        NavigationLink { HealthHistoryView() } label: { HealthHistoryPreviewCard(model: history) }
            .buttonStyle(.plain).padding(.top, 8)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: -20) {
            VStack(alignment: .leading, spacing: 22) {
                ViewThatFits(in: .horizontal) {
                    heroHeader
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CardioSafe").font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        headerActions
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    if !typeSize.isAccessibilitySize {
                        Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                    Text(greeting).font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 42)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardioSafeTheme.navy, in: RoundedRectangle(cornerRadius: 24))
            healthCard.padding(.horizontal, 12)
        }
    }

    private var heroHeader: some View {
        HStack(spacing: 9) {
            RecoveryMark()
                .stroke(heroAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 28, height: 28).accessibilityHidden(true)
            Text("CardioSafe").font(.headline).fixedSize()
            Spacer(minLength: 4)
            headerActions
        }
    }

    private var headerActions: some View {
        HStack(spacing: 12) {
            Button(action: onEmergencyContacts) {
                Text("SOS").font(.subheadline.bold())
                    .frame(minWidth: 48, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(CardioSafeTheme.alert, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Emergency")
            .accessibilityHint("Call 1990 or request a demo ambulance")
            Button { onSelectTab(.profile) } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title2).foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).accessibilityLabel("Profile and settings")
        }
    }

    // MARK: Health

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(viewModel.healthMetrics) { metric in healthMetric(metric) }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(viewModel.healthMetrics) { metric in
                        healthMetric(metric)
                        if metric.id != viewModel.healthMetrics.last?.id {
                            Rectangle().fill(ink.opacity(0.08)).frame(width: 1, height: 67)
                        }
                    }
                }
            }
            Divider()
            HStack(spacing: 7) {
                Image(systemName: "heart.fill").foregroundStyle(CardioSafeTheme.alert).accessibilityHidden(true)
                Text(viewModel.snapshot.healthReadings.isEmpty ? "No Health data yet" : "From Apple Health")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if viewModel.isRefreshingHealth { ProgressView().controlSize(.mini) }
            }
            .font(.caption)
            if viewModel.snapshot.healthReadings.isEmpty, viewModel.hasRequestedHealthAccess, viewModel.healthError == nil {
                Text("If you allowed access, make sure your iPhone or watch has recorded something today.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = viewModel.healthError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                Task { await viewModel.connectHealth() }
            } label: {
                Text(viewModel.isConnectingHealth ? "Opening Apple Health…"
                     : (viewModel.hasRequestedHealthAccess ? "Health permissions" : "Connect Apple Health"))
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
            .disabled(viewModel.isConnectingHealth || viewModel.isSeedingHealth)
            if viewModel.supportsSampleHealthData {
                Button {
                    Task { await viewModel.loadSampleHealthData() }
                } label: {
                    Label(viewModel.isSeedingHealth ? "Saving test samples…" : "Load simulator sample data",
                          systemImage: "testtube.2")
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                .disabled(viewModel.isSeedingHealth || viewModel.isConnectingHealth)
                Text(viewModel.sampleDataMessage
                     ?? "Simulator only. Adds test steps, distance and heart rate, then reads them back.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 17).padding(.horizontal, 12)
        .background(surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(ink.opacity(0.05)))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 14, y: 6)
    }

    private func healthMetric(_ metric: DashboardViewModel.MetricDisplay) -> some View {
        let colour: Color = metric.id == .heartRateBPM ? CardioSafeTheme.alert : CardioSafeTheme.teal
        return VStack(alignment: .leading, spacing: 6) {
            Label(metric.title, systemImage: metric.symbol)
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(metric.value).font(.title2.bold()).monospacedDigit()
                .foregroundStyle(metric.id == .heartRateBPM ? colour : ink)
            Text(metric.unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 7)
        .accessibilityElement(children: .ignore).accessibilityLabel(metric.accessibilityDescription)
    }

    // MARK: Walking

    private var walkingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Walking").font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                Button { showingWalkingMap = true } label: {
                    HomeMapPreview().frame(height: 170)
                        .overlay(alignment: .bottomTrailing) {
                            Label("Open map", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.semibold)).padding(10)
                                .background(.regularMaterial, in: Capsule()).padding(12)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open the map to find hospitals, parks and walking routes")
                Divider()
                Button {
                    if sessionViewModel.isActive || sessionViewModel.start(plan: viewModel.snapshot.walkingPlan) {
                        showingSession = true
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "figure.walk")
                            .font(.title3).foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(CardioSafeTheme.teal, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sessionViewModel.isActive ? "Return to walk" : "Start walking")
                                .font(.subheadline.bold())
                            Text(sessionViewModel.isActive ? "Session in progress" : viewModel.walkingStatus)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(surface, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(ink.opacity(0.05)))
        }
    }

    // MARK: Care and records

    private var careShortcuts: some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize
                  ? [GridItem(.flexible())]
                  : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            shortcut(.care, title: "Find care", subtitle: "Hospitals and queues", symbol: "cross.case.fill")
            shortcut(.records, title: "My records", subtitle: "Documents and reminders", symbol: "doc.text.fill")
        }
    }

    private func shortcut(_ tab: AppTab, title: String, subtitle: String, symbol: String) -> some View {
        Button { onSelectTab(tab) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: symbol).font(.title3).foregroundStyle(themeAccent)
                        .accessibilityHidden(true)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.bold())
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ink.opacity(0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Map preview

private struct HomeMapPreview: View {
    private let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612),
        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
    )

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: [])
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
