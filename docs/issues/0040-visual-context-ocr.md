# 0040 — Visual context / OCR (region above field)

**Type:** AFK

## What to build

Capture the visible content above the focused text field and inject it as context into the completion prompt, enabling completions that are aware of the email being replied to, the document above the cursor, or the thread being responded to.

**Screen Recording permission:** Request at onboarding (after the Accessibility step). Make clear it is optional — the app still works without it, completions are just less context-aware. Permission state is re-checked on each capture attempt.

**Capture region:** `CGRect` from the top of the screen down to `inputFrame.origin.y` (Cocoa coords), cropped to the screen width. This captures what is visually above the text field without grabbing content below it.

**OCR:** Use `VNRecognizeTextRequest` (Vision framework, on-device, no network) on the captured image. Run on a background thread; do not block the poll loop.

**Filtering strategies (both shipped, B is default):**
- **(B) Proximity trim:** Take the last N characters of the joined OCR strings (physically closest to the input field). N = remaining budget after other context fields are filled. This naturally discards toolbars and menu bars at the top.
- **(C) Model distillation:** Run a summarisation pass through the loaded model to strip UI chrome and keep prose. Gate behind a `VisualDistillation` feature flag in `UserDefaults`. Measure end-to-end latency with and without; if C adds > 100 ms on the quality tier, keep B as permanent default.

**Budget:** OCR context is the highest-priority context signal (ADR 0006). It consumes its portion of the 1 000-char shared budget before other fields.

**IPC:** Pass the extracted text as a new `visualContext` field in the `contextUpdate` notification from Swift to Rust.

## Acceptance criteria

- [ ] Onboarding shows an optional Screen Recording step; skipping it does not block setup
- [ ] In Mail.app replying to an email: OCR text includes the sender's message body
- [ ] In Gmail (browser): OCR text includes visible thread content above the compose area
- [ ] OCR runs off the main thread; no perceptible input lag
- [ ] Strategy B (proximity trim) is the default; strategy C is togglable via feature flag
- [ ] Latency delta between B and C is logged to stderr for measurement
- [ ] No capture occurs in password fields or excluded apps
- [ ] All screenshots stay on-device; no network calls

## Blocked by

None — can start immediately.
