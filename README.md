<div align="center">

<img src="Resources/AppIcon-source.png" alt="TabTypist" width="140" height="140" />

<h1>TabTypist <sup><sub>beta</sub></sup></h1>

### On-device AI autocomplete for every app on your Mac.

<em>No cloud. No subscriptions. Your text never leaves your machine.</em>

<br/>

<p>
  <a href="https://github.com/mmexploit/TabTypist/releases/latest"><img src="https://img.shields.io/badge/Download_for_Mac-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="Download for Mac" /></a>
  <a href="#build-from-source"><img src="https://img.shields.io/badge/Build_from_source-2B2B2B?style=for-the-badge&logo=swift&logoColor=white" alt="Build from source" /></a>
  <a href="https://github.com/mmexploit/TabTypist/issues"><img src="https://img.shields.io/badge/Report_a_bug-FFFFFF?style=for-the-badge&logo=github&logoColor=black" alt="Report a bug" /></a>
</p>

<p>
  <a href="https://github.com/mmexploit/TabTypist/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/mmexploit/TabTypist/ci.yml?branch=main&label=build" alt="Build status" /></a>
  <img src="https://img.shields.io/badge/license-FSL--1.1-blue" alt="License: FSL-1.1" />
  <a href="https://github.com/mmexploit/TabTypist/releases"><img src="https://img.shields.io/github/v/release/mmexploit/TabTypist?include_prereleases&label=release" alt="Latest release" /></a>
  <a href="https://github.com/mmexploit/TabTypist/releases"><img src="https://img.shields.io/github/downloads/mmexploit/TabTypist/total?label=downloads" alt="Downloads" /></a>
  <a href="https://github.com/mmexploit/TabTypist/stargazers"><img src="https://img.shields.io/github/stars/mmexploit/TabTypist?label=stars" alt="Stars" /></a>
  <img src="https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white" alt="Swift" />
  <img src="https://img.shields.io/badge/platform-macOS_14%2B-lightgrey" alt="Platform: macOS 14+" />
</p>

</div>

---

Start typing anywhere. After a brief pause, a grey suggestion appears right at your caret. Press **Tab** to accept a word, **`** (backtick) to accept the whole thing, or **Esc** to dismiss.

## ✨ Features

- **Works system-wide** — text editors, email, chat apps, browsers, anything with a text field
- **100% on-device** — inference runs locally via `llama.cpp`; no text ever leaves your Mac
- **Six model tiers** — Nano → Pro, so you can match quality to your hardware
- **Context-aware** — optionally reads on-screen text near the field via on-device OCR for sharper suggestions
- **Tab to accept, word by word** — take one word at a time or the full completion in a single key
- **Yours to shape** — configurable completion length, personal writing-style rules, and per-app exclusions
- **Light on your machine** — lazy keyboard tap, off-main IPC, and bounded OCR keep typing snappy
- **Stays current** — built-in auto-updates (Sparkle) check daily and update in place; toggle them in Settings

## 📦 Install

1. **[Download the latest `.dmg`](https://github.com/mmexploit/TabTypist/releases/latest)** and drag TabTypist to Applications.
2. First launch: right-click the app → **Open** (the beta is ad-hoc signed, so Gatekeeper asks once).
3. Grant **Accessibility** and **Input Monitoring** when prompted, then finish onboarding and pick a model tier.

## 🖥 Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel Mac with at least 8 GB RAM (4 GB for the Nano tier)

## 🔐 Permissions

TabTypist needs two permissions to function, plus one optional one:

| Permission | Why |
|---|---|
| **Accessibility** | Read caret position; insert text when you press Tab |
| **Input Monitoring** | Detect Tab and Escape keypresses |
| **Screen Recording** *(optional)* | On-device OCR of nearby text for context-aware suggestions |

Grant these in **System Settings → Privacy & Security**.

## 🧩 Model Tiers

| Tier | Size | Min RAM |
|---|---|---|
| Nano | 0.4 GB | Any Mac |
| Mini | 0.6 GB | 8 GB+ |
| Standard | 1.3 GB | 8 GB+ |
| Performance | 2.5 GB | 16 GB+ |
| Quality | 3.9 GB | 16 GB+ |
| Pro | 5.3 GB | 24 GB+ |

Models are GGUF base checkpoints downloaded from public HuggingFace repos during onboarding — no account or token needed. A HuggingFace token is only required if you point TabTypist at a custom GGUF in a gated or private repo (set it in Settings).

## Build from Source

### Prerequisites

- Xcode 15+ / Swift 5.9+
- Rust toolchain (stable) — install via [rustup.rs](https://rustup.rs)

### Build

```bash
# Clone the repository
git clone https://github.com/mmexploit/TabTypist.git
cd TabTypist

# Build and assemble the .app bundle (debug)
bash scripts/bundle.sh

# Or build a release bundle
bash scripts/bundle.sh --release
```

The assembled app lands at `dist/TabTypist.app`.

### Code signing (for development)

Without a stable signing identity, macOS revokes Input Monitoring on every rebuild. Create a self-signed identity once:

```bash
bash scripts/make-signing-cert.sh
```

This creates a "TabTypist Dev" identity in your login keychain; the bundle script finds and uses it automatically on later builds.

## 🏗 Architecture

TabTypist is two processes talking over a JSON-RPC pipe:

```
TabTypist (Swift)          tabtypist-core (Rust)
  Menu bar UI       ←──→   llama.cpp inference
  AX monitor                Model downloader
  Overlay / popup           Settings store
  Onboarding UI             Exclusion engine
```

- **Swift app** (`Sources/TabTypist/`) — menu bar, onboarding, overlay windows, Accessibility and key capture
- **Rust core** (`crates/tabtypist-core/`) — local inference via `llama-cpp-2`, model downloads, settings persistence

The Rust binary lives at `TabTypist.app/Contents/Resources/tabtypist-core`. The Swift app spawns it on launch and communicates over piped stdin/stdout.

## 🚧 Beta Status

This is **v0.1.1**, an early beta. Expect rough edges:

- Telemetry endpoint is not yet live

Bug reports and feedback are very welcome via [GitHub Issues](https://github.com/mmexploit/TabTypist/issues).

## 🤝 Contributing

Contributions are welcome! Open an issue or pull request anytime.

The first time you open a PR, our CLA bot will ask you to sign the
[Contributor License Agreement](CLA.md) by posting a one-line comment — a single
click, only once. It grants the project the rights it needs to keep TabTypist
sustainable (including offering it under alternative licenses in the future).

## 📄 License

[Functional Source License 1.1](LICENSE) — free for **personal and
non-commercial** use, and for all non-production use. Commercial/competing use
requires a separate arrangement. The license automatically converts to Apache
2.0 four years after each version is published.
