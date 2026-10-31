import SwiftUI

struct WalkingSessionView: View {
    let viewModel: WalkingSessionViewModel
    var allowsAutomaticSOS = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 56
    @State private var showingFinishConfirmation = false
    @State private var showingEmergency = false
    @State private var showingHealthDetails = false

    private var resting: Bool { viewModel.phase == .resting }
    private var surface: Color { CardioSafeTheme.surface(for: colorScheme) }
    private var restColour: Color {
        colorScheme == .dark ? .orange : Color(red: 0.62, green: 0.30, blue: 0.04)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isActive {
                    activeMapScreen
                } else {
                    summaryScreen
                }
            }
            .background(CardioSafeTheme.background(for: colorScheme))
            .navigationTitle(viewModel.hasSummary ? "Walk summary" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(viewModel.isActive ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingEmergency = true } label: {
                        Label("Emergency Help", systemImage: "sos.circle")
                    }
                    .tint(CardioSafeTheme.alert)
                }
            }
            .confirmationDialog("Finish this walk?", isPresented: $showingFinishConfirmation, titleVisibility: .visible) {
                Button("Finish walk") { viewModel.finish() }
                Button("Continue walking", role: .cancel) {}
            } message: {
                Text("This ends the timer and saves your walking and rest totals.")
            }
            .sheet(isPresented: $showingEmergency) { EmergencyHelpView() }
            .sheet(isPresented: $showingHealthDetails, onDismiss: {
                if viewModel.automaticSOS.state == .submitted { showingEmergency = true }
            }) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                        automaticSOSSettings
                        journeySettings
                        WalkingHealthPanel(model: viewModel.healthModel,
                            gpsDistance: (viewModel.session?.routeDistanceMetres ?? 0) > 0 ? viewModel.session?.routeDistanceMetres : nil)
                        }.padding(20)
                    }
                    .safeAreaInset(edge: .top) { AutomaticSOSBanner(model: viewModel.automaticSOS) }
                    .navigationTitle("Walk health details")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingHealthDetails = false }
                    } }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .tint(CardioSafeTheme.accent(for: colorScheme))
        .interactiveDismissDisabled(viewModel.isActive)
        .onChange(of: viewModel.automaticSOS.state) { _, state in
            if state == .submitted {
                if showingHealthDetails { showingHealthDetails = false }
                else { showingEmergency = true }
            }
        }
    }

    private var summaryScreen: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusHeader
                    if viewModel.isActive {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            timingContent(viewModel.timing())
                        }
                    } else {
                        timingContent(viewModel.timing())
                    }
                    if viewModel.hasSummary, let session = viewModel.session {
                        summaryDetails(session)
                        if let gaps = session.untrackedGaps, !gaps.isEmpty {
                            Label("This walk was recovered after an interruption", systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                            Text("Untracked gaps are excluded from walking/rest totals and route distance. After resuming, saved health measurements cover the resumed portion only.")
                                .font(.footnote).foregroundStyle(.secondary)
                            ForEach(Array(gaps.enumerated()), id: \.offset) { _, gap in
                                Text("Not recorded: \(gap.from.formatted(.dateTime.day().month().hour().minute().second())) – \(gap.to.formatted(.dateTime.day().month().hour().minute().second()))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    DisclosureGroup("About this record") { WalkingModeNote().padding(.top, 10) }.font(.subheadline)
                    if viewModel.hasSummary {
                        if let id = viewModel.session?.id, viewModel.savedSessionIDs.contains(id) {
                            Label("Saved on this device", systemImage: "checkmark.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if let error = viewModel.saveError {
                            Text(error).font(.caption).foregroundStyle(.red)
                            Button("Retry save") { Task { await viewModel.savePendingSessions() } }
                        } else {
                            Text(viewModel.isSaving ? "Saving walk…" : "This walk is not saved on this device.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 800, alignment: .leading)
                .padding(20).frame(maxWidth: .infinity)
            }
            .background(CardioSafeTheme.background(for: colorScheme))
            .safeAreaInset(edge: .bottom, spacing: 0) { controlDock }
    }

    private var activeMapScreen: some View {
        GeometryReader { geometry in
            let wide = horizontalSizeClass == .regular && geometry.size.width >= 900 && !typeSize.isAccessibilitySize
            if wide {
                activeMapBase.safeAreaInset(edge: .trailing, spacing: 0) {
                    activeMapDock(height: geometry.size.height, wide: true)
                }
            } else {
                activeMapBase.safeAreaInset(edge: .bottom, spacing: 0) {
                    activeMapDock(height: geometry.size.height, wide: false)
                }
            }
        }
    }

    private var activeMapBase: some View {
        WalkingLiveMapView(sessionViewModel: viewModel)
            .ignoresSafeArea()
            .safeAreaInset(edge: .top, spacing: 0) { activeMapHeader }
    }

    private var activeMapHeader: some View {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down").frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel("Minimise walking session")
                    Spacer()
                    WalkingStatusPill(title: resting ? "Resting" : "Walking", symbol: phaseSymbol,
                                      colour: resting ? restColour : CardioSafeTheme.accent(for: colorScheme))
                        .background(.regularMaterial, in: Capsule())
                    Spacer()
                    Button { showingEmergency = true } label: {
                        Image(systemName: "sos.circle").font(.title2).frame(width: 44, height: 44)
                            .foregroundStyle(CardioSafeTheme.alert)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel("Emergency Help")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.top, 8)
    }

    private func activeMapDock(height: CGFloat, wide: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: 8) {
                AutomaticSOSBanner(model: viewModel.automaticSOS)
                activeRestStop
                if typeSize.isAccessibilitySize {
                    ScrollView { activeControls(viewModel.timing()) }.frame(height: height * 0.55)
                } else { activeControls(viewModel.timing()) }
            }
            .frame(width: wide ? 360 : nil)
            .padding(.trailing, wide ? 16 : 0)
        }
    }

    @ViewBuilder private var activeRestStop: some View {
                        if let stop = viewModel.restStop.reminder {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label(viewModel.restStop.isNearby ? "Rest stop nearby" : stop.place.name, systemImage: "mappin.circle")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Button { viewModel.restStop.clear() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Remove rest stop")
                                }
                                Text(viewModel.restStop.message ?? "").font(.caption)
                                if viewModel.restStop.isNearby && !resting {
                                    Button("Rest now") { _ = viewModel.beginRest() }.frame(minHeight: 44)
                                } else if !viewModel.restStop.isNearby && !viewModel.restStop.canMonitorBackground {
                                    Button("Enable background rest-stop alerts") { viewModel.restStop.enableBackground() }.font(.caption).frame(minHeight: 44)
                                }
                            }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 12)
                        }
    }

    @ViewBuilder private var journeySettings: some View {
        if viewModel.canSimulateJourney {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Simulated walking journey", isOn: Binding(
                    get: { viewModel.journeyEnabled },
                    set: { viewModel.setJourneySimulation($0) }))
                Text("Simulator only. The patient follows an Apple Maps walking route; location, distance, steps and heart rate are simulated test data and are labelled as such. Rest breaks pause the journey.")
                    .font(.caption).foregroundStyle(.secondary)
                if viewModel.isSimulatingJourney { journeyProgress }
            }
        }
    }

    @ViewBuilder private var journeySettings: some View {
        if viewModel.canSimulateJourney {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Simulated walking journey", isOn: Binding(
                    get: { viewModel.journeyEnabled },
                    set: { viewModel.setJourneySimulation($0) }))
                Text("Simulator only. The patient follows an Apple Maps walking route; location, distance, steps and heart rate are simulated test data and are labelled as such. Rest breaks pause the journey.")
                    .font(.caption).foregroundStyle(.secondary)
                if viewModel.isSimulatingJourney { journeyProgress }
            }
        }
    }

    private var automaticSOSSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Automatic SOS simulation", isOn: Binding(
                get: { viewModel.automaticSOS.enabled },
                set: { viewModel.automaticSOS.setEnabled($0) }))
                .disabled(!allowsAutomaticSOS)
            if !allowsAutomaticSOS {
                Text("Sign in with a patient account to enable automatic SOS simulation.").font(.caption).foregroundStyle(.secondary)
            }
            Text("For this walk while CardioSafe is open and unlocked. Two distinct HealthKit readings of at least 140 bpm, at least 10 seconds apart, start a 20-second cancellation countdown. This is a test threshold, not a medical assessment. Sign in as a patient to send a simulated hospital request. No real dispatch.")
                .font(.caption).foregroundStyle(.secondary)
            if viewModel.healthModel.supportsSimulatorFeed {
                Toggle("High heart rate test samples", isOn: Binding(
                    get: { viewModel.healthModel.highHeartRateTest },
                    set: { viewModel.healthModel.highHeartRateTest = $0 }))
                Text("Start the simulator feed below to write 160 bpm samples to HealthKit. The app reads them back through the HealthKit query.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func activeControls(_ timing: WalkingSessionTiming) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resting ? "Rest break" : "Walking time")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(viewModel.durationText(resting ? timing.currentRestSeconds : timing.walkingSeconds))
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit().foregroundStyle(resting ? restColour : CardioSafeTheme.text(for: colorScheme))
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Button { showingHealthDetails = true } label: {
                    Label("Health details", systemImage: "chevron.up")
                        .font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                }
                .accessibilityHint("Opens all health readings, data sources and connection controls")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { compactHealthMetrics }.font(.subheadline.weight(.medium))
                VStack(alignment: .leading, spacing: 6) { compactHealthMetrics }.font(.subheadline.weight(.medium))
            }
            if viewModel.healthModel.usesSimulatorSamples {
                Text("Simulated HealthKit samples").font(.caption2).foregroundStyle(.secondary)
            }
            if viewModel.isSimulatingJourney {
                journeyProgress
            }
            if let plan = viewModel.session?.plan {
                ProgressView(value: timing.progress).tint(CardioSafeTheme.teal)
                    .accessibilityLabel("Walking target progress")
                Text(timing.targetReached ? "Walking target reached" : "Target \(plan.walkingMinutes) min · Rest \(viewModel.durationText(timing.restingSeconds))")
                    .font(.caption).foregroundStyle(.secondary)
            } else if resting {
                Text("Walking paused · Total rest \(viewModel.durationText(timing.restingSeconds))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if resting, let minutes = viewModel.session?.plan?.restMinutesPerBreak {
                Text(timing.currentRestSeconds >= Double(minutes) * 60
                     ? "Planned rest reached. Resume when you’re ready."
                     : "Planned rest · \(minutes) min")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { restButton; finishButton }
            } else {
                HStack(spacing: 10) { restButton; finishButton }
            }
        }
        .padding(16).frame(maxWidth: 600)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    /// Simulator-only: shows the patient moving along an Apple Maps walking route.
    private var journeyProgress: some View {
        let journey = viewModel.journeySimulator
        return VStack(alignment: .leading, spacing: 4) {
            Label(journey.routeName, systemImage: "figure.walk.motion")
                .font(.caption.weight(.semibold)).lineLimit(2)
            ProgressView(value: journey.progress).tint(.orange)
                .accessibilityLabel("Simulated journey progress")
                .accessibilityValue("\(Int((journey.progress * 100).rounded(.down))) percent")
            Text(journey.summary).font(.caption).monospacedDigit()
            Text(resting ? "Patient is resting · journey paused" : (journey.statusMessage ?? "Simulated data"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var compactHealthMetrics: some View {
        Label("\(viewModel.healthModel.steps.map(String.init) ?? "—") steps", systemImage: "shoeprints.fill")
            .accessibilityLabel("Session steps, \(viewModel.healthModel.steps.map(String.init) ?? "unavailable")")
        Label("\(viewModel.healthModel.heartRate.map { String(Int($0.rounded())) } ?? "—") bpm", systemImage: "heart.fill")
            .accessibilityLabel("Latest heart rate, \(viewModel.healthModel.heartRate.map { String(Int($0.rounded())) + " beats per minute" } ?? "unavailable")")
            .accessibilityHint("Open Health details to check when this sample was recorded")
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                WalkingStatusPill(title: phaseTitle, symbol: phaseSymbol,
                                  colour: resting ? restColour : CardioSafeTheme.teal)
                Spacer(minLength: 8)
                if let date = viewModel.session?.startedAt {
                    Text(date, format: .dateTime.hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Started at \(date.formatted(date: .omitted, time: .shortened))")
                }
            }
            Text(viewModel.hasSummary ? "Your session, at a glance." : (resting ? "Walking time is paused." : "Your walking time is recording."))
                .font(.title2.bold()).tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if resting {
                Text("Your current break and total rest are tracked separately. Resume when you choose.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func timingContent(_ timing: WalkingSessionTiming) -> some View {
        let seconds = viewModel.hasSummary ? timing.displayedElapsedSeconds : (resting ? timing.currentRestSeconds : timing.walkingSeconds)
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text(viewModel.hasSummary ? "Total duration" : (resting ? "This rest break" : "Active walking"))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Text(viewModel.durationText(seconds))
                    .font(typeSize.isAccessibilitySize ? .largeTitle.bold() : .system(size: timerSize, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(resting ? restColour : CardioSafeTheme.text(for: colorScheme))
                    .contentTransition(.numericText())
                if let target = viewModel.session?.plan?.restMinutesPerBreak, resting {
                    Text("Planned interval · \(target) min")
                        .font(.caption).foregroundStyle(.secondary)
                    if timing.currentRestSeconds >= Double(target) * 60 {
                        Label("Planned rest interval reached", systemImage: "clock.badge.checkmark")
                            .font(.caption).foregroundStyle(restColour)
                    }
                }
            }
            if let plan = viewModel.session?.plan {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Walking target · \(plan.walkingMinutes) min").font(.caption)
                        Spacer()
                        Text("\(Int((timing.progress * 100).rounded(.down)))%")
                            .font(.caption.weight(.semibold)).monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    ProgressView(value: timing.progress).tint(CardioSafeTheme.teal)
                        .accessibilityLabel("Walking target progress")
                    if timing.targetReached {
                        Label("Walking target reached", systemImage: "checkmark.circle")
                            .font(.caption).foregroundStyle(CardioSafeTheme.teal)
                    }
                    if let rest = plan.restMinutesPerBreak, !resting && viewModel.isActive {
                        Text("Planned rest · \(rest) min per break")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 18) { timingMetrics(timing) }
            } else {
                HStack(alignment: .top, spacing: 20) { timingMetrics(timing) }
            }
            if resting {
                Text("Total elapsed · \(viewModel.durationText(timing.displayedElapsedSeconds))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(resting ? restColour.opacity(0.065) : surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(resting ? restColour.opacity(0.16) : .clear))
    }

    @ViewBuilder
    private func timingMetrics(_ timing: WalkingSessionTiming) -> some View {
        if viewModel.hasSummary || resting {
            WalkingMetric(title: "Walking", value: viewModel.durationText(timing.walkingSeconds),
                          unit: timeUnit(timing.walkingSeconds), symbol: "figure.walk")
            WalkingMetric(title: "Total rest", value: viewModel.durationText(timing.restingSeconds),
                          unit: timeUnit(timing.restingSeconds), symbol: "pause.circle")
        } else {
            WalkingMetric(title: "Total rest", value: viewModel.durationText(timing.restingSeconds),
                          unit: timeUnit(timing.restingSeconds), symbol: "pause.circle")
            WalkingMetric(title: "Total elapsed", value: viewModel.durationText(timing.displayedElapsedSeconds),
                          unit: timeUnit(timing.displayedElapsedSeconds), symbol: "clock")
        }
    }

    private var controlDock: some View {
        VStack(spacing: 10) {
            if viewModel.isActive {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 10) { restButton; finishButton }
                } else {
                    HStack(spacing: 12) { restButton; finishButton }
                }
                Text("Timer continues when minimised")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Button { dismiss() } label: {
                    Text("Done").font(.headline).frame(maxWidth: .infinity).padding(17)
                        .foregroundStyle(.white).background(CardioSafeTheme.navy, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 800).padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
        .frame(maxWidth: .infinity).background(.regularMaterial)
    }

    private var restButton: some View {
        Button {
            if viewModel.phase == .walking { viewModel.beginRest() }
            else if viewModel.phase == .resting { viewModel.resume() }
        } label: {
            Label(resting ? "Resume walking" : "Rest", systemImage: resting ? "play.fill" : "pause.fill")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(.white).background(CardioSafeTheme.navy, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityHint(resting ? "Continues recording walking time" : "Pauses walking time and records a rest break")
    }

    private var finishButton: some View {
        Button { showingFinishConfirmation = true } label: {
            Label("Finish", systemImage: "stop.fill")
                .font(.subheadline.weight(.semibold)).frame(minWidth: 100, minHeight: 54)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
                .foregroundStyle(CardioSafeTheme.text(for: colorScheme))
                .background(surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.09)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Finish walking session")
        .accessibilityHint("Shows a confirmation before stopping the timer")
    }

    private func summaryDetails(_ session: WalkingSession) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if session.plan != nil {
            VStack(alignment: .leading, spacing: 14) {
                Label("Plan used for this walk", systemImage: "list.clipboard")
                    .font(.headline)
                detailRow("Walking target", value: session.plan.map { "\($0.walkingMinutes) min" } ?? "Not set")
                detailRow("Planned rest", value: session.plan?.restMinutesPerBreak.map { "\($0) min per break" } ?? "Not set")
                if let end = session.endedAt {
                    detailRow("Finished", value: end.formatted(date: .omitted, time: .shortened))
                }
            }
            .padding(18).background(surface, in: RoundedRectangle(cornerRadius: 18))
            }
            DisclosureGroup("Rest breaks (\(session.restPeriods.count))") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Rest periods").font(.headline)
                    Spacer()
                    Text("\(session.restPeriods.count)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                if session.restPeriods.isEmpty {
                    Text("No rest periods were recorded.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(Array(session.restPeriods.enumerated()), id: \.offset) { index, rest in
                    if index > 0 { Divider() }
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Rest \(index + 1)", systemImage: "pause.circle")
                                .font(.subheadline.weight(.medium))
                            Text(rest.startedAt, format: .dateTime.hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(viewModel.durationText(rest.durationSeconds)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                }
            }
            .padding(18).background(surface, in: RoundedRectangle(cornerRadius: 18))
            }
            WalkingSavedHealthView(snapshot: session.healthSnapshot)
            WalkingRecordedRouteView(session: session)
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func timeUnit(_ seconds: TimeInterval) -> String { seconds >= 3600 ? "hr:min:sec" : "min:sec" }

    private var phaseTitle: String {
        switch viewModel.phase {
        case .walking: "Walking"
        case .resting: "Resting"
        case .finished: "Completed"
        case .ready: "Ready"
        }
    }

    private var phaseSymbol: String {
        switch viewModel.phase {
        case .walking: "figure.walk"
        case .resting: "pause.circle.fill"
        case .finished: "checkmark.circle.fill"
        case .ready: "clock"
        }
    }
}

#if DEBUG
#Preview("Walking · example plan") {
    let model = WalkingSessionViewModel()
    let _ = model.start(plan: WalkingPlan(walkingMinutes: 20, restMinutesPerBreak: 5))
    WalkingSessionView(viewModel: model)
}

#Preview("Resting · example plan") {
    let model = WalkingSessionViewModel()
    let _ = model.start(plan: WalkingPlan(walkingMinutes: 20, restMinutesPerBreak: 5))
    let _ = model.beginRest()
    WalkingSessionView(viewModel: model)
}

#Preview("Summary · example session") {
    let clock = WalkingExampleClock()
    let model = WalkingSessionViewModel(clock: clock)
    let _ = model.start(plan: WalkingPlan(walkingMinutes: 20, restMinutesPerBreak: 5))
    let _ = clock.advance(600)
    let _ = model.beginRest()
    let _ = clock.advance(120)
    let _ = model.resume()
    let _ = clock.advance(300)
    let _ = model.finish()
    WalkingSessionView(viewModel: model)
}

#Preview("Resting · large text") {
    let model = WalkingSessionViewModel()
    let _ = model.start(plan: WalkingPlan(walkingMinutes: 20, restMinutesPerBreak: 5))
    let _ = model.beginRest()
    WalkingSessionView(viewModel: model).environment(\.dynamicTypeSize, .accessibility2)
}

@MainActor
private final class WalkingExampleClock: WalkingSessionClock {
    private let origin = Date.now.addingTimeInterval(-1020)
    private var seconds: TimeInterval = 0
    func advance(_ duration: TimeInterval) { seconds += duration }
    func read() -> WalkingSessionInstant {
        WalkingSessionInstant(date: origin.addingTimeInterval(seconds), monotonicSeconds: seconds)
    }
}
#endif
