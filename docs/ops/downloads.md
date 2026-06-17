# Counting downloads

TabTypist is distributed as a DMG attached to GitHub Releases. Downloads come from
two paths:

- **Manual** — the download button on tabtypist.com / the GitHub release page.
- **Auto-update** — Sparkle pulls the DMG directly from the release enclosure URL
  (`SUFeedURL` → appcast → `…/releases/latest/download/TabTypist.dmg`).

## Source of truth: GitHub `download_count` (already live)

GitHub counts **every** asset download, including Sparkle auto-updates (they hit the
same asset). This is the most complete total and needs no infrastructure.

```bash
bash scripts/download-stats.sh
```

## Optional: Cloudflare-side counting (website funnel)

Cloudflare can only count a download that routes through a Cloudflare-served domain.
Two pieces, both requiring the `site/` directory to be deployed as a **Cloudflare
Pages** project on tabtypist.com:

1. **Web Analytics** (visits + funnel) — enable in the Pages project dashboard
   (Settings → Web Analytics → automatic injection). No code change.

2. **Server-side download counter** — `site/functions/download/[[path]].js` is a
   Pages Function that logs the hit and 302-redirects to the GitHub asset. To turn
   it on:
   - Bind a counting backend in the Pages project (Settings → Functions):
     - *Analytics Engine* dataset bound as `DL` (queryable, time-series), **or**
     - *KV namespace* bound as `COUNTER` (simple running total).
   - Change the site's direct-DMG link from the GitHub URL to the gateway:
     ```html
     <!-- site/index.html line ~32 (.dmg-link) -->
     <a ... href="/download/TabTypist.dmg">Download</a>
     ```
     The release-page links (`…/releases/latest`) can stay on GitHub.

   Read the counter:
   - KV: `wrangler kv key get --binding COUNTER TabTypist.dmg`
   - Analytics Engine: query via the GraphQL/SQL API (dataset name = the bound one).

### Do NOT route auto-updates through Cloudflare

Keep the appcast `enclosure url` on the direct GitHub asset. Routing Sparkle's
download through a redirect adds a failure point to the updater for a number GitHub
already tracks accurately. Use Cloudflare only for the website funnel.
