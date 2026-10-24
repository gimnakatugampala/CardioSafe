import SwiftUI

struct DashboardView: View {
    let viewModel: DashboardViewModel
    let onSelectTab: (AppTab) -> Void
    let onEmergency: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var surface: Color { CardioSafeTheme.surface(for: colorScheme) }
    private var ink: Color { CardioSafeTheme.text(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                introduction
                walkingPlan
                healthSummary
                careAccess
                guardian
                Label("Health information stays on your device", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.bottom, 8)
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(20).frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .background(CardioSafeTheme.background(for: colorScheme))
    }

    private var header: some View {
        HStack(spacing: 10) {
            RecoveryMark().stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 24, height: 24).padding(9)
                .background(CardioSafeTheme.navy, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            Text("CardioSafe").font(.title3.bold()).tracking(-0.6)
            Spacer(minLength: 4)
            Button(action: onEmergency) {
                Text("SOS").font(.caption.bold())
                    .foregroundStyle(CardioSafeTheme.alert)
                    .frame(minWidth: 46, minHeight: 46)
                    .background(CardioSafeTheme.alert.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain).accessibilityLabel("Emergency Help")
            Button { onSelectTab(.profile) } label: {
                Image(systemName: "person.crop.circle").font(.title2)
                    .frame(width: 46, height: 46)
                    .background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain).accessibilityLabel("Profile and settings")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Your recovery overview")
                .font(.largeTitle.weight(.bold)).tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var walkingPlan: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("WALKING REHABILITATION", systemImage: "figure.walk")
                        .font(.caption2.bold()).tracking(0.8)
                        .foregroundStyle(Color(red: 0.67, green: 0.79, blue: 0.93))
                    Text(viewModel.walkingTitle).font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(viewModel.walkingDescription)
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.top, 25).accessibilityHidden(true)
                }
            }
            Divider().overlay(.white.opacity(0.15))
            Button { onSelectTab(.walk) } label: {
                HStack {
                    Text(viewModel.walkingActionTitle).font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding(15).foregroundStyle(CardioSafeTheme.navy)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(20).foregroundStyle(.white)
        .background(CardioSafeTheme.navy, in: RoundedRectangle(cornerRadius: 18))
    }

    private var healthSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Health summary").font(.headline)
                Spacer()
                Label("Apple Health", systemImage: "heart.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 18) {
                        ForEach(viewModel.healthMetrics) { metric in
                            healthMetric(metric)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(viewModel.healthMetrics) { metric in
                            healthMetric(metric)
                            if metric.id != viewModel.healthMetrics.last?.id {
                                Rectangle().fill(ink.opacity(0.09)).frame(width: 1, height: 78)
                            }
                        }
                    }
                }
                Divider()
                Label(viewModel.healthStatus, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 18).padding(.horizontal, 10)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ink.opacity(0.05)))
        }
    }

    private func healthMetric(_ metric: DashboardViewModel.MetricDisplay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(metric.title, systemImage: metric.symbol)
                .font(.caption).foregroundStyle(.secondary)
            Text(metric.value).font(.title.bold()).monospacedDigit()
            Text(metric.unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityDescription)
    }

    private var careAccess: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Care & records").font(.headline)
            VStack(spacing: 0) {
                directoryRow(.care, title: "Find a hospital", subtitle: "Nearby care & department queues", symbol: "cross.case")
                Divider().padding(.leading, 62)
                directoryRow(.records, title: "Medical records", subtitle: "Documents, scans & reminders", symbol: "doc.text")
            }
            .background(surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ink.opacity(0.05)))
        }
    }

    private func directoryRow(_ tab: AppTab, title: String, subtitle: String, symbol: String) -> some View {
        Button { onSelectTab(tab) } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).foregroundStyle(CardioSafeTheme.teal)
                    .frame(width: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var guardian: some View {
        Button(action: onEmergency) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title2).foregroundStyle(CardioSafeTheme.teal).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CardioSafe Guardian").font(.subheadline.bold())
                    Text(viewModel.guardianDetail).font(.caption).foregroundStyle(.secondary)
                    Text(viewModel.guardianStatus).font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(CardioSafeTheme.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(CardioSafeTheme.teal.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}
