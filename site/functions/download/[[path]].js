// Cloudflare Pages Function — download gateway + counter.
//
// Route: tabtypist.com/download/<asset>   e.g. /download/TabTypist.dmg
// Behaviour: logs the hit, then 302-redirects to the GitHub release asset.
// GitHub's own download_count still increments (the 302 lands on the asset), so
// this gives you a Cloudflare-side count *in addition to* GitHub's.
//
// Point the site's download button at /download/TabTypist.dmg.
// Do NOT point the Sparkle appcast enclosure here — keep auto-updates on the
// direct GitHub URL to avoid adding a redirect hop into the updater.
//
// Counting backend: pick ONE and bind it in the Pages project settings.
//   • Analytics Engine — bind as DL  (Settings → Functions → Analytics Engine bindings)
//   • KV namespace     — bind as COUNTER  (Settings → Functions → KV namespace bindings)

const REPO = "mmexploit/TabTypist";
const ALLOWED = new Set(["TabTypist.dmg"]); // assets we’re willing to redirect to

export async function onRequest(context) {
  const { params, env, request } = context;
  const asset = Array.isArray(params.path) ? params.path.join("/") : params.path;

  if (!ALLOWED.has(asset)) {
    return new Response("Not found", { status: 404 });
  }

  // --- log the download (whichever backend is bound) ---
  try {
    if (env.DL) {
      const ua = request.headers.get("user-agent") ?? "";
      const country = request.cf?.country ?? "??";
      env.DL.writeDataPoint({ blobs: [asset, ua, country], indexes: [asset] });
    } else if (env.COUNTER) {
      const n = parseInt((await env.COUNTER.get(asset)) ?? "0", 10) + 1;
      await env.COUNTER.put(asset, String(n));
    }
  } catch (_) {
    // never let logging failures block the download
  }

  const target = `https://github.com/${REPO}/releases/latest/download/${asset}`;
  return Response.redirect(target, 302);
}
