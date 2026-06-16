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

  /* ---- download label, served from the public repo ----
     Every download button points at the version-less redirect
     https://github.com/<owner>/<repo>/releases/latest/download/<asset>, which
     GitHub resolves to the current Latest release on each click — no API, no
     rate limit, works with JS off, and never needs a version baked into the
     href. The fetch below ONLY enhances the label (live version + size); it
     deliberately does NOT rewrite the href, so the button can never get pinned
     to a stale tag. Fails silently and leaves the static label untouched. */
  const GH_OWNER = 'mmexploit', GH_REPO = 'TabTypist', DMG_NAME = 'TabTypist.dmg';
  const GH_API = 'https://api.github.com/repos/' + GH_OWNER + '/' + GH_REPO;
  const fmtStars = (n) => n >= 1000 ? (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k' : String(n);

  fetch(GH_API + '/releases/latest')
    .then((r) => r.ok ? r.json() : Promise.reject())
    .then((rel) => {
      if (!rel || !rel.tag_name) return;
      const assets = rel.assets || [];
      const asset = assets.find((a) => a.name === DMG_NAME) || assets.find((a) => /\.dmg$/i.test(a.name));
      const sub = document.querySelector('#dmgBtn .sub');
      const ver = rel.tag_name.replace(/^v/, '');
      const mb = asset ? Math.round(asset.size / 1048576) : null;
      if (sub && ver) sub.textContent = 'v' + ver + ' · .dmg · macOS 13+ · Apple Silicon & Intel' + (mb ? ' · ' + mb + ' MB' : '');
    })
    .catch(() => {});

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
