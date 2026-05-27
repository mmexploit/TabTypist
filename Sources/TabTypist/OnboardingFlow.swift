import AppKit
import SwiftUI

// Two-phase onboarding per ADR-0002 schedule.
final class OnboardingController {
    static let shared = OnboardingController()

    private var window: NSWindow?

    func showIfNeeded() {
        // Core tells sidecar whether onboarding is needed via the ready message
        // (see TabTypistApp.swift). This is called when core sends needsOnboarding: true.
        DispatchQueue.main.async { self.show(phase: 1) }
    }

    func show(phase: Int) {
        let view = OnboardingView(phase: phase)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 420)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Welcome to TabTypist"
        w.contentView = hosting
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}

enum OnboardingPhase: Int, CaseIterable {
    case welcome = 1
    case languageSelect
    case accessibilityPermission
    case modelDownload
    case done
}

struct OnboardingView: View {
    let phase: Int
    @State private var currentPhase: OnboardingPhase = .welcome
    @State private var accessibilityGranted: Bool = false
    @State private var downloadProgress: Double = 0
    @State private var isDownloading: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            phaseView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                if currentPhase != .welcome {
                    Button("Back") { advance(by: -1) }
                }
                Spacer()
                nextButton
            }
            .padding()
        }
        .frame(width: 560, height: 420)
        .onAppear {
            currentPhase = OnboardingPhase(rawValue: phase) ?? .welcome
        }
    }

    @ViewBuilder
    private var phaseView: some View {
        switch currentPhase {
        case .welcome:
            WelcomeStep()
        case .languageSelect:
            LanguageSelectStep()
        case .accessibilityPermission:
            AccessibilityStep(granted: $accessibilityGranted)
        case .modelDownload:
            ModelDownloadStep(progress: $downloadProgress, isDownloading: $isDownloading)
        case .done:
            DoneStep()
        }
    }

    private var nextButton: some View {
        Button(nextLabel) {
            if currentPhase == .accessibilityPermission && !accessibilityGranted {
                requestAccessibility()
            } else if currentPhase == .modelDownload && !isDownloading {
                startModelDownload()
            } else {
                advance(by: 1)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(currentPhase == .accessibilityPermission && !accessibilityGranted && accessibilityCheckFailed)
    }

    private var nextLabel: String {
        switch currentPhase {
        case .welcome: return "Get Started"
        case .languageSelect: return "Continue"
        case .accessibilityPermission: return accessibilityGranted ? "Continue" : "Grant Accessibility"
        case .modelDownload: return isDownloading ? "Downloading…" : "Download Model"
        case .done: return "Start Typing"
        }
    }

    private var accessibilityCheckFailed: Bool { false }

    private func advance(by delta: Int) {
        let raw = (currentPhase.rawValue + delta)
        currentPhase = OnboardingPhase(rawValue: raw) ?? .done
        if currentPhase == .done {
            IPCBridge.shared.notify(method: "onboardingComplete", params: [:])
            OnboardingController.shared.dismiss()
        }
    }

    private func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(opts as CFDictionary)
        accessibilityGranted = trusted
        if trusted { advance(by: 1) }
    }

    private func startModelDownload() {
        isDownloading = true
        IPCBridge.shared.notify(method: "startModelDownload", params: ["language": "en"])
        // Progress updates come in via downloadProgress RPC notifications
    }
}

// ── Step views ────────────────────────────────────────────────────────────────

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.cursor")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
            Text("Welcome to TabTypist")
                .font(.title.bold())
            Text("Ghost-text completions as you type — in any app on your Mac. Runs entirely on your device. No cloud, no subscriptions.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
        }
        .padding(40)
    }
}

struct LanguageSelectStep: View {
    @State private var english = true
    var body: some View {
        VStack(spacing: 20) {
            Text("Choose Languages")
                .font(.title2.bold())
            Text("TabTypist will download a model for each language you select.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Toggle("English (Qwen 2.5 1.5B · ~900 MB)", isOn: $english)
                    .disabled(true)
            }
            .frame(maxWidth: 380)
        }
        .padding(40)
        .onChange(of: english) { _, _ in
            IPCBridge.shared.notify(method: "updateSetting", params: ["key": "languages", "value": ["en"]])
        }
    }
}

struct AccessibilityStep: View {
    @Binding var granted: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Accessibility Permission")
                .font(.title2.bold())
            Text("TabTypist reads your caret position to place completions next to your cursor. This permission is required for the app to work.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            if granted {
                Label("Accessibility granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(40)
        .onAppear {
            granted = AXIsProcessTrusted()
        }
    }
}

struct ModelDownloadStep: View {
    @Binding var progress: Double
    @Binding var isDownloading: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("Download English Model")
                .font(.title2.bold())
            Text("Qwen 2.5 1.5B (4-bit) · ~900 MB\nThis model runs entirely on your Mac — no internet required after download.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            if isDownloading {
                ProgressView(value: progress)
                    .frame(maxWidth: 300)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
    }
}

struct DoneStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("You're all set!")
                .font(.title.bold())
            Text("Start typing anywhere. Press Tab to accept a completion, Escape to dismiss.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
        }
        .padding(40)
    }
}
