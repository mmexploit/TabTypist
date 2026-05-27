import AppKit
import SwiftUI

// One-time activation toast for messaging apps.
final class ToastManager {
    static let shared = ToastManager()

    private var toastWindow: NSWindow?

    func showMessagingToast(bundleId: String, appName: String) {
        DispatchQueue.main.async {
            self.present(bundleId: bundleId, appName: appName)
        }
    }

    private func present(bundleId: String, appName: String) {
        toastWindow?.close()

        let toast = MessagingToastView(
            appName: appName,
            onKeep: { [weak self] in
                self?.toastWindow?.close()
            },
            onDisable: { [weak self] in
                IPCBridge.shared.notify(method: "updateSetting", params: [
                    "key": "disableApp",
                    "bundleId": bundleId,
                ])
                self?.toastWindow?.close()
            }
        )

        let hosting = NSHostingView(rootView: toast)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 80)

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - 340
        let y = screenFrame.maxY - 100

        let window = NSPanel(
            contentRect: NSRect(x: x, y: y, width: 320, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.contentView = hosting
        window.ignoresMouseEvents = false
        window.orderFront(nil)

        toastWindow = window

        // Auto-dismiss after 8 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.toastWindow?.close()
        }
    }
}

struct MessagingToastView: View {
    let appName: String
    let onKeep: () -> Void
    let onDisable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TabTypist is active in \(appName)")
                .font(.system(size: 12, weight: .semibold))
            Text("Completions run locally on your Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Keep", action: onKeep)
                    .controlSize(.small)
                Button("Disable in \(appName)", action: onDisable)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .shadow(radius: 4)
        )
    }
}
