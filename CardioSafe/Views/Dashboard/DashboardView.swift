import SwiftUI
import MapKit

struct DashboardView: View {
    let viewModel: DashboardViewModel
    let sessionViewModel: WalkingSessionViewModel
    let onSelectTab: (AppTab) -> Void
    let onEmergency: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingWalkingMap = false
    @State private var showingSession = false

    private var surface: Color { CardioSafeTheme.surface(for: colorScheme) }
    private var ink: Color { CardioSafeTheme.text(for: colorScheme) }
    private let accent = Color(red: 0.31, green: 0.79, blue: 0.86)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                recoveryOverview
                walkingCompanion
                careShortcuts
                guardian
                Label("Health information stays on your device", systemImage: "lock.shield")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.bottom, 12)
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .background(CardioSafeTheme.background(for: colorScheme))
        .refreshable { await viewModel.refreshHealth() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await viewModel.refreshHealth()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .sheet(isPresented: $showingWalkingMap) { WalkingMapView() }
        .fullScreenCover(isPresented: $showingSession) { WalkingSessionView(viewModel: sessionViewModel) }
    }

    private var recoveryOverview: some View {
        VStack(spacing: -20) {
            VStack(alignment: .leading, spacing: 25) {
                HStack(spacing: 9) {
                    RecoveryMark()
                        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 28, height: 28).accessibilityHidden(true)
                    Text("CardioSafe").font(.headline).tracking(-0.4)
                    Spacer(minLength: 4)
                    Button(action: onEmergency) {
                        Text("SOS").font(.caption.bold())
                            .frame(minWidth: 44, minHeight: 44)
                            .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.74))
                            .background(.white.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Emergency Help")
                    Button { onSelectTab(.profile) } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title2).foregroundStyle(.white.opacity(0.85))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Profile and settings")
                }
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("YOUR RECOVERY").font(.caption2.weight(.semibold))
                            .tracking(1.8).foregroundStyle(accent)
                        Text("Today, in focus.").font(.title.bold()).tracking(-0.7)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 0)
                    if !typeSize.isAccessibilitySize {
                        Text(Date.now, format: .dateTime.day().month(.abbreviated))
                            .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.65))
                            .padding(.bottom, 4)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 42)
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [CardioSafeTheme.navy, Color(red: 0.08, green: 0.22, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            healthSummary.padding(.horizontal, 12)
        }
    }

    private var healthSummary: some View {
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
                Image(systemName: "heart.fill").foregroundStyle(CardioSafeTheme.alert)
                Text(viewModel.snapshot.healthReadings.isEmpty ? "No readable Health samples" : "Apple Health · Today’s activity & latest heart rate")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if viewModel.isRefreshingHealth { ProgressView().controlSize(.mini) }
            }
            .font(.caption2)
            if let error = viewModel.healthError {
                Text(error).font(.caption2).foregroundStyle(.secondary)
            }
            Button {
                Task { await viewModel.connectHealth() }
            } label: {
                Text(viewModel.isConnectingHealth ? "Opening Apple Health…" : (viewModel.hasRequestedHealthAccess ? "Request Health access" : "Connect Apple Health"))
                    .font(.caption.weight(.semibold)).frame(minHeight: 44)
            }
            .disabled(viewModel.isConnectingHealth || viewModel.isSeedingHealth)
            if viewModel.supportsSampleHealthData {
                Button {
                    Task { await viewModel.loadSampleHealthData() }
                } label: {
                    Label(viewModel.isSeedingHealth ? "Saving test samples…" : "Load simulator sample data", systemImage: "testtube.2")
                        .font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
                .disabled(viewModel.isSeedingHealth || viewModel.isConnectingHealth)
                Text(viewModel.sampleDataMessage ?? "Simulator testing: writes sample steps, distance, heart rate and energy to HealthKit, then queries them.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 17).padding(.horizontal, 12)
        .background(surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(ink.opacity(0.05)))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.045), radius: 14, y: 7)
    }

    private func healthMetric(_ metric: DashboardViewModel.MetricDisplay) -> some View {
        let colour: Color = metric.id == .heartRateBPM ? CardioSafeTheme.alert : CardioSafeTheme.teal
        return VStack(alignment: .leading, spacing: 7) {
            Label(metric.title, systemImage: metric.symbol)
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            Text(metric.value).font(.title2.bold()).monospacedDigit()
                .foregroundStyle(metric.id == .heartRateBPM ? colour : ink)
            Text(metric.unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 7)
        .accessibilityElement(children: .ignore).accessibilityLabel(metric.accessibilityDescription)
    }

    private var walkingCompanion: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("Walking companion").font(.headline).tracking(-0.3)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("YOUR NEXT STEP").font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                Button { showingWalkingMap = true } label: {
                    HomeMapPreview().frame(height: 180)
                        .overlay(alignment: .bottomTrailing) {
                            Label("Explore map", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.semibold)).padding(10)
                                .background(.regularMaterial, in: Capsule()).padding(12)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Explore hospitals, parks and walking routes on the map")
                Button {
                    if sessionViewModel.isActive || sessionViewModel.start(plan: viewModel.snapshot.walkingPlan) {
                        showingSession = true
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "figure.walk")
                            .font(.title3).foregroundStyle(CardioSafeTheme.teal)
                            .frame(width: 42, height: 46)
                            .background(CardioSafeTheme.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(sessionViewModel.isActive ? "Return to walk" : "Start walking")
                                .font(.subheadline.bold())
                            Text(sessionViewModel.isActive ? "Your session is still running" : "One tap to start your walking session").font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
                            .foregroundStyle(CardioSafeTheme.teal)
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

    private var careShortcuts: some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            shortcut(.care, title: "Find care", subtitle: "Hospitals & queues", symbol: "cross.case.fill")
            shortcut(.records, title: "My records", subtitle: "Documents & reminders", symbol: "doc.text.fill")
        }
    }

    private func shortcut(_ tab: AppTab, title: String, subtitle: String, symbol: String) -> some View {
        Button { onSelectTab(tab) } label: {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: symbol).font(.title3).foregroundStyle(CardioSafeTheme.teal)
                        .accessibilityHidden(true)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.bold())
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ink.opacity(0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var guardian: some View {
        Button(action: onEmergency) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title3).foregroundStyle(CardioSafeTheme.teal).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("CardioSafe Guardian").font(.subheadline.bold())
                    Text("Explore the hospital and ambulance dispatch demonstration.").font(.caption2).foregroundStyle(.secondary)
                    Text("Demo only · No real dispatch").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(CardioSafeTheme.teal.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(CardioSafeTheme.teal.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}

private struct HomeMapPreview: View {
    private let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612),
        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
    )

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: [])
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                Label("Colombo · Map preview", systemImage: "map")
                    .font(.caption2.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule()).padding(12)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "location.slash")
                    .font(.caption2).padding(9)
                    .background(.regularMaterial, in: Circle()).padding(12)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Map preview of Colombo. Your location and walking route are not connected.")
    }
}
