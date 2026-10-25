import SwiftUI
import UIKit

struct AppLockShield: UIViewRepresentable {
    let model: AppLockViewModel
    let isVisible: Bool
    func makeUIView(context: Context) -> ShieldAnchor {
        let anchor = ShieldAnchor()
        anchor.model = model
        anchor.isVisible = isVisible
        return anchor
    }
    func updateUIView(_ view: ShieldAnchor, context: Context) {
        view.model = model
        view.isVisible = isVisible
        view.updateShield()
    }
    static func dismantleUIView(_ view: ShieldAnchor, coordinator: ()) { view.removeShield() }

    final class ShieldAnchor: UIView {
        var model: AppLockViewModel?
        var isVisible = false
        private var shield: UIWindow?
        override func didMoveToWindow() { super.didMoveToWindow(); updateShield() }
        func updateShield() {
            guard let model, let scene = window?.windowScene else { return }
            if shield == nil {
                let overlay = UIWindow(windowScene: scene)
                overlay.windowLevel = .alert + 1
                overlay.backgroundColor = .systemBackground
                overlay.rootViewController = UIHostingController(rootView: AppLockedView(model: model))
                shield = overlay
            }
            shield?.isHidden = !isVisible
        }
        func removeShield() { shield?.isHidden = true; shield = nil }
    }
}

private struct AppLockedView: View {
    let model: AppLockViewModel
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "lock.shield.fill").font(.system(size: 58)).foregroundStyle(.blue)
                Text("CardioSafe is locked").font(.title.bold())
                Text("Unlock to view your profile and records.").foregroundStyle(.secondary)
                if model.isActive {
                    Button { Task { await model.unlock() } } label: {
                        HStack {
                            if model.isBusy { ProgressView().tint(.white) }
                            Text(model.isBusy ? "Authenticating…" : "Unlock CardioSafe").fontWeight(.semibold)
                        }.frame(maxWidth: .infinity).padding(16)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 16))
                    .disabled(model.isBusy)
                    if let error = model.errorMessage { Text(error).font(.subheadline).foregroundStyle(.secondary) }
                    Text("Uses Face ID, Touch ID or your device passcode. Walking tracking continues during an active session.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.multilineTextAlignment(.center).padding(28).frame(maxWidth: 440)
        }
    }
}
