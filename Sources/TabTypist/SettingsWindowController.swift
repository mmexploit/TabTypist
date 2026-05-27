import AppKit
import SwiftUI

// Per-app toggle + telemetry consent + reset from the settings window.
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView()
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 360)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "TabTypist Settings"
        w.contentView = hosting
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

struct SettingsView: View {
    @State private var telemetryEnabled: Bool = false
    @State private var showResetConfirm: Bool = false

    var body: some View {
        Form {
            Section("Privacy") {
                Toggle("Send anonymous usage data", isOn: $telemetryEnabled)
                    .onChange(of: telemetryEnabled) { _, enabled in
                        IPCBridge.shared.notify(method: "updateSetting", params: [
                            "key": "telemetryEnabled",
                            "value": enabled,
                        ])
                    }
                Text("Never includes your text, completions, or identity. Only: model used, accept/dismiss counts, app version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                Button("Reset TabTypist…") { showResetConfirm = true }
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog(
            "This removes all models, settings, and stored data.",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                IPCBridge.shared.notify(method: "resetTabTypist", params: [:])
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
