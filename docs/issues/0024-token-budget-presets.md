# 0024 — Token budget presets (short / medium / long)

**Type:** AFK

## What to build

Replace the hardcoded `max_tokens: 25` passed to `completer.complete()` with a user-configurable three-tier preset stored in `SettingsStore`.

**Tiers:**

| Preset | Target words | Token budget |
|---|---|---|
| short | 3–7 | 11 |
| medium | 7–12 | 18 |
| long (default) | 12–20 | 30 |

**Formula:** `max(config_base, preset_budget)` where `config_base` starts at 8. Multi-line mode (issue 0025) will double this value capped at 60.

Changes span:
- `settings_store.rs` — add `completion_length: CompletionLength` enum (short / medium / long), default long
- `main.rs` — read preset, compute budget, pass to `completer.complete()`
- `ipc.rs` / Swift settings bridge — expose `updateSetting` handler for `completionLength`
- Settings UI — segmented control or dropdown with the three options

## Acceptance criteria

- [ ] `SettingsStore` persists `completion_length`; defaults to `long` on fresh install
- [ ] Core passes 30 tokens to the completer when preset is `long`
- [ ] Core passes 11 tokens when preset is `short`
- [ ] Changing the preset in settings takes effect on the next completion without restart
- [ ] Settings window shows the three options with label and approximate word-range hint
- [ ] Unit test covers the budget formula for all three presets

## Blocked by

None — can start immediately.
