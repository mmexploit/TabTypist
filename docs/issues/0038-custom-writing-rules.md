# 0038 — Custom writing rules: global + per-app

**Type:** AFK

## What to build

Let users steer completions with free-text directives that are appended to the instruct prompt.

**Global rules:** A text editor in Settings (Writing pane) where the user enters rules one per line (e.g. "avoid passive voice", "use British spelling"). Normalised on save: trimmed, deduplicated, capped at 10 rules, empty lines removed. Persisted in `UserDefaults`.

**Per-app rules:** A second text editor, visible after selecting an app from the active-app list in Settings. Rules are stored keyed by bundle ID. At inference time, per-app rules are appended after global rules (both within the 1 000-char budget).

**IPC:** Global and per-app rules are sent to Rust via `updateSetting`. Rust concatenates them, formats as `"Additional instructions: {rules}"`, and injects after the language hint.

## Acceptance criteria

- [ ] Global rules entered in settings appear in the instruct prompt on next completion
- [ ] Per-app rule for Mail differs from per-app rule for Messages; each is injected only in its app
- [ ] Saving more than 10 rules silently truncates to 10 (oldest dropped)
- [ ] Empty rules are ignored
- [ ] Changing rules takes effect without restart
- [ ] Rules are dropped silently if the 1 000-char budget is already exhausted by higher-priority fields

## Blocked by

- [0037 — Context prompt pipeline](0037-context-prompt-pipeline.md)
