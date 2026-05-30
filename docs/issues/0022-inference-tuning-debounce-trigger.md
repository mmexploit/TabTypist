# 0022 — Inference tuning: debounce 75 ms + trigger threshold

**Type:** AFK

## What to build

Two small configuration changes to the Rust core that make completions appear faster and fire on more keystrokes — bringing behaviour in line with industry standard.

1. **Debounce**: lower the watch-channel sleep in `main.rs` from 250 ms to 75 ms. This is the pause the core waits after the last keystroke before starting inference. KV cache reuse (already implemented) makes a triggered-but-stale call cheap, so a shorter debounce is now safe.

2. **Trigger threshold**: replace the `should_trigger_completion` word-count guard with `!prefix.trim().is_empty()`. Completions should fire as soon as any non-whitespace character exists in the field, not only after a complete word.

## Acceptance criteria

- [ ] Debounce constant in `main.rs` is 75 ms
- [ ] `should_trigger_completion` returns `true` for any prefix containing at least one non-whitespace character
- [ ] `should_trigger_completion` returns `false` for an empty or whitespace-only prefix
- [ ] Existing unit tests pass; add one test for each of the two threshold cases above
- [ ] Ghost text visibly appears faster after the last keystroke when typing in Notes

## Blocked by

None — can start immediately.
