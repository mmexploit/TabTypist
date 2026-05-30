# 0030 — AXObserver notifications + adaptive poll backoff

**Type:** AFK

## What to build

Replace the fixed 50 ms poll-only loop in `AXMonitor` with a dual-track system that fires immediately on AX change events and uses the timer only as a backstop.

**AXObserver:** On every focus change (app activation or field change), register an `AXObserver` on the newly focused element for `kAXValueChangedNotification` and `kAXSelectedTextRangeChangedNotification`. The callback calls `poll()` directly. Tear down the observer when focus moves.

**Adaptive poll backoff:** Start the backstop timer at 80 ms. Track a consecutive-unchanged counter. After 5 unchanged polls, double the interval up to a ceiling of 200 ms. Reset to 80 ms the moment any change is detected. This cuts idle CPU by ~60 % on apps that post notifications reliably.

**Backstop purpose:** Apps that don't post AX notifications (some Electron builds, terminal emulators) still receive completions via the timer path.

## Acceptance criteria

- [ ] In Notes.app (reliable AX notifications): poll timer fires at 200 ms during idle; drops back to 80 ms on the next keystroke
- [ ] Ghost text still appears correctly in a Chrome textarea (no AX notifications — timer-only path)
- [ ] AXObserver is torn down and re-registered correctly on app switch
- [ ] No observer leak: registering in a tight focus-switch loop does not accumulate observers
- [ ] CPU usage while idle (no typing) is measurably lower than before this change

## Blocked by

None — can start immediately.
