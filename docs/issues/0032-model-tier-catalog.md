# 0032 — Model tier catalog: 6-tier expansion with hardware auto-select

**Type:** AFK

## What to build

Expand `ModelCatalog` in `model_downloader.rs` from a single English entry to six tiers mixing Qwen3 base and Gemma4 instruct models. Add hardware-aware auto-selection at onboarding.

**Tier catalog:**

| Tier | Model | Size | Min RAM |
|---|---|---|---|
| nano | SmolLM2-135M-Instruct Q8_0 | 0.1 GB | any |
| mini | Qwen3-0.6B Q4_K_M | 0.4 GB | 8 GB |
| standard | Qwen3-1.7B Q4_K_M | ~1 GB | 8 GB |
| performance | Qwen3-4B Q4_K_M | ~2.3 GB | 16 GB |
| quality | Gemma4-E2B-it Q4_K_M | 3.1 GB | 16 GB |
| pro | Gemma4-E4B-it Q4_K_M | 5.0 GB | 24 GB |

**Hardware auto-select (Swift, onboarding):** Read physical RAM via `sysctl hw.memsize`. Pre-select **quality** (3.1 GB) for 16 GB Macs and **pro** for 24 GB+. Never auto-select upward — show the full list as an override dropdown so the user can go smaller. Display download size and minimum RAM requirement for each tier.

**Model type flag:** Each catalog entry carries a `modelKind: .base | .instruct` field. The inference layer (issue 0033) uses this to choose the right completion path at load time.

## Acceptance criteria

- [ ] All 6 tiers appear in the onboarding model picker with correct names, sizes, and RAM labels
- [ ] On a 16 GB Mac, `quality` (Gemma4-E2B) is pre-selected
- [ ] On an 8 GB Mac, `standard` (Qwen3-1.7B) is pre-selected
- [ ] User can override to any tier and the choice is persisted
- [ ] Each entry has a correct HuggingFace download URL and SHA-256 checksum
- [ ] Download, verify, and load flow works for at least one new entry (nano or mini)
- [ ] `modelKind` field is present on every catalog entry

## Blocked by

None — can start immediately.
