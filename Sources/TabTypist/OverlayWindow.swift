import AppKit
import Foundation

// Borderless NSPanel that renders ghost-text at the caret position.
final class OverlayWindow: NSPanel {
    private let label: NSTextField

    static let shared: OverlayWindow = {
        let w = OverlayWindow()
        return w
    }()

    private init() {
        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        label.textColor = NSColor.placeholderTextColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.sizeToFit()

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        hasShadow = false

        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(0.85)
            .cgColor
        container.layer?.cornerRadius = 4

        container.addSubview(label)
        contentView = container
    }

    func show(text: String, x: CGFloat, y: CGFloat, caretHeight: CGFloat) {
        label.stringValue = text
        label.sizeToFit()

        let padding: CGFloat = 4
        let width = label.frame.width + padding * 2
        let height = label.frame.height + padding * 2

        let frame = NSRect(x: x, y: y - caretHeight - height - 2, width: width, height: height)
        setFrame(frame, display: false)

        label.frame = NSRect(
            x: padding, y: padding,
            width: label.frame.width, height: label.frame.height
        )
        contentView?.frame = NSRect(origin: .zero, size: frame.size)

        orderFront(nil)
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
        KeyCapture.shared.clearCompletion()
    }
}
