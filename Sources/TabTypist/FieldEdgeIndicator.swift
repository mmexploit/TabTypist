import AppKit

// A small non-interactive NSPanel anchored to the right edge of the focused text field
// to indicate that TabTypist is active.  Invisible when completions are excluded.
final class FieldEdgeIndicator: NSPanel {
    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }

    static let shared = FieldEdgeIndicator()

    private let iconView: NSTextField

    private init() {
        iconView = NSTextField(labelWithString: "⌨")
        iconView.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        iconView.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.7)
        iconView.backgroundColor = .clear
        iconView.alignment = .center

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 20, height: 20),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        isOpaque = false
        backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.7)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        hasShadow = false
        contentView = iconView
    }

    func show(inputFrame: CGRect) {
        guard inputFrame.width > 10 && inputFrame.height > 10 else { hide(); return }
        let iconSize: CGFloat = 18
        let padding: CGFloat = 4
        let fx = inputFrame.maxX - iconSize - padding
        let fy = inputFrame.midY - iconSize / 2

        setFrame(NSRect(x: fx, y: fy, width: iconSize, height: iconSize), display: true)
        contentView?.frame = NSRect(origin: .zero, size: frame.size)
        alphaValue = 1
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }
}
