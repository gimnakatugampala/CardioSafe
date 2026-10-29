import SwiftUI

struct AutomaticSOSBanner: View {
    let model: AutomaticSOSViewModel
    var body: some View {
        if model.state == .countdown {
            VStack(alignment: .leading, spacing: 8) {
                Label("Simulation SOS in \(model.secondsRemaining)s", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).accessibilityAddTraits(.updatesFrequently)
                Text("Repeated readings crossed the test threshold. No real emergency service will be contacted.")
                    .font(.caption)
                Button("I’m OK — cancel automatic SOS", role: .cancel) { model.setEnabled(false) }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.borderedProminent)
            }
            .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.orange, lineWidth: 2))
            .padding(.horizontal, 12)
        }
    }
}
