# 0029 — Text injection: AX set-value with Cmd+V fallback

**Type:** AFK

## What to build

Replace the current Cmd+V-only injection in `KeyCapture.swift` with a two-step approach that avoids clobbering the user's clipboard when possible.

**Step 1 — AX set-value:** Read the full field value via `AXUIElementCopyAttributeValue(kAXValueAttribute)`, insert the completion at the caret position, write back with `AXUIElementSetAttributeValue(kAXValueAttribute, newValue)`. Also advance the selection range to the new caret position with `kAXSelectedTextRangeAttribute`.

**Step 2 — Cmd+V fallback:** If AX write returns an error (most Electron and web-view apps reject it), fall back to the existing pasteboard + Cmd+V path.

**Per-app caching:** Store the injection method that succeeded per bundle ID in `UserDefaults`. On subsequent completions in the same app, try the cached method first. Reset cache entry if the cached method starts failing.

## Acceptance criteria

- [ ] In Notes.app: completion is inserted without touching `NSPasteboard.general`
- [ ] In a web textarea (Chrome): Cmd+V fallback fires; clipboard is clobbered only in this path
- [ ] Caret position after AX injection is correct (cursor is at end of inserted text)
- [ ] Per-app preference is cached and survives app restarts
- [ ] No regression in apps that currently work with Cmd+V

## Blocked by

None — can start immediately.
