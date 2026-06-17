import Foundation
import Sparkle

// Wraps Sparkle's SPUStandardUpdaterController so the menu bar, Settings, and the
// app delegate share one updater instance.
//
// The updater checks SUFeedURL (Info.plist) for an EdDSA-signed appcast and offers
// updates non-blockingly. Automatic daily checks are governed by SUEnableAutomaticChecks
// / SUScheduledCheckInterval in Info.plist; the Settings toggle flips the persisted
// user preference at runtime via `automaticallyChecksForUpdates`.
final class UpdaterManager: NSObject {
    static let shared = UpdaterManager()

    private var controller: SPUStandardUpdaterController?

    private override init() { super.init() }

    /// Starts the updater. Call once from applicationDidFinishLaunching.
    /// `startingUpdater: true` is required for both manual and scheduled checks to work.
    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Shows Sparkle's update UI: checks the feed, and prompts if a newer version exists.
    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    /// Whether Sparkle performs scheduled background checks. Persisted by Sparkle.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
