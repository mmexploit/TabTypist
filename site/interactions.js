/* ============================================================
   TabTypist — page interactions
   nav scroll state · scroll reveals · brand ghost · copy brew
   ============================================================ */
(function () {
  /* nav shadow on scroll */
  const nav = document.getElementById('nav');
  const onScroll = () => nav.classList.toggle('scrolled', window.scrollY > 24);
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  /* scroll reveals */
  const reveals = document.querySelectorAll('.reveal');
  const io = new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });
  reveals.forEach((r) => io.observe(r));

  /* brand "Typist" ghost → accept on load (cute self-demo of the product) */
  const bg = document.getElementById('brandGhost');
  if (bg) {
    setTimeout(() => {
      bg.style.transition = 'color .5s var(--ease)';
      bg.style.color = 'var(--ink)';
    }, 1400);
  }

  /* copy brew command */
  const copy = document.getElementById('brewCopy');
  if (copy) {
    copy.addEventListener('click', async () => {
      const cmd = 'brew install --cask tabtypist';
      try {
        await navigator.clipboard.writeText(cmd);
      } catch (_) {
        const ta = document.createElement('textarea');
        ta.value = cmd; document.body.appendChild(ta); ta.select();
        try { document.execCommand('copy'); } catch (e) {}
        document.body.removeChild(ta);
      }
      const prev = copy.textContent;
      copy.textContent = '✓ Copied';
      copy.classList.add('done');
      setTimeout(() => { copy.textContent = prev; copy.classList.remove('done'); }, 1600);
    });
  }

  /* ---- download + GitHub stats, served from the public repo ----
     The button already points at the latest release asset (a plain GitHub
     redirect — no API, no rate limit, works with JS off). The fetches below
     only *enhance* it: pick up the newest release (incl. pre-releases), show
     the live version + size, and fill real star counts. Everything fails
     silently and leaves the static values untouched. */
  const GH_OWNER = 'mmexploit', GH_REPO = 'TabTypist', DMG_NAME = 'TabTypist.dmg';
  const GH_API = 'https://api.github.com/repos/' + GH_OWNER + '/' + GH_REPO;
  const fmtStars = (n) => n >= 1000 ? (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k' : String(n);

  fetch(GH_API + '/releases?per_page=1')
    .then((r) => r.ok ? r.json() : Promise.reject())
    .then((list) => {
      const rel = Array.isArray(list) && list[0];
      if (!rel) return;
      const assets = rel.assets || [];
      const asset = assets.find((a) => a.name === DMG_NAME) || assets.find((a) => /\.dmg$/i.test(a.name));
      const dmg = document.getElementById('dmgBtn');
      if (dmg && asset) dmg.href = asset.browser_download_url;
      const sub = dmg && dmg.querySelector('.sub');
      const ver = (rel.tag_name || '').replace(/^v/, '');
      const mb = asset ? Math.round(asset.size / 1048576) : null;
      if (sub && ver) sub.textContent = 'v' + ver + ' · .dmg · macOS 13+ · Apple Silicon & Intel' + (mb ? ' · ' + mb + ' MB' : '');
    })
    .catch(() => {});

  /* Friction Horizon — draggable open-book split */
  (function () {
    const horizon = document.getElementById('horizon');
    const bar = document.getElementById('horizonBar');
    if (!horizon || !bar) return;
    const MIN = 18, MAX = 82;
    let dragging = false;

    const set = (pct) => {
      pct = Math.max(MIN, Math.min(MAX, pct));
      horizon.style.setProperty('--split', pct.toFixed(1));
      bar.setAttribute('aria-valuenow', Math.round(pct));
    };
    const fromEvent = (clientX) => {
      const r = horizon.getBoundingClientRect();
      set(((clientX - r.left) / r.width) * 100);
    };

    bar.addEventListener('pointerdown', (e) => {
      dragging = true; bar.setPointerCapture(e.pointerId); e.preventDefault();
    });
    window.addEventListener('pointermove', (e) => { if (dragging) fromEvent(e.clientX); });
    window.addEventListener('pointerup', () => { dragging = false; });
    horizon.addEventListener('pointerdown', (e) => {
      if (e.target === bar || bar.contains(e.target)) return;
      fromEvent(e.clientX);
    });
    bar.addEventListener('keydown', (e) => {
      const cur = parseFloat(horizon.style.getPropertyValue('--split')) || 52;
      if (e.key === 'ArrowLeft') { set(cur - 4); e.preventDefault(); }
      if (e.key === 'ArrowRight') { set(cur + 4); e.preventDefault(); }
    });
  })();

  /* Star count is hidden for now. Re-enable by uncommenting this block and
     restoring the [data-gh-stars] badges in index.html.
  fetch(GH_API)
    .then((r) => r.ok ? r.json() : Promise.reject())
    .then((d) => {
      if (typeof d.stargazers_count !== 'number') return;
      const s = fmtStars(d.stargazers_count);
      document.querySelectorAll('[data-gh-stars]').forEach((el) => { el.textContent = s; });
    })
    .catch(() => {});
  */
})();

/* ============================================================
   Download email capture — optional, skippable.
   Intercepts .js-download clicks, asks for an email, POSTs it to
   /api/lead (Cloudflare Pages Function → D1), then starts the
   download via the /download gateway. Skipping downloads directly.
   ============================================================ */
(function () {
  // Downloads go direct to the GitHub release asset — no Cloudflare gateway.
  const DOWNLOAD_URL =
    'https://github.com/mmexploit/TabTypist/releases/latest/download/TabTypist.dmg';
  const modal = document.getElementById('dlModal');
  if (!modal) return;

  const form = document.getElementById('dlForm');
  const email = document.getElementById('dlEmail');
  const skip = document.getElementById('dlSkip');
  let lastFocus = null;
  let pendingHref = DOWNLOAD_URL; // the asset the clicked button points to

  const open = (trigger) => {
    lastFocus = trigger || document.activeElement;
    pendingHref = (trigger && trigger.getAttribute('href')) || DOWNLOAD_URL;
    modal.classList.add('show');
    modal.setAttribute('aria-hidden', 'false');
    setTimeout(() => email.focus(), 60);
  };
  const close = () => {
    modal.classList.remove('show');
    modal.setAttribute('aria-hidden', 'true');
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  };
  const download = () => { window.location.href = pendingHref; };

  const sendLead = (value) => {
    if (!value) return Promise.resolve();
    return fetch('/api/lead', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: value }),
      keepalive: true,
    }).catch(() => {}); // never block the download on a logging failure
  };

  document.querySelectorAll('.js-download').forEach((el) => {
    el.addEventListener('click', (e) => { e.preventDefault(); open(el); });
  });

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    if (!email.checkValidity()) { email.reportValidity(); return; }
    sendLead(email.value.trim()).finally(() => { close(); download(); });
  });

  skip.addEventListener('click', () => { close(); download(); });

  modal.querySelectorAll('[data-dl-close]').forEach((el) =>
    el.addEventListener('click', close));
  modal.addEventListener('click', (e) => { if (e.target === modal) close(); });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && modal.classList.contains('show')) close();
  });
})();
