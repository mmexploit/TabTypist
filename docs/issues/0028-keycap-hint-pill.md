# 0028 — Keycap hint pill in ghost text

**Type:** AFK

## What to build

Render a small "Tab ⇥" pill glyph immediately after the ghost text in the overlay window. The pill teaches first-time users what key to press. It disappears permanently after the user has accepted N completions (default: 5), signalling they have learned the interaction.

Changes:
- `OverlayWindow.swift` — append the pill as a styled attributed-string suffix: rounded-rect background in a muted system colour, monospaced "⇥" glyph, smaller font size than the ghost text.
- `OverlayWindow.swift` — accept a `showHint: Bool` parameter in `show(text:…)`.
- `KeyCapture.swift` / `TabTypistApp.swift` — track acceptance count in `UserDefaults`; pass `showHint: false` once count ≥ 5.
- Pill inherits the ghost text's alpha value so it fades consistently.

## Acceptance criteria

- [ ] Pill is visible on the first 5 acceptances (fresh install)
- [ ] Pill is absent after the 5th acceptance and on all subsequent launches
- [ ] Pill does not extend beyond the screen right edge (clamped with ghost text)
- [ ] Pill alpha matches the ghost text opacity setting (issue 0034)
- [ ] No pill is shown when a completion is dismissed without accepting

## Blocked by

None — can start immediately.
