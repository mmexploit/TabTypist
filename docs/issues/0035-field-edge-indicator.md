# 0035 — Field-edge active indicator icon

**Type:** AFK

## What to build

A small, non-interactive icon anchored to the right edge of the focused text field indicating that TabTypist is active in that field. It should not interfere with typing and must disappear when the app is excluded.

Implementation: a tiny borderless `NSPanel` (similar to `OverlayWindow`) positioned at `(inputFrame.maxX - iconWidth - padding, inputFrame.midY)` in screen coordinates. Displays a small template image (a miniature keyboard or checkmark glyph). Hidden when `completions_active` is false for the current app.

`AXMonitor` already receives `inputFrame` from AX — use that to position the icon on each poll. Hide on app switch and when the exclusion engine returns a non-active verdict.

## Acceptance criteria

- [ ] Icon is visible in Notes, Mail, and Messages when TabTypist is active
- [ ] Icon is absent in excluded apps (1Password, password fields)
- [ ] Icon does not steal focus or intercept mouse events
- [ ] Icon repositions correctly when the window is moved or resized
- [ ] Icon is hidden when TabTypist is globally paused from the menu bar

## Blocked by

None — can start immediately.
