# 0033 — Instruct model inference path

**Type:** AFK

## What to build

Add a second inference code path for instruct-tuned models (Gemma4-E2B, Gemma4-E4B, SmolLM2-Instruct). The base path (current `do_complete`) is unchanged. The instruct path builds a structured system prompt and passes it to the model instead of raw prefix continuation.

**Routing:** `LlamaCppCompleter::load()` inspects the model filename. If it contains `-it`, `-Instruct`, or similar markers, it sets `self.is_instruct = true`. Alternatively, use the `modelKind` field from the catalog (issue 0032).

**Instruct prompt structure (within 1 000-char context budget, ADR 0006):**

```
[SYSTEM]
Complete the user's text. {completionLengthInstruction}.
{appNameContext}
{languageInstruction}
{userNameContext}
{customRules}
{visualContext}
[/SYSTEM]
[USER]
{prefix}
```

`completionLengthInstruction` is derived from the active token preset (issue 0024): "Return only the next 3 to 7 words.", etc.

**Normaliser:** The completion normaliser from issue 0023 is mandatory on the instruct path to strip chat template tokens and echo.

**Base path unchanged:** When `is_instruct = false`, `do_complete` behaves exactly as today.

## Acceptance criteria

- [ ] Loading Gemma4-E2B-it routes to the instruct path; loading Qwen3-0.6B routes to base path
- [ ] Instruct path produces completions in Notes and Mail
- [ ] Normaliser runs on instruct output — no `<|im_end|>` visible in ghost text
- [ ] Length instruction matches the active preset ("3 to 7 words" for short, etc.)
- [ ] Base path output is byte-for-byte identical to before this change

## Blocked by

- [0032 — Model tier catalog](0032-model-tier-catalog.md)
- [0023 — Completion normalizer + echo suppression](0023-completion-normalizer-echo-suppression.md)
