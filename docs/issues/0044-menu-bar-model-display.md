# 0044 — Menu bar: active model / tier display

**Type:** AFK

## What to build

Show the currently loaded model tier name in the menu bar popover so users always know which model is active and can navigate to settings to change it.

**Location:** In `MenuBarController`, add a section at the top of the popover showing the tier name (e.g. "quality — Gemma4-E2B") and a "Change model…" link that opens the Engine & Model settings pane.

**State:** The loaded tier is known to the Rust core after `model_runtime::LlamaCppCompleter::load()` succeeds. Send a `modelLoaded` IPC notification from Rust to Swift on successful load with `{ "tier": "quality", "displayName": "Gemma4-E2B-it" }`. Swift stores it and the menu bar reads from that stored value.

**Loading state:** While no model is loaded (download in progress, cold start), show "Loading model…" in that slot.

## Acceptance criteria

- [ ] Menu bar popover shows the active tier name after a model is loaded
- [ ] Shows "Loading model…" during the download / load phase
- [ ] "Change model…" opens the correct settings pane
- [ ] Tier display updates immediately after switching models in settings without restart

## Blocked by

- [0032 — Model tier catalog](0032-model-tier-catalog.md)
