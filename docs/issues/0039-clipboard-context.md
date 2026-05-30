# 0039 — Clipboard context (opt-in)

**Type:** AFK

## What to build

Optionally include the current clipboard contents in the completion prompt to improve suggestions when the user is working with recently copied material.

**Opt-in:** Settings toggle, off by default.

**Capture:** On each completion trigger (in Swift, before `contextUpdate` is sent), read `NSPasteboard.general.string(forType: .string)`. Pass as `clipboardContext` in the IPC payload.

**Relevance filter (Rust):** Skip injection if the clipboard text:
- Is empty or whitespace only
- Looks like code (> 30 % non-alphanumeric characters, or contains common code tokens like `{`, `=>`, `function`)
- Looks like a URL list (every line starts with `http`)
- Is longer than 1 200 characters (truncate to last 1 200 chars if so)

**Injection:** Formatted as `"Clipboard: {text}"`. Lowest priority before typing history — dropped silently if budget is exhausted.

## Acceptance criteria

- [ ] Toggle default is off; no clipboard read occurs when off
- [ ] With toggle on: copying a sentence and typing in a compose field produces a completion that references the copied content
- [ ] Code content on the clipboard is not injected
- [ ] URL-list content is not injected
- [ ] Budget is respected — clipboard is the first field dropped when budget fills

## Blocked by

- [0037 — Context prompt pipeline](0037-context-prompt-pipeline.md)
