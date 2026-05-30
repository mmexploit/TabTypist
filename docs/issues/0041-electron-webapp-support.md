# 0041 — Electron / web-app support via OCR caret estimate

**Type:** AFK

## What to build

Extend completions to Electron apps (Slack, Discord, Notion desktop) where `caretHeight = 0` because the AX layer does not expose caret geometry.

**Prefix extraction:** When OCR context is available (issue 0040) and `caretHeight = 0`, attempt to derive the prefix from the OCR text of the focused field area rather than from `kAXValueAttribute` (which often returns empty in Electron). Use the Vision bounding box of the last recognised text line as the caret position estimate.

**Overlay positioning:** Use the Vision bounding box bottom-right corner as the caret anchor. Fall back to the popup card mode (issue 0036) if the bounding box confidence is low.

**Exclusion engine:** Keep Electron apps on `defaultOn` with completion active but note the OCR dependency — if Screen Recording permission is denied, these apps silently produce no overlay (existing behaviour, no regression).

## Acceptance criteria

- [ ] In Slack desktop: ghost text appears after typing in a DM compose field
- [ ] Caret position estimate is close enough that the overlay does not overlap typed text
- [ ] No overlay appears in Slack if Screen Recording permission is not granted
- [ ] Native apps (Notes, Mail) are unaffected by this change

## Blocked by

- [0040 — Visual context / OCR](0040-visual-context-ocr.md)
