# 0036 — Mirror / popup card mode for unreliable AX caret

**Type:** AFK

## What to build

An alternative completion presentation for apps where the AX caret position is unreliable or unavailable (Firefox, some Electron apps, apps with `caretHeight = 0`). Instead of inline ghost text anchored to the caret, a floating card is rendered near the bottom edge of the input field.

**Auto-detection:** Trigger popup mode when `caretHeight == 0` or when the bundle ID is on a known-unreliable list (e.g. `org.mozilla.firefox`). Per-app preference is persisted so the user can override.

**Card layout:** A small `NSPanel` with a rounded-rect background (system material), the completion text in the ghost colour, and the keycap hint pill. Positioned at `(inputFrame.minX + padding, inputFrame.minY - cardHeight - gap)` — just below the field bottom.

**Inline mode unchanged:** Apps with reliable AX caret continue using the existing `OverlayWindow` inline path.

## Acceptance criteria

- [ ] In Firefox, a popup card appears below the focused textarea with the completion text
- [ ] In Notes.app (reliable AX), inline ghost text is used — no regression
- [ ] User can pin popup or inline mode per app in settings
- [ ] Card does not appear outside the screen bounds (clamped)
- [ ] Accepting via Tab / backtick works identically in both modes

## Blocked by

- [0030 — AXObserver + adaptive poll backoff](0030-axobserver-adaptive-backoff.md)
