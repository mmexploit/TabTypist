# ADR 0006 — Prompt context budget and injection priority

## Status
Accepted

## Context

TabTypist's instruct-model path (Gemma4, and any future instruct tier) injects several
context signals into the prompt alongside the user's prefix text: visual OCR context,
app name, language hint, user name, custom rules, clipboard, and typing history.

These signals compete for the model's attention budget. The model is only generating
8–30 tokens per completion, so a long system prompt can crowd out the prefix text and
degrade rather than improve quality. Industry data (confirmed by the developer of a
competing app) shows custom instructions and typing history have surprisingly limited
impact precisely because of this attention dilution.

The context window for the local llama path is kept small intentionally: large prefix
windows hurt latency with little quality gain because TabTypist completes the immediate
local continuation, not the whole document.

## Decision

**Hard cap: 1 000 characters total** across all injected context fields, independent of
model tier. Larger models do not receive a larger budget — the constraint is attention
quality, not context-window size.

When the budget is exhausted, lower-priority fields are silently dropped rather than
truncated mid-sentence. Injection priority order (highest to lowest signal):

1. Visual OCR context (screenshot above field — email reply, document above cursor)
2. App name
3. Language instruction
4. User name
5. Custom writing rules
6. Clipboard context (opt-in only)
7. Typing history excerpts (opt-in only, lowest confirmed signal)

The prefix text itself (what the user has typed) is never counted against this budget —
it is always injected in full (with its own separate truncation at `maxPrefixCharacters`).

## Consequences

- Simple to reason about and test: no per-tier branching in the prompt builder.
- Visual OCR context always wins the budget battle, which matches the use case with the
  highest confirmed quality gain (reply-to threads in Mail/Gmail).
- Typing history will often be dropped entirely at first; this is acceptable given its
  low confirmed impact. Revisit if experiments show otherwise.
- If a user writes very long custom rules they may crowd out clipboard context — this is
  intentional, as user-authored rules are higher priority.
- Budget can be raised in a future ADR once ablation experiments quantify the
  attention-dilution tradeoff more precisely.
