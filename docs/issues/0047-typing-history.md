# 0047 — Typing history / personal vocabulary database

**Type:** AFK

## What to build

A local encrypted SQLite database of the user's accepted completions, used to bias future suggestions toward their actual vocabulary, phrasing, and names.

**Storage:** SQLite at `~/Library/Application Support/TabTypist/history.db`. Encryption key stored in macOS Keychain (`service: "TabTypist", account: "history-key"`). Schema: `(id INTEGER PRIMARY KEY, text TEXT, app_bundle_id TEXT, accepted_at INTEGER)`.

**Collection (accepted-only default):** On each `acceptCompletion` IPC event, write the accepted text and the app bundle ID to the database. Auto-exclude: password fields (`isSecureField`), entries shorter than 3 characters, and apps on the exclusion list.

**Retrieval:** At inference time in Rust, pass the last N accepted completions (most recent first, same app prioritised) to the prompt builder as `"This user often writes: …"`. Total contribution capped at the remaining budget after all higher-priority fields are filled.

**Strength slider:** A `UserDefaults` integer (0 = off, 1 = subtle, 2 = strong) controlling how many history entries are injected (0, 3, 8 respectively). Default: 1 (subtle).

**Opt-in to all-inputs mode:** A separate toggle to also record text typed even when no completion was accepted. Off by default.

**Model independence:** Switching model tier does not clear the database — history is model-agnostic.

## Acceptance criteria

- [ ] Fresh install: database is created on first accept; Keychain entry is present
- [ ] Accepted completions appear in future prompts (visible in debug log) when slider > 0
- [ ] Slider = 0: no history is injected
- [ ] Password fields are never recorded even when revealed
- [ ] Switching model tier leaves the database intact
- [ ] Database file is encrypted at rest (verify it is not readable as plain text)
- [ ] All-inputs toggle is off by default and requires explicit opt-in

## Blocked by

- [0033 — Instruct model inference path](0033-instruct-inference-path.md)
- [0040 — Visual context / OCR](0040-visual-context-ocr.md)
