# 0046 — Apple Intelligence backend (FoundationModels, macOS 26+)

**Type:** AFK

## What to build

Add a second inference backend that uses Apple's on-device `FoundationModels` framework (macOS 26+). Zero model download required; Apple manages the model lifecycle and privacy guarantees.

**Routing:** At app launch, check `FoundationModels.isAvailable`. If available and the user has selected the "Apple Intelligence" backend in settings, route all completion requests through it instead of the llama path. The llama path remains the default and the fallback.

**Prompt:** `FoundationModels` uses a larger shared context (~4 096 tokens). The instruct prompt structure from issue 0033 applies. Length instruction, app name, language hint, and custom rules are all included.

**Completion call:** Use `LanguageModel.shared.complete(prompt:maxTokens:)` (or equivalent API from the shipped framework). Run on a background actor. Apply the normaliser (0023) to the result before sending `showOverlay`.

**Settings:** Add "Apple Intelligence" as an engine option in the settings engine picker, shown only on macOS 26+.

## Acceptance criteria

- [ ] On macOS 26+ with Apple Intelligence available: selecting the backend produces completions without any GGUF model installed
- [ ] On macOS < 26 or when Apple Intelligence is unavailable: the option is hidden; llama path is used
- [ ] Completion normaliser runs on Apple Intelligence output (chat tokens, echo suppression)
- [ ] Switching engine in settings takes effect without restart
- [ ] No GGUF model download is triggered or required when this backend is active

## Blocked by

None — can start immediately.
