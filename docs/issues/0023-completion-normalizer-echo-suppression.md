# 0023 — Completion normalizer + echo suppression

**Type:** AFK

## What to build

A single `normalize_completion(raw: String, prefix: &str) -> String` function in `model_runtime.rs`, called on every raw model output before it is sent to Swift as a `showOverlay` payload.

The function applies these passes in order:

1. **Chat token stripping** — remove `<|im_end|>`, `<|im_start|>`, `<|im_start|>assistant`, and any `<think>…</think>` blocks (including unclosed `<think>` tags where generation hit the token limit).
2. **Carriage-return collapse** — replace `\r` with nothing.
3. **Echo suppression** — find the longest suffix of `prefix` (by word) that matches a prefix of the completion, and strip it. Word-by-word overlap search, case-insensitive, up to 15 words deep. Returns `""` if the entire completion is an echo. This fixes the "cycling words" symptom where the model regurgitates the last word the user typed.
4. **Leading-whitespace normalisation** — if `prefix` ends with whitespace, strip any leading whitespace from the result to prevent double-spacing.

## Acceptance criteria

- [ ] `normalize_completion` is called in `do_complete` before the result is returned
- [ ] Chat tokens (`<|im_end|>` etc.) are stripped from output — verify with a stub completer that returns them
- [ ] `<think>complete block</think>` is stripped; partial `<think>unclosed` is also stripped
- [ ] Echo suppression: prefix ending `"hello world"`, completion `"world is great"` → `" is great"`
- [ ] Echo suppression: prefix ending `"I like"`, completion `"I like to eat"` → `""` (full echo)
- [ ] Leading-whitespace rule: prefix ends in space, completion `" great"` → `"great"`
- [ ] Leading-whitespace rule: prefix ends in word char, completion `" great"` passes through unchanged
- [ ] Unit tests cover all cases above

## Blocked by

None — can start immediately.
