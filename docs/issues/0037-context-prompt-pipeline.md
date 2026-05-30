# 0037 — Context prompt pipeline: app name + user name + language targeting

**Type:** AFK

## What to build

Wire three lightweight context signals into the instruct prompt, each consuming from the shared 1 000-char budget (ADR 0006).

**App name:** `AXMonitor` already has `bundleId`. Resolve to a display name via `NSRunningApplication.runningApplications(withBundleIdentifier:).first?.localizedName` and pass it in the `contextUpdate` IPC message as `appDisplayName`. Rust injects: `"The user is typing in \(appDisplayName)."`.

**User name:** Optional free-text field in settings (Swift). Passed to Rust via `updateSetting { key: "userName", value: "…" }`. Injected as `"The user's name is \(name)."`. Empty string = skip.

**Language targeting:** Detect the dominant script of the last 200 characters of `prefix` (Latin, Ethiopic, Arabic, Cyrillic, CJK…) using Unicode block ranges. If non-Latin detected, inject `"The user is writing in \(language)."`. Ethiopic maps to "Amharic", etc. This surfaces the language-router work already in the codebase.

All three fields are injected after the length instruction, in the order: app → language → user name. Each is a single short sentence; combined overhead is < 80 chars.

## Acceptance criteria

- [ ] Instruct-path completions in Slack include "The user is typing in Slack." in the prompt (visible in debug log)
- [ ] Setting a user name in settings results in it being injected on the next completion
- [ ] Typing in Amharic (Ethiopic script): language hint appears automatically
- [ ] Typing in English: no language hint (Latin is the neutral baseline)
- [ ] All three fields respect the 1 000-char budget and are the first to be dropped if budget is exceeded

## Blocked by

- [0033 — Instruct model inference path](0033-instruct-inference-path.md)
