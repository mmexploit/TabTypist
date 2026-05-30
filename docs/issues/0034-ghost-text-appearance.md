# 0034 — Ghost text appearance: opacity slider + colour picker

**Type:** AFK

## What to build

Let users control how the ghost text looks in `OverlayWindow`.

**Opacity:** An `NSSlider` (30–100 %, step 10 %, default 40 %) in the settings window. The value is applied as `label.textColor = NSColor.labelColor.withAlphaComponent(opacity)`. Changes take effect on the next overlay show.

**Colour:** An `NSColorWell` in the settings window backed by a hex string in `UserDefaults`. When set, it overrides the base `labelColor` (opacity still applies on top). A "Reset to default" button clears the override.

Both values are read by `OverlayWindow.show()` on each call so live changes are immediately reflected.

## Acceptance criteria

- [ ] Opacity slider from 30 % to 100 % visibly changes ghost text transparency
- [ ] Default opacity is 40 %
- [ ] Custom colour is applied; reset clears it back to system `labelColor`
- [ ] Both settings persist across restarts
- [ ] Keycap hint pill (issue 0028) inherits the same opacity value

## Blocked by

None — can start immediately.
