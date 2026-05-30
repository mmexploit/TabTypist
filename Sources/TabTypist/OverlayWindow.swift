import AppKit
import Foundation

// ── NSColor hex helper ────────────────────────────────────────────────────────

private extension NSColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            srgbRed:   CGFloat((value >> 16) & 0xFF) / 255,
            green:     CGFloat((value >>  8) & 0xFF) / 255,
            blue:      CGFloat( value        & 0xFF) / 255,
            alpha:     1
        )
    }
}

// ── Borderless NSPanel that renders inline ghost text at the caret position. ─
final class OverlayWindow: NSPanel {
    // Hard-disable key/main status. With .nonactivatingPanel the panel can still
    // become the *key* window of our (accessory) app, which on some macOS builds
    // affects how the next key event is routed before our CGEventTap sees it.
    // 's OverlayController does the same override for the same reason.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private let label: NSTextField

    static let shared: OverlayWindow = OverlayWindow()

    private init() {
        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        label.textColor = NSColor.labelColor.withAlphaComponent(0.4)  // overridden on every show
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.cell?.wraps = false
        label.cell?.truncatesLastVisibleLine = false

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        hasShadow = false

        contentView = label
    }

    // ── Appearance helpers ────────────────────────────────────────────────────

    /// Ghost-text opacity (30–100 %; default 40 %).  Read from UserDefaults on every
    /// call so a settings change takes effect immediately without restart.
    static func ghostOpacity() -> CGFloat {
        guard UserDefaults.standard.object(forKey: "ghostTextOpacity") != nil else { return 0.4 }
        return max(0.3, min(1.0, CGFloat(UserDefaults.standard.double(forKey: "ghostTextOpacity"))))
    }

    /// Resolved ghost-text color.  Applies the user-chosen colour (or labelColor)
    /// plus the opacity setting.
    static func ghostTextColor() -> NSColor {
        let base: NSColor
        if let hex = UserDefaults.standard.string(forKey: "ghostTextColorHex"),
           let custom = NSColor(hexString: hex) {
            base = custom
        } else {
            base = .labelColor
        }
        return base.withAlphaComponent(ghostOpacity())
    }

    // ── Show / hide ───────────────────────────────────────────────────────────

    // fontSize: AX-reported point size for the focused field (0 = unavailable, use estimate).
    func show(text: String, x: CGFloat, y: CGFloat, caretHeight: CGFloat,
              fontSize: CGFloat = 0, inputFrame: CGRect? = nil) {
        // Prefer the AX-reported font size; fall back to caret-height proportion.
        let resolvedSize = fontSize > 4 ? fontSize : max(10, caretHeight * 0.75)
        let font = NSFont.systemFont(ofSize: resolvedSize, weight: .regular)

        // Use the screen that actually contains the caret, not always the primary display.
        let caretPoint = NSPoint(x: x, y: y)
        let screen = NSScreen.screens.first(where: { NSMouseInRect(caretPoint, $0.frame, false) })
            ?? NSScreen.screens.first ?? NSScreen.main!
        let safe = screen.visibleFrame

        // Usable width boundary for word-wrap column (field bounds clamped to screen).
        let usable: CGRect = {
            if let f = inputFrame {
                let padded = f.insetBy(dx: 4, dy: 0)
                let inter = padded.intersection(safe)
                return inter.isEmpty ? safe : inter
            }
            return safe
        }()

        // Inline fit check uses the screen right edge (not field right edge) so single-line
        // suggestions aren't prematurely wrapped in narrow fields.
        let singleLineW = (text as NSString).size(withAttributes: [.font: font]).width + 4
        let availableInline = max(20, safe.maxX - x)

        if singleLineW <= availableInline {
            renderSingleLine(text: text, font: font, caretX: x, caretY: y,
                             caretHeight: caretHeight, usable: usable, panelW: singleLineW)
        } else {
            renderWrapped(text: text, font: font, caretX: x, caretY: y,
                          caretHeight: caretHeight, usable: usable, safe: safe)
        }
    }

    private func renderSingleLine(
        text: String, font: NSFont, caretX: CGFloat, caretY: CGFloat,
        caretHeight: CGFloat, usable: CGRect, panelW: CGFloat
    ) {
        label.font = font
        label.textColor = OverlayWindow.ghostTextColor()
        label.usesSingleLineMode = true
        label.cell?.wraps = false
        label.cell?.truncatesLastVisibleLine = false
        label.cell?.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.stringValue = text

        // Panel height = caret height exactly so text sits on the same baseline as the
        // host app's line. Using max(textHeight, caretHeight) caused the panel to extend
        // above the caret when the font rendered taller than the caret, skewing text up.
        let textH = (text as NSString).size(withAttributes: [.font: font]).height
        let panelH = max(textH, caretHeight)
        let rawY = caretY - caretHeight          // panel bottom aligns with caret bottom
        let fx = max(usable.minX, min(caretX, usable.maxX - panelW))
        let fy = max(usable.minY, min(rawY, usable.maxY - panelH))

        fputs("overlay(1L): (\(Int(fx)),\(Int(fy))) \(Int(panelW))×\(Int(panelH)) \"\(text.prefix(30))\"\n", stderr)

        setFrame(NSRect(x: fx, y: fy, width: max(panelW, 20), height: panelH), display: true)
        contentView?.frame = NSRect(origin: .zero, size: frame.size)
        alphaValue = 1
        orderFront(nil)
    }

    private func renderWrapped(
        text: String, font: NSFont, caretX: CGFloat, caretY: CGFloat,
        caretHeight: CGFloat, usable: CGRect, safe: CGRect
    ) {
        // Panel spans the field's usable width. First line is indented to the caret via
        // firstLineHeadIndent; overflow lines are flush with the field's left edge.
        let panelX = usable.minX
        let panelW = max(40, usable.width)
        let firstLineIndent = max(0, caretX - panelX)

        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = firstLineIndent
        para.headIndent = 0
        para.lineBreakMode = .byWordWrapping
        para.lineSpacing = 0

        let attrStr = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: OverlayWindow.ghostTextColor(),
            .paragraphStyle: para,
        ])

        label.font = font
        label.usesSingleLineMode = false
        label.maximumNumberOfLines = 0
        label.cell?.wraps = true
        label.cell?.truncatesLastVisibleLine = true
        label.cell?.lineBreakMode = .byWordWrapping
        label.attributedStringValue = attrStr

        let measureWidth = max(20, panelW - 4)
        let bounds = attrStr.boundingRect(
            with: CGSize(width: measureWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let fullPanelH = max(ceil(bounds.height) + 2, caretHeight)

        // Anchor: panel TOP = caretY (top of the caret line in Cocoa y-up coords).
        // Extend DOWNWARD from there. Only clamp at the screen bottom — never push the
        // panel above the caret, which would cover content and break small text boxes
        // like Telegram's chat input where there is no room above.
        let panelTopY  = caretY
        let idealBotY  = panelTopY - fullPanelH
        let clampedBotY = max(safe.minY, idealBotY)
        let actualPanelH = max(caretHeight, panelTopY - clampedBotY)

        let fx = max(safe.minX, min(panelX, safe.maxX - panelW))

        fputs("overlay(ML): (\(Int(fx)),\(Int(clampedBotY))) \(Int(panelW))×\(Int(actualPanelH)) indent=\(Int(firstLineIndent)) \"\(text.prefix(30))\"\n", stderr)

        setFrame(NSRect(x: fx, y: clampedBotY, width: panelW, height: actualPanelH), display: true)
        contentView?.frame = NSRect(origin: .zero, size: frame.size)
        alphaValue = 1
        orderFront(nil)
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
