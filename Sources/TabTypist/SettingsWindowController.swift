import AppKit
import SwiftUI

// Per-app toggle + telemetry consent + personalisation + model browser.
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
        hosting.frame = NSRect(x: 0, y: 0, width: 500, height: 580)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 580),
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
    @State private var telemetryEnabled: Bool =
        UserDefaults.standard.bool(forKey: "telemetryEnabled")
    @State private var userName: String =
        UserDefaults.standard.string(forKey: "userName") ?? ""
    @State private var customRulesGlobal: String =
        UserDefaults.standard.string(forKey: "customRulesGlobal") ?? ""
    @State private var clipboardEnabled: Bool =
        UserDefaults.standard.bool(forKey: "clipboardContextEnabled")
    @State private var customModelUrl: String = ""
    @State private var showResetConfirm: Bool = false
    @State private var downloadingCustom: Bool = false

    var body: some View {
        Form {
            Section("Privacy") {
                Toggle("Send anonymous usage data", isOn: $telemetryEnabled)
                    .onChange(of: telemetryEnabled) { _, enabled in
                        UserDefaults.standard.set(enabled, forKey: "telemetryEnabled")
                        IPCBridge.shared.notify(method: "updateSetting", params: [
                            "key": "telemetryEnabled", "value": enabled,
                        ])
                    }
                Text("Never includes your text, completions, or identity. Only: model used, accept/dismiss counts, app version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Personalization") {
                LabeledContent("Your name") {
                    TextField("Used in suggestions", text: $userName)
                        .onSubmit { sendUserName() }
                }
                Text("Shown to the model as context for more relevant suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Writing Style") {
                Text("Global rules")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $customRulesGlobal)
                    .font(.body)
                    .frame(height: 72)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    .onChange(of: customRulesGlobal) { _, newValue in
                        sendCustomRulesGlobal(newValue)
                    }
                Text("Applied to all apps. Example: use formal tone, prefer short sentences, write in British English.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Context") {
                Toggle("Include clipboard text in suggestions", isOn: $clipboardEnabled)
                    .onChange(of: clipboardEnabled) { _, enabled in
                        UserDefaults.standard.set(enabled, forKey: "clipboardContextEnabled")
                        IPCBridge.shared.notify(method: "updateSetting", params: [
                            "key": "clipboardContextEnabled", "value": enabled,
                        ])
                    }
                Text("TabTypist reads your clipboard to offer more relevant completions. Nothing leaves your device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model") {
                Button("Change model…") {
                    OnboardingController.shared.showIfNeeded()
                }

                Divider()

                LabeledContent("Custom GGUF") {
                    TextField("HuggingFace GGUF URL", text: $customModelUrl)
                }
                HStack {
                    Spacer()
                    Button(downloadingCustom ? "Downloading…" : "Download custom model") {
                        downloadCustomModel()
                    }
                    .disabled(customModelUrl.isEmpty || downloadingCustom)
                }
                Text("Enter a direct URL to a GGUF file from HuggingFace. Signature verification is skipped for custom models.")
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
        .onReceive(
            NotificationCenter.default.publisher(for: .downloadProgressUpdated)
        ) { note in
            if let phase = note.userInfo?["phase"] as? String {
                downloadingCustom = (phase == "downloading" || phase == "verifying")
                if phase == "complete" || phase == "failed" {
                    customModelUrl = ""
                }
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func sendUserName() {
        let trimmed = userName.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(trimmed, forKey: "userName")
        IPCBridge.shared.notify(method: "updateSetting", params: [
            "key": "userName", "value": trimmed,
        ])
    }

    private func sendCustomRulesGlobal(_ text: String) {
        UserDefaults.standard.set(text, forKey: "customRulesGlobal")
        IPCBridge.shared.notify(method: "updateSetting", params: [
            "key": "customRulesGlobal", "value": text,
        ])
    }

    private func downloadCustomModel() {
        let url = customModelUrl.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        downloadingCustom = true
        IPCBridge.shared.notify(method: "startModelDownload", params: [
            "language": "en",
            "customUrl": url,
        ])
    }
}
