import AppKit

// Floating card shown when the AX caret is unreliable (Firefox, some Electron apps).
// Positioned just below the focused text field instead of inline at the caret.
final class PopupCardWindow: NSPanel {
    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }

    static let shared = PopupCardWindow()

    private let label: NSTextField

    private init() {
        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        label.textColor = NSColor.labelColor.withAlphaComponent(0.5)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.cell?.wraps = true
        label.cell?.truncatesLastVisibleLine = true
        label.maximumNumberOfLines = 3

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        isOpaque = false
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        hasShadow = true
        contentView = label
    }

    /// Known-unreliable bundle IDs that trigger popup mode automatically.
    static let unreliableBundles: Set<String> = [
        "org.mozilla.firefox",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
    ]

    /// True when popup mode should be used for the given app (automatic or user-pinned).
    static func shouldUsePopup(bundleId: String, caretHeight: CGFloat) -> Bool {
        if caretHeight == 0 { return true }
        let pinned = UserDefaults.standard.string(forKey: "overlayMode.\(bundleId)")
        if pinned == "popup" { return true }
        if pinned == "inline" { return false }
        return unreliableBundles.contains(bundleId)
    }

    func show(text: String, inputFrame: CGRect) {
        guard inputFrame.width > 10 else { return }

        let cardPadding: CGFloat = 8
        let cardGap: CGFloat = 4
        let maxW = min(inputFrame.width - cardPadding * 2, 360)

        label.textColor = OverlayWindow.ghostTextColor()
        label.font = NSFont.systemFont(ofSize: 13, weight: .regular)

        // Include hint pill text if applicable.
        let displayText = OverlayWindow.shouldShowHint() ? text + "  Tab ⇥ " : text
        label.stringValue = displayText

        let measured = (displayText as NSString).boundingRect(
            with: CGSize(width: maxW - cardPadding * 2, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: label.font!]
        )
        let cardW = max(120, min(measured.width + cardPadding * 2 + 4, maxW))
        let cardH = max(30, measured.height + cardPadding * 2)

        // Position: just below the field bottom edge.
        let fx = inputFrame.minX + cardPadding
        let fy = inputFrame.minY - cardH - cardGap

        // Clamp to screen bottom.
        let clampedY = max(
            (NSScreen.screens.first?.visibleFrame.minY ?? 0),
            fy
        )

        setFrame(NSRect(x: fx, y: clampedY, width: cardW, height: cardH), display: true)
        contentView?.frame = NSRect(origin: .zero, size: frame.size)
        alphaValue = 1
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }
}
