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

    // Stability gate: suppress showOverlay calls for 150 ms after hide() to prevent
    // flicker from stale AX caret positions published right after acceptance.
    private var lastHideTime: Date = .distantPast
    private static let stabilityGateMs: Double = 0.15

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

    // ── Keycap hint pill ──────────────────────────────────────────────────────

    /// Number of accepted completions after which the hint pill is hidden permanently.
    private static let hintThreshold = 5

    static func shouldShowHint() -> Bool {
        let count = UserDefaults.standard.integer(forKey: "completionAcceptCount")
        return count < hintThreshold
    }

    static func recordAcceptance() {
        let count = UserDefaults.standard.integer(forKey: "completionAcceptCount")
        UserDefaults.standard.set(count + 1, forKey: "completionAcceptCount")
    }

    /// Build the attributed string for the keycap pill: "  Tab ⇥  " in a muted capsule.
    private static func pillAttributedString(opacity: CGFloat, fontSize: CGFloat) -> NSAttributedString {
        let pillFont = NSFont.monospacedSystemFont(ofSize: max(9, fontSize * 0.7), weight: .medium)
        let label = " Tab ⇥ "
        let pillColor = NSColor.secondaryLabelColor.withAlphaComponent(opacity * 0.9)
        let pillBg = NSColor.labelColor.withAlphaComponent(0.08)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: pillFont,
            .foregroundColor: pillColor,
            .backgroundColor: pillBg,
        ]
        return NSAttributedString(string: label, attributes: attrs)
    }

    // ── Show / hide ───────────────────────────────────────────────────────────

    // fontSize: AX-reported point size for the focused field (0 = unavailable, use estimate).
    func show(text: String, x: CGFloat, y: CGFloat, caretHeight: CGFloat,
              fontSize: CGFloat = 0, inputFrame: CGRect? = nil) {
        // Stability gate: ignore show() calls in the 150 ms window after hide().
        guard Date().timeIntervalSince(lastHideTime) >= OverlayWindow.stabilityGateMs else { return }
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

        // Inline fit check — include the hint pill width when it's showing.
        let ghostW = (text as NSString).size(withAttributes: [.font: font]).width
        let pillW: CGFloat = OverlayWindow.shouldShowHint()
            ? OverlayWindow.pillAttributedString(
                opacity: OverlayWindow.ghostOpacity(), fontSize: resolvedSize
              ).size().width
            : 0
        let singleLineW = ghostW + pillW + 4
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
        let showHint = OverlayWindow.shouldShowHint()
        let opacity = OverlayWindow.ghostOpacity()
        let resolvedFontSize = font.pointSize

        let fullAttr: NSAttributedString = {
            let ghost = NSMutableAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: OverlayWindow.ghostTextColor(),
            ])
            if showHint {
                ghost.append(OverlayWindow.pillAttributedString(opacity: opacity, fontSize: resolvedFontSize))
            }
            return ghost
        }()

        label.usesSingleLineMode = true
        label.cell?.wraps = false
        label.cell?.truncatesLastVisibleLine = false
        label.cell?.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.attributedStringValue = fullAttr

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

        let ghostBase = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: OverlayWindow.ghostTextColor(),
            .paragraphStyle: para,
        ])
        if OverlayWindow.shouldShowHint() {
            ghostBase.append(OverlayWindow.pillAttributedString(opacity: OverlayWindow.ghostOpacity(), fontSize: font.pointSize))
        }
        let attrStr: NSAttributedString = ghostBase

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

    // armStabilityGate: only true for acceptance/dismiss hides. After a paste the
    // host app briefly reports a stale AX caret, so we suppress shows for 150 ms to
    // avoid painting ghost text at the old position. The per-keystroke hide must NOT
    // arm the gate — it races the 75 ms inference debounce and would drop the
    // legitimate reposition for the new caret.
    func hide(armStabilityGate: Bool = false) {
        if armStabilityGate {
            // Acceptance / dismiss: arm the post-paste stability gate and use a brief
            // fade so the ghost text doesn't pop out abruptly after the user accepts.
            lastHideTime = Date()
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.08
                animator().alphaValue = 0
            }, completionHandler: {
                self.orderOut(nil)
            })
        } else {
            // Typing / app-switch: hide INSTANTLY. A fade here keeps the stale ghost
            // text on screen for ~80 ms while the user is already typing over it, so it
            // visibly lags behind the caret and overlaps the freshly typed characters.
            alphaValue = 0
            orderOut(nil)
        }
        KeyCapture.shared.clearCompletion()
    }
}
