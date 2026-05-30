# 0042 — Terminal support (opt-in)

**Type:** AFK

## What to build

Allow TabTypist to generate completions inside terminal emulators (Terminal.app, iTerm2) on an opt-in basis. Disabled by default to avoid dangerous suggestions at arbitrary shell prompts.

**Opt-in:** A per-app toggle in the exclusion engine settings. Terminal bundle IDs (`com.apple.Terminal`, `com.googlecode.iterm2`) remain on the `defaultOff` list; the user must explicitly enable them.

**Prompt-character detection:** When active in a terminal, only trigger completions when the prefix text ends with a known prompt suffix — a line ending in `$ `, `> `, `❯ `, `% `, or `# `. This prevents suggestions mid-command or in interactive programs (vim, htop, etc.).

**Safety:** Completions in terminals must not auto-accept or have reduced Escape-dismiss latency. The standard Tab / backtick / Escape flow is unchanged.

## Acceptance criteria

- [ ] Terminal apps are excluded (no completions) on a fresh install
- [ ] User can enable Terminal in the exclusion settings; completions appear after shell prompts
- [ ] No completion fires mid-command (e.g. while the cursor is inside `git commit -m "`)
- [ ] Escape dismisses the completion without inserting anything
- [ ] Re-disabling Terminal in settings stops completions immediately

## Blocked by

None — can start immediately.
