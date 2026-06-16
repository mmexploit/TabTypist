/* ============================================================
   TabTypist demo — interactive ghost-text completion engine
   - type real prefixes → completion appears after the caret
   - Tab accepts (with accept flash), Esc dismisses
   - autoplay "watch" loop until the user takes over
   - per-app + EN/AM language switching
   ============================================================ */
(function () {
  const field   = document.getElementById('field');
  const hint     = document.getElementById('demoHint');
  const fieldTo  = document.getElementById('fieldTo');
  const winTabs  = document.getElementById('winTabs');
  const langTog  = document.getElementById('langToggle');
  if (!field) return;

  /* ---------- completion corpus ---------- */
  // The engine finds a target the typed text is a prefix of, and shows the rest.
  const CORPUS = {
    en: {
      mail: [
        "Thanks so much for getting back to me — I really appreciate it.",
        "Just wanted to follow up on the note I sent last week.",
        "Let me know if you have any questions and I'll be happy to help.",
        "I'll send over the updated draft by end of day tomorrow.",
        "Could you review the attached document when you get a chance?",
        "Looking forward to hearing your thoughts on the proposal.",
      ],
      slack: [
        "Sounds good to me, let's schedule a call for early next week.",
        "Happy to jump on a quick call if that's easier for you.",
        "Can you take a look when you get a sec? No rush at all.",
        "Nice work on this — shipping it now and I'll keep an eye on it.",
      ],
      notes: [
        "Action items from today's sync: finalize the deck and send the recap.",
        "Key takeaways: budget approved, timeline moves to next quarter.",
        "Follow up with the client about the revised proposal by Friday.",
        "Decisions made in the review and who owns each next step.",
      ],
    },
    am: {
      mail:  ["ሰላም፣ እንዴት ነህ?", "አመሰግናለሁ፣ መልካም ቀን!"],
      slack: ["እሺ፣ ነገ እንነጋገራለን።", "በጣም ጥሩ ሥራ ነው!"],
      notes: ["እንኳን ደህና መጡ።", "ቡና እንጠጣ?"],
    },
  };

  const TRANS = {
    "ሰላም፣ እንዴት ነህ?": "“Hello, how are you?”",
    "አመሰግናለሁ፣ መልካም ቀን!": "“Thank you, have a good day!”",
    "እሺ፣ ነገ እንነጋገራለን።": "“Okay, let's talk tomorrow.”",
    "በጣም ጥሩ ሥራ ነው!": "“Great work!”",
    "እንኳን ደህና መጡ።": "“Welcome.”",
    "ቡና እንጠጣ?": "“Shall we get coffee?”",
  };

  const TO_LINE = {
    mail:  "New message · To: alex@team.co",
    slack: "# design-review · message",
    notes: "Untitled note · today",
  };

  /* ---------- state ---------- */
  let lang = 'en';
  let app  = 'mail';
  let typed = '';
  let ghost = '';
  let dismissed = false;     // Esc hides ghost until next input
  let userDriving = false;   // becomes true once the person types
  let autoToken = 0;         // cancels the autoplay loop

  function targets() { return CORPUS[lang][app] || []; }

  function computeGhost() {
    if (dismissed || typed.length === 0) { ghost = ''; return; }
    const lower = typed.toLowerCase();
    // prefer the shortest remaining completion among matches
    let best = null;
    for (const t of targets()) {
      if (t.length > typed.length && t.toLowerCase().startsWith(lower)) {
        const rest = t.slice(typed.length);
        if (best === null || rest.length < best.length) best = rest;
      }
    }
    ghost = best || '';
  }

  /* ---------- render ---------- */
  function render(opts) {
    opts = opts || {};
    field.classList.toggle('eth', lang === 'am');
    field.classList.toggle('field-empty', typed.length === 0 && ghost.length === 0 && !document.activeElement);

    field.innerHTML = '';

    if (typed.length === 0 && ghost.length === 0 && document.activeElement !== field) {
      const ph = document.createElement('span');
      ph.className = 'placeholder';
      ph.textContent = lang === 'am' ? 'እዚህ ይተይቡ…' : 'Type here…';
      field.appendChild(ph);
      return;
    }

    const tSpan = document.createElement('span');
    tSpan.className = 'typed';
    if (opts.acceptedFrom != null) {
      tSpan.appendChild(document.createTextNode(typed.slice(0, opts.acceptedFrom)));
      const acc = document.createElement('span');
      acc.className = 'just-accepted';
      acc.textContent = typed.slice(opts.acceptedFrom);
      tSpan.appendChild(acc);
    } else {
      tSpan.textContent = typed;
    }
    field.appendChild(tSpan);

    const caret = document.createElement('span');
    caret.className = 'caret' + (document.activeElement === field ? '' : ' hide');
    field.appendChild(caret);

    if (ghost) {
      const gSpan = document.createElement('span');
      gSpan.className = 'ghost';
      gSpan.textContent = ghost;
      field.appendChild(gSpan);

      // Tab hint pill (issue 0028) — only while the user is learning
      if (!opts.noPill) {
        const pill = document.createElement('span');
        pill.className = 'tab-pill' + (opts.pressPill ? ' press' : '');
        pill.textContent = '⇥ Tab';
        field.appendChild(pill);
      }
    }
  }

  /* ---------- actions ---------- */
  // length of the next chunk to accept: one word plus any trailing space,
  // so each Tab commits a single word and leaves the caret ready for the next.
  function nextWordCut(str) {
    let i = 0;
    while (i < str.length && str[i] === ' ') i++;   // leading space
    while (i < str.length && str[i] !== ' ') i++;    // the word
    while (i < str.length && str[i] === ' ') i++;    // trailing space
    return i;
  }

  function accept() {
    if (!ghost) return false;
    const from = typed.length;
    const cut = nextWordCut(ghost);
    typed += ghost.slice(0, cut);
    ghost = ghost.slice(cut);   // remaining words stay as ghost
    dismissed = false;
    render({ acceptedFrom: from, pressPill: true });
    return true;
  }

  function dismiss() {
    if (!ghost) return;
    ghost = '';
    dismissed = true;
    render();
  }

  function insert(ch) {
    dismissed = false;
    typed += ch;
    computeGhost();
    render();
  }

  function backspace() {
    if (typed.length === 0) return;
    typed = typed.slice(0, -1);
    dismissed = false;
    computeGhost();
    render();
  }

  function resetField() {
    typed = ''; ghost = ''; dismissed = false;
    render();
  }

  /* ---------- user input ---------- */
  function takeOver() {
    if (!userDriving) {
      userDriving = true;
      autoToken++; // cancel autoplay
      hint.innerHTML = "You're driving now — keep typing, hit <span style='color:var(--acc)'>Tab</span> to accept a word at a time, <span style='color:var(--on-dark)'>Esc</span> to dismiss. &nbsp;<span class='replay' id='replayBtn'>↻ watch the demo</span>";
      bindReplay();
    }
  }

  field.addEventListener('focus', function () { render(); });
  field.addEventListener('blur', function () { render(); });

  field.addEventListener('keydown', function (e) {
    if (e.key === 'Tab') {
      e.preventDefault();
      takeOver();
      if (!accept()) { /* no ghost: behave like a normal tab — do nothing visible */ }
      return;
    }
    if (e.key === 'Escape') { e.preventDefault(); takeOver(); dismiss(); return; }
    if (e.key === 'Backspace') { e.preventDefault(); takeOver(); backspace(); return; }
    if (e.key === 'Enter') { e.preventDefault(); takeOver(); resetField(); return; }
    if (e.key.length === 1 && !e.metaKey && !e.ctrlKey && !e.altKey) {
      e.preventDefault();
      takeOver();
      insert(e.key);
    }
  });

  // tapping the field focuses it
  field.addEventListener('mousedown', function () {
    setTimeout(function () { field.focus(); render(); }, 0);
  });

  /* ---------- app tabs ---------- */
  winTabs.addEventListener('click', function (e) {
    const tab = e.target.closest('.win-tab');
    if (!tab) return;
    [...winTabs.children].forEach(c => c.classList.remove('active'));
    tab.classList.add('active');
    app = tab.dataset.app;
    fieldTo.textContent = TO_LINE[app];
    if (userDriving) { resetField(); }
    else { restartAuto(); }
  });

  /* ---------- language toggle ---------- */
  langTog.addEventListener('click', function (e) {
    const btn = e.target.closest('button');
    if (!btn) return;
    [...langTog.children].forEach(c => c.classList.remove('active'));
    btn.classList.add('active');
    lang = btn.dataset.lang;
    if (userDriving) { resetField(); }
    else { restartAuto(); }
  });

  /* ---------- autoplay ("watch") ---------- */
  const sleep = (ms, tok) => new Promise(res => {
    const id = setInterval(() => {
      if (tok !== autoToken) { clearInterval(id); res('cancel'); }
    }, 40);
    setTimeout(() => { clearInterval(id); res(tok === autoToken ? 'ok' : 'cancel'); }, ms);
  });

  // type a "seed" prefix char-by-char so the engine surfaces a completion,
  // pause, then simulate Tab to accept, then clear and move on.
  async function autoplay() {
    const tok = ++autoToken;
    while (tok === autoToken) {
      const list = targets();
      for (let i = 0; i < list.length && tok === autoToken; i++) {
        const full = list[i];
        // choose a seed: ~45% of the sentence, ending on a space when possible
        let cut = Math.max(6, Math.floor(full.length * 0.45));
        const sp = full.lastIndexOf(' ', cut);
        if (sp > 4) cut = sp;
        const seed = full.slice(0, cut);

        resetField();
        // type the seed
        for (let c = 0; c < seed.length && tok === autoToken; c++) {
          insert(seed[c]);
          if ((await sleep(38 + Math.random() * 46, tok)) === 'cancel') return;
        }
        if (tok !== autoToken) return;
        // let the completion sit
        if ((await sleep(820, tok)) === 'cancel') return;
        // press Tab — accept one word at a time
        while (ghost && tok === autoToken) {
          accept();
          if ((await sleep(430, tok)) === 'cancel') return;
        }
        if ((await sleep(1100, tok)) === 'cancel') return;
        // clear before next
        resetField();
        if ((await sleep(420, tok)) === 'cancel') return;
      }
    }
  }

  function restartAuto() {
    if (userDriving) return;
    autoToken++;
    resetField();
    autoplay();
  }

  function bindReplay() {
    const r = document.getElementById('replayBtn');
    if (r) r.addEventListener('click', function () {
      userDriving = false;
      field.blur();
      hint.innerHTML = "<b>Click the field and start typing.</b> A completion appears — press <span style='color:var(--acc)'>Tab</span> to accept it one word at a time, <span style='color:var(--on-dark)'>Esc</span> to dismiss.";
      restartAuto();
    });
  }

  /* ---------- Amharic showcase card (languages section) ---------- */
  const amhLine  = document.getElementById('amhLine');
  const amhTrans = document.getElementById('amhTrans');
  const amhTag   = document.getElementById('amhTag');
  if (amhLine) {
    const phrases = [
      { full: "ሰላም፣ እንዴት ነህ?", seed: "ሰላም፣ " },
      { full: "አመሰግናለሁ፣ መልካም ቀን!", seed: "አመሰግናለሁ፣ " },
      { full: "እንኳን ደህና መጡ።", seed: "እንኳን " },
    ];
    let amTok = 0;
    const amSleep = (ms, t) => new Promise(r => setTimeout(() => r(t === amTok ? 'ok' : 'x'), ms));
    async function amLoop() {
      const t = ++amTok;
      while (t === amTok) {
        for (const p of phrases) {
          if (t !== amTok) return;
          amhTrans.textContent = TRANS[p.full] || '';
          const rest = p.full.slice(p.seed.length);
          // type seed
          for (let i = 0; i < p.seed.length; i++) {
            amhLine.innerHTML = esc(p.seed.slice(0, i + 1)) + '<span class="caret" style="background:var(--acc)"></span>';
            if ((await amSleep(95, t)) === 'x') return;
          }
          // reveal ghost
          amhLine.innerHTML = esc(p.seed) + '<span class="caret"></span><span class="g">' + esc(rest) + '</span>';
          if ((await amSleep(1100, t)) === 'x') return;
          // accept
          amhLine.innerHTML = esc(p.full);
          if ((await amSleep(1700, t)) === 'x') return;
        }
      }
    }
    function esc(s) { return s.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c])); }
    // start when scrolled into view
    const io = new IntersectionObserver((ents) => {
      ents.forEach(en => { if (en.isIntersecting) { amLoop(); io.disconnect(); } });
    }, { threshold: 0.4 });
    io.observe(amhLine);
  }

  /* ---------- kick off hero autoplay ---------- */
  resetField();
  // small delay so fonts settle
  setTimeout(autoplay, 600);
})();
