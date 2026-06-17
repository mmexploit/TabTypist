# Downloads & lead capture

TabTypist is distributed as a DMG attached to GitHub Releases. The site's download
buttons link **directly** to the GitHub release asset
(`…/releases/latest/download/TabTypist.dmg`), so downloads never depend on
Cloudflare. Auto-updates use the same asset via Sparkle's appcast.

## Counting downloads: GitHub `download_count` (already live)

GitHub counts **every** asset download, including Sparkle auto-updates (they hit the
same asset). This is the most complete total and needs no infrastructure.

```bash
bash scripts/download-stats.sh
```

(If you later want Cloudflare-side download counts too, route the download button
through a Worker route that 302-redirects to the GitHub asset and logs the hit — but
GitHub's number already covers it, and keeping downloads on the direct URL is more
reliable.)

## Optional email capture on download (leads)

When a visitor clicks a download button the site shows a small modal asking for an
email. **It's skippable** — "Skip and download" downloads immediately and sends
nothing. If they enter an email, the site POSTs it to `/api/lead`, which stores it in
a **D1** database. The download itself uses the button's GitHub URL and never blocks
on this call.

The site is deployed as a **Cloudflare Worker with static assets** (not Pages):

- `wrangler.jsonc` — Worker config: serves `./site` via the `ASSETS` binding, binds
  D1 as `DB`, and runs the Worker first for `/api/*`.
- `src/index.js` — Worker entry: serves the static site and handles `POST /api/lead`.
- `d1/schema.sql` — the `leads` table (kept outside `./site` so it isn't served).
- Modal markup/CSS/JS live in `site/index.html`, `styles.css`, `interactions.js`
  (the `.js-download` class on each download button triggers it).

### Setup

```bash
# 1. Create the D1 database (prints a database_id):
wrangler d1 create tabtypist-leads

# 2. Paste that id into wrangler.jsonc → d1_databases[0].database_id

# 3. Create the table in the remote DB:
wrangler d1 execute tabtypist-leads --remote --file=d1/schema.sql

# 4. Deploy the Worker (serves the site + /api/lead):
wrangler deploy
```

Run these locally from the repo root (wrangler talks to your Cloudflare account).

### Read / export the leads

```bash
wrangler d1 execute tabtypist-leads --remote \
  --command "SELECT email, created_at, country FROM leads ORDER BY created_at DESC LIMIT 50"

# export all:
wrangler d1 execute tabtypist-leads --remote --json \
  --command "SELECT * FROM leads" > leads.json
```

### Page-view analytics (optional)

For visit/funnel analytics, enable Cloudflare **Web Analytics** for the Worker in the
dashboard. No code change.

Privacy: emails are PII. The prompt is optional and the copy states what it's for;
keep it that way, and honour unsubscribe/delete requests
(`DELETE FROM leads WHERE email = ?`).
