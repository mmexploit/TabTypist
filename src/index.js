// TabTypist site Worker.
//
// Serves the static site in ./site (ASSETS binding) and handles dynamic routes:
//   POST /api/lead  → store an (optional) email in D1 (binding: DB)
// Everything else falls through to the static assets.
//
// The download buttons link straight to the GitHub release asset, so downloads
// never depend on this Worker. Lead capture is best-effort: if DB isn't bound
// yet, /api/lead returns 503 and the frontend just proceeds with the download.

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/lead") {
      if (request.method !== "POST") {
        return json({ ok: false, error: "method not allowed" }, 405);
      }
      return handleLead(request, env);
    }

    // Static marketing site.
    return env.ASSETS.fetch(request);
  },
};

async function handleLead(request, env) {
  let email = "";
  try {
    const body = await request.json();
    email = String(body.email ?? "").trim().toLowerCase();
  } catch (_) {
    return json({ ok: false, error: "bad request" }, 400);
  }

  if (email.length > 254 || !EMAIL_RE.test(email)) {
    return json({ ok: false, error: "invalid email" }, 400);
  }

  if (!env.DB) {
    // Store not bound yet — don't error the client; the download still works.
    return json({ ok: false, error: "store not configured" }, 503);
  }

  const cf = request.cf ?? {};
  try {
    await env.DB.prepare(
      `INSERT INTO leads (email, created_at, country, user_agent)
       VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT(email) DO NOTHING`
    )
      .bind(
        email,
        new Date().toISOString(),
        cf.country ?? null,
        request.headers.get("user-agent") ?? null
      )
      .run();
  } catch (_) {
    return json({ ok: false, error: "store error" }, 500);
  }

  return json({ ok: true });
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });
}
