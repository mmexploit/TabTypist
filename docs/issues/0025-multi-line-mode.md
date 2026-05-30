# 0025 — Multi-line mode toggle

**Type:** AFK

## What to build

Add an optional mode where completions span multiple lines. Off by default so the existing single-line behaviour is preserved.

**When on:** Stop at the first blank-line boundary (`\n\n`) instead of the first `\n`. Token budget doubles (capped at 60): a `long` preset becomes 60 instead of 30. The overlay `renderWrapped` path already handles multi-line display.

**When off (default):** Existing behaviour — truncate at the first `\n`.

Changes:
- `settings_store.rs` — add `multi_line_enabled: bool`, default `false`
- `main.rs` — compute budget as `if multi_line { min(budget * 2, 60) } else { budget }`
- `model_runtime.rs` — replace `ends_at_sentence_boundary` newline check with a blank-line check when multi-line is on
- Settings UI — toggle with label

## Acceptance criteria

- [ ] Default is off; existing `\n` truncation behaviour is unchanged
- [ ] With toggle on: completion continues past a single newline and stops at `\n\n`
- [ ] Token budget doubles (e.g. `long` → 60) when multi-line is on
- [ ] Budget never exceeds 60 regardless of preset
- [ ] Overlay renders multi-line completions without clipping

## Blocked by

- [0024 — Token budget presets](0024-token-budget-presets.md)
