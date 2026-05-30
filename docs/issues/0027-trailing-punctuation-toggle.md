# 0027 — Auto-accept trailing punctuation toggle

**Type:** AFK

## What to build

When **off**, word-by-word Tab acceptance stops before trailing punctuation. Accepting "you?" yields "you" on the first Tab and "?" on the second. When **on** (default), the current behaviour is preserved — the entire token including punctuation is accepted at once.

Changes:
- `KeyCapture.swift` — modify `nextWord(from:)` to accept an `autoAcceptTrailingPunctuation: Bool` parameter. When `false`, trim trailing non-alphanumeric characters from the chunk and return them as the head of the remaining text.
- `SettingsStore` (Swift) — persist `autoAcceptTrailingPunctuation: Bool`, default `true`.
- Settings UI — toggle with label.

## Acceptance criteria

- [ ] Toggle default is **on**; existing word-by-word behaviour is unchanged
- [ ] With toggle **off**: completion `"you? Really"` → first Tab accepts `"you"`, second accepts `"?"`, third accepts `" Really"`
- [ ] Punctuation inside a word (`don't`, `U.S.A`) is not split off — only trailing punctuation is
- [ ] Setting persists across restarts

## Blocked by

None — can start immediately.
