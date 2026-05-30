# 0045 — HuggingFace model browser

**Type:** AFK

## What to build

A settings pane that lets power users search HuggingFace for any GGUF model, browse its files, and download it directly into TabTypist's models directory — without leaving the app.

**Search:** Text field that queries `GET https://huggingface.co/api/models?filter=gguf&search={query}&sort=downloads`. Results show repo ID, download count, and likes.

**File browser:** Selecting a result queries `GET https://huggingface.co/api/models/{repoId}/tree/main` and lists `.gguf` files with their sizes.

**Download:** Selecting a file triggers the existing `ModelDownloader` infrastructure with the HuggingFace CDN URL. Progress is shown inline. On completion the model appears in the tier picker as a custom entry with the raw filename as display name.

**Model type detection:** Attempt to infer `modelKind` from the filename (`.gguf` containing `-it`, `-Instruct` → instruct path; else base path).

## Acceptance criteria

- [ ] Searching "qwen3" returns relevant HuggingFace repos
- [ ] File list shows GGUF variants with sizes
- [ ] Downloading a model via the browser produces a working model that generates completions
- [ ] Custom models appear alongside built-in tiers in the model picker
- [ ] Download can be cancelled mid-way

## Blocked by

- [0032 — Model tier catalog](0032-model-tier-catalog.md)
