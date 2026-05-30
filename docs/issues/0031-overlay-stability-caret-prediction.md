# 0031 — Overlay stability gate + caret position prediction post-accept

**Type:** AFK

## What to build

Two related overlay reliability improvements that reduce flicker and misalignment after acceptance.

**Overlay stability gate:** After `OverlayWindow.hide()` is called, suppress any `showOverlay` call for 150 ms. This prevents the overlay from flickering back into view when AX publishes a stale caret position in the poll immediately after acceptance. Implemented as a timestamp in `OverlayWindow` checked inside `show()`.

**Caret position prediction post-accept:** After Cmd+V injection, the AX caret rect lags by 1–2 poll cycles (50–160 ms). During this window, if a new completion arrives, it appears at the old caret position. Fix: in `AXMonitor`, track a rolling average of character width from the last N AX frame measurements (`caretRect.width / 1` for single-char queries). After acceptance, advance the predicted caret X by `acceptedText.count × avgCharWidth` and use that for overlay positioning until the next real AX update arrives.

## Acceptance criteria

- [ ] Accepting a completion in Notes does not produce a visible overlay flicker
- [ ] Ghost text for the next completion appears at the correct caret position, not the pre-acceptance position
- [ ] Stability gate does not delay completions in normal typing (only suppresses the immediate post-accept window)
- [ ] Average char-width estimate is reset on app switch and font-size change

## Blocked by

- [0030 — AXObserver + adaptive poll backoff](0030-axobserver-adaptive-backoff.md)
