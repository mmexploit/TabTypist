# 0026 — Full-accept shortcut (backtick, configurable)

**Type:** AFK

## What to build

Add a second acceptance key that accepts the **entire remaining completion** in one keystroke. Industry standard default is the backtick key (`` ` ``, `kVK_ANSI_Grave`, keycode 50 — the key directly above Tab on most keyboards). Tab continues to accept one word at a time.

Changes:
- `KeyCapture.swift` — intercept the configured full-accept keycode in the CGEventTap. When a completion is visible: consume the event, call `insertCompletion(pendingCompletionText)`, clear completion state, notify Rust `acceptCompletion`.
- `SettingsStore` (Swift) — persist `fullAcceptKeyCode: CGKeyCode`, default 50 (backtick). Expose a key-recorder UI in settings so users on international keyboards (where that slot is `§` or `^`) can remap it.
- If the configured keycode is 0 / `disabled`, the full-accept shortcut is off — only Tab works.

## Acceptance criteria

- [ ] Pressing backtick while a completion is visible accepts the entire remaining text
- [ ] Tab continues to accept one word at a time (existing behaviour unchanged)
- [ ] Backtick passes through normally when no completion is visible
- [ ] Full-accept keycode is configurable in settings; change takes effect immediately
- [ ] Setting keycode to `disabled` turns off the shortcut without affecting Tab
- [ ] `acceptCompletion` IPC notification fires (telemetry counts full accepts correctly)
- [ ] Tested on a keyboard where backtick position produces a different character

## Blocked by

None — can start immediately.
