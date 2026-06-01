import AppKit
import SwiftUI
import IOKit.hid

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
        hosting.frame = NSRect(x: 0, y: 0, width: 500, height: 760)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 760),
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
    @State private var hfToken: String =
        UserDefaults.standard.string(forKey: "hfToken") ?? ""
    @State private var customModelUrl: String = ""
    @State private var showResetConfirm: Bool = false
    @State private var downloadingCustom: Bool = false

    @State private var axGranted: Bool = AXIsProcessTrusted()
    @State private var screenGranted: Bool = CGPreflightScreenCaptureAccess()
    @State private var inputMonGranted: Bool =
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted

    var body: some View {
        Form {
            Section("Permissions") {
                permissionRow(
                    name: "Accessibility", granted: axGranted,
                    detail: "Read caret position and insert completions when you press Tab."
                ) {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
                    openPrivacyPane("Privacy_Accessibility")
                }
                permissionRow(
                    name: "Input Monitoring", granted: inputMonGranted,
                    detail: "Detect the Tab key so suggestions can be accepted."
                ) {
                    _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
                    openPrivacyPane("Privacy_ListenEvent")
                }
                permissionRow(
                    name: "Screen Recording", granted: screenGranted,
                    detail: "Optional. On-device OCR of nearby on-screen text for context-aware suggestions."
                ) {
                    _ = CGRequestScreenCaptureAccess()
                    openPrivacyPane("Privacy_ScreenCapture")
                }
                if !screenGranted {
                    Text("After enabling Screen Recording, macOS may ask you to quit & reopen TabTypist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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

                LabeledContent("HuggingFace token") {
                    SecureField("hf_...", text: $hfToken)
                        .onSubmit { sendHfToken() }
                }
                Text("Required for all model downloads. Get yours at huggingface.co/settings/tokens (read-only token is enough).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
        // Permissions can change while this window is open (the user grants them in
        // System Settings). Re-poll periodically so the rows update live.
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            refreshPermissions()
        }
    }

    // ── Permission row ─────────────────────────────────────────────────────────

    @ViewBuilder
    private func permissionRow(
        name: String, granted: Bool, detail: String, grant: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text("Granted").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Grant…", action: grant)
            }
        }
        .padding(.vertical, 2)
    }

    private func refreshPermissions() {
        axGranted = AXIsProcessTrusted()
        screenGranted = CGPreflightScreenCaptureAccess()
        inputMonGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
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

    private func sendHfToken() {
        let trimmed = hfToken.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(trimmed, forKey: "hfToken")
        IPCBridge.shared.notify(method: "updateSetting", params: [
            "key": "hfToken", "value": trimmed,
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
