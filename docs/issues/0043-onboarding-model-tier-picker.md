# 0043 — Onboarding: model tier picker with RAM auto-select

**Type:** AFK

## What to build

Replace the current single-model download screen in the onboarding flow with a tier picker that auto-selects the right model for the user's Mac and lets them override.

**Hardware detection:** Read `sysctl hw.memsize` in Swift at onboarding time. Map to recommended tier:
- < 16 GB → standard (Qwen3-1.7B, ~1 GB)
- 16 GB → quality (Gemma4-E2B-it, 3.1 GB)
- ≥ 24 GB → pro (Gemma4-E4B-it, 5.0 GB)

**UI:** A list of all 6 tiers showing model name, download size, and a "Recommended for your Mac" badge on the auto-selected entry. The user can select any tier. Nano is available but unlabelled as recommended (manual choice only).

**Download flow:** Unchanged from existing `startModelDownload` IPC flow, just parameterised by tier.

## Acceptance criteria

- [ ] On a 16 GB Mac, `quality` is pre-selected with the badge; all other tiers are selectable
- [ ] Download size is displayed for each tier
- [ ] Selecting a tier and clicking Download starts the correct model download
- [ ] Completing onboarding with any tier results in that model being loaded and producing completions
- [ ] Previously-installed models are detected and the tier is pre-selected without re-downloading

## Blocked by

- [0032 — Model tier catalog](0032-model-tier-catalog.md)
