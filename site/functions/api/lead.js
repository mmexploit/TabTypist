// Cloudflare Pages Function — capture an (optional) email on download.
//
// Route: POST /api/lead   body: { "email": "you@example.com" }
// Stores the lead in D1. Bind a D1 database as `DB` in the Pages project
// (Settings → Functions → D1 database bindings) and apply site/d1/schema.sql.
//
// The site only calls this when the user actually entered an email; skipping the
// prompt sends nothing. Downloads never depend on this endpoint succeeding.

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export async function onRequestPost({ request, env }) {
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
    // Store not configured yet — don't 500 the client; the download still works.
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
