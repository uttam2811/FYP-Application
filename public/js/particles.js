/**
 * Antigravity.google–style particle animation
 * Blue confetti: dashes, dots, tiny lines scattered across a white page
 * Organic simplex-noise drift + cursor push
 */
(function () {
  'use strict';

  /* ═══════ Simplex Noise 3D ═══════ */
  const F3 = 1 / 3, G3 = 1 / 6;
  const grad3 = [
    [1,1,0],[-1,1,0],[1,-1,0],[-1,-1,0],
    [1,0,1],[-1,0,1],[1,0,-1],[-1,0,-1],
    [0,1,1],[0,-1,1],[0,1,-1],[0,-1,-1]
  ];
  const perm = new Uint8Array(512);
  (function () {
    const p = [];
    for (let i = 0; i < 256; i++) p[i] = i;
    for (let i = 255; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [p[i], p[j]] = [p[j], p[i]];
    }
    for (let i = 0; i < 512; i++) perm[i] = p[i & 255];
  })();
  function snoise3(x, y, z) {
    let s = (x + y + z) * F3;
    let i = Math.floor(x + s), j = Math.floor(y + s), k = Math.floor(z + s);
    let t = (i + j + k) * G3;
    let x0 = x - (i - t), y0 = y - (j - t), z0 = z - (k - t);
    let i1, j1, k1, i2, j2, k2;
    if (x0 >= y0) {
      if (y0 >= z0) { i1=1;j1=0;k1=0;i2=1;j2=1;k2=0; }
      else if (x0 >= z0) { i1=1;j1=0;k1=0;i2=1;j2=0;k2=1; }
      else { i1=0;j1=0;k1=1;i2=1;j2=0;k2=1; }
    } else {
      if (y0 < z0) { i1=0;j1=0;k1=1;i2=0;j2=1;k2=1; }
      else if (x0 < z0) { i1=0;j1=1;k1=0;i2=0;j2=1;k2=1; }
      else { i1=0;j1=1;k1=0;i2=1;j2=1;k2=0; }
    }
    let x1 = x0 - i1 + G3, y1 = y0 - j1 + G3, z1 = z0 - k1 + G3;
    let x2 = x0 - i2 + 2*G3, y2 = y0 - j2 + 2*G3, z2 = z0 - k2 + 2*G3;
    let x3 = x0 - 1 + 0.5, y3 = y0 - 1 + 0.5, z3 = z0 - 1 + 0.5;
    i &= 255; j &= 255; k &= 255;
    let n0=0, n1=0, n2=0, n3=0;
    let t0 = 0.6 - x0*x0 - y0*y0 - z0*z0;
    if (t0>0){t0*=t0;let g=grad3[perm[i+perm[j+perm[k]]]%12];n0=t0*t0*(g[0]*x0+g[1]*y0+g[2]*z0);}
    let t1 = 0.6 - x1*x1 - y1*y1 - z1*z1;
    if (t1>0){t1*=t1;let g=grad3[perm[i+i1+perm[j+j1+perm[k+k1]]]%12];n1=t1*t1*(g[0]*x1+g[1]*y1+g[2]*z1);}
    let t2 = 0.6 - x2*x2 - y2*y2 - z2*z2;
    if (t2>0){t2*=t2;let g=grad3[perm[i+i2+perm[j+j2+perm[k+k2]]]%12];n2=t2*t2*(g[0]*x2+g[1]*y2+g[2]*z2);}
    let t3 = 0.6 - x3*x3 - y3*y3 - z3*z3;
    if (t3>0){t3*=t3;let g=grad3[perm[i+1+perm[j+1+perm[k+1]]]%12];n3=t3*t3*(g[0]*x3+g[1]*y3+g[2]*z3);}
    return 32*(n0+n1+n2+n3);
  }

  /* ═══════ Canvas ═══════ */
  const canvas = document.createElement('canvas');
  canvas.id = 'particleCanvas';
  canvas.style.cssText =
    'position:fixed;inset:0;z-index:0;pointer-events:none;width:100%;height:100%;';
  document.body.prepend(canvas);
  const ctx = canvas.getContext('2d');

  let W, H, dpr;
  let particles = [];
  let mouse = { x: -9999, y: -9999, px: -9999, py: -9999, vx: 0, vy: 0, active: false };
  let animId, time = 0;

  /* ── Detect light/dark ── */
  function isLightPage() {
    const bg = getComputedStyle(document.body).backgroundColor;
    if (!bg || bg === 'transparent') return false;
    const m = bg.match(/\d+/g);
    if (!m) return false;
    return (parseInt(m[0])*299 + parseInt(m[1])*587 + parseInt(m[2])*114) / 1000 > 128;
  }
  let lightMode = false;

  /* ═══════ MULTICOLOR palette (antigravity.google exact match) ═══════ */
  /* Base: blue-heavy with purple, pink, orange, teal, gold scattered in */
  const BLUES_LIGHT = [
    '#2563eb', '#3b82f6', '#1d4ed8', '#60a5fa',     // blues
    '#4f46e5', '#6366f1', '#4338ca',                 // indigo
    '#7c3aed', '#8b5cf6',                             // violet
    '#a855f7', '#9333ea',                              // purple
    '#ec4899', '#f472b6',                              // pink
    '#f43f5e', '#fb7185',                              // rose/red
    '#f59e0b', '#fbbf24',                              // amber/gold
    '#f97316', '#fb923c',                              // orange
    '#14b8a6', '#0d9488',                              // teal
    '#0ea5e9', '#0284c7',                              // sky
  ];
  const BLUES_DARK = [
    '#60a5fa', '#93c5fd', '#3b82f6', '#818cf8',
    '#a5b4fc', '#c084fc', '#f9a8d4', '#fb923c',
    '#34d399', '#fbbf24', '#bfdbfe', '#f472b6',
  ];

  /* Colors near cursor — even brighter / warmer burst */
  const CURSOR_COLORS_LIGHT = [
    '#ec4899', '#f43f5e', '#f59e0b', '#f97316',
    '#a855f7', '#7c3aed', '#10b981', '#14b8a6',
    '#fb7185', '#fbbf24', '#6366f1', '#0ea5e9',
  ];
  const CURSOR_COLORS_DARK = [
    '#f472b6', '#fb923c', '#fbbf24', '#a78bfa',
    '#c084fc', '#34d399', '#818cf8', '#93c5fd',
  ];

  /* ═══════ Shapes — dashes, dots, tiny lines ═══════ */
  // Weighted: mostly dashes + dots (matches the screenshot exactly)
  const SHAPES = [
    'dash','dash','dash','dash','dash',
    'dot','dot','dot',
    'tinyline','tinyline',
    'square',
  ];

  const rand = (a,b) => Math.random()*(b-a)+a;
  const pick = a => a[Math.floor(Math.random()*a.length)];
  const clamp = (v,lo,hi) => Math.max(lo,Math.min(hi,v));
  const TAU = Math.PI * 2;

  /* Particle count — denser for brighter field */
  const COUNT = 960;

  /* ═══════ Create particle ═══════ */
  function create(scatter) {
    const palette = lightMode ? BLUES_LIGHT : BLUES_DARK;
    const color = pick(palette);
    const shape = pick(SHAPES);

    /* Size per shape */
    let w, h;
    switch (shape) {
      case 'dash':     w = rand(6, 16); h = rand(1.8, 3.4); break;
      case 'tinyline': w = rand(4, 9);  h = rand(1.1, 1.9); break;
      case 'dot':      w = h = rand(2, 4.2);                 break;
      case 'square':   w = h = rand(2.5, 5);                 break;
    }

    /* Position */
    let x, y;
    if (scatter) {
      x = rand(0, W);
      y = rand(0, H);
    } else {
      // respawn from edges
      const side = Math.random();
      if (side < 0.5)      { x = rand(0, W);      y = H + rand(10,50); }
      else if (side < 0.75){ x = rand(-50, -10);   y = rand(0, H); }
      else                 { x = rand(W+10, W+50); y = rand(0, H); }
    }

    /* Opacity — brighter baseline */
    const alpha = lightMode ? rand(0.45, 0.95) : rand(0.35, 0.85);

    return {
      x, y,
      hx: x, hy: y,
      shape, color, baseColor: color, w, h,
      angle: rand(0, TAU),
      spin: rand(-0.003, 0.003),
      // noise seeds
      sx: rand(0, 300),
      sy: rand(0, 300),
      // cursor-imparted velocity
      vx: 0, vy: 0,
      // drift direction (slow upward)
      driftY: -rand(0.08, 0.25),
      driftX: rand(-0.06, 0.06),
      // alpha
      alpha, baseAlpha: alpha,
      fade: scatter ? rand(0.5, 1) : 0,
      // cursor proximity (0 = far, 1 = on cursor)
      cursorInfluence: 0,
    };
  }

  /* ═══════ Resize ═══════ */
  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = window.innerWidth;
    H = window.innerHeight;
    canvas.width  = W * dpr;
    canvas.height = H * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  /* ═══════ Init ═══════ */
  function init() {
    resize();
    lightMode = isLightPage();
    particles = [];
    for (let i = 0; i < COUNT; i++) particles.push(create(true));
  }

  /* ═══════ Draw one particle ═══════ */
  function drawParticle(p) {
    const visBoost = 1 + p.cursorInfluence * 0.45;
    const a = clamp(p.alpha * p.fade * visBoost, 0, 1);
    if (a < 0.008) return;

    ctx.save();
    ctx.globalAlpha = a;
    ctx.translate(p.x, p.y);
    ctx.rotate(p.angle);
    ctx.fillStyle = p.color;
    ctx.shadowColor = p.color;
    ctx.shadowBlur = 2 + p.cursorInfluence * 7;

    switch (p.shape) {
      case 'dash':
      case 'tinyline': {
        // Rounded rectangle
        const hw = p.w / 2, hh = p.h / 2;
        const r = Math.min(hh, 1.5);
        ctx.beginPath();
        ctx.moveTo(-hw + r, -hh);
        ctx.lineTo(hw - r, -hh);
        ctx.quadraticCurveTo(hw, -hh, hw, -hh + r);
        ctx.lineTo(hw, hh - r);
        ctx.quadraticCurveTo(hw, hh, hw - r, hh);
        ctx.lineTo(-hw + r, hh);
        ctx.quadraticCurveTo(-hw, hh, -hw, hh - r);
        ctx.lineTo(-hw, -hh + r);
        ctx.quadraticCurveTo(-hw, -hh, -hw + r, -hh);
        ctx.closePath();
        ctx.fill();
        break;
      }
      case 'dot': {
        ctx.beginPath();
        ctx.arc(0, 0, p.w / 2, 0, TAU);
        ctx.fill();
        break;
      }
      case 'square': {
        const s = p.w / 2;
        ctx.fillRect(-s, -s, p.w, p.w);
        break;
      }
    }
    ctx.restore();
  }

  /* ═══════ Main loop ═══════ */
  function loop() {
    time += 0.006;
    ctx.clearRect(0, 0, W, H);

    /* Track cursor velocity */
    mouse.vx = (mouse.x - mouse.px) * 0.6;
    mouse.vy = (mouse.y - mouse.py) * 0.6;
    mouse.px = mouse.x;
    mouse.py = mouse.y;

    const mx = mouse.x;
    const my = mouse.y;
    const mActive = mouse.active;
    const mvx = mouse.vx;
    const mvy = mouse.vy;
    const cursorR = 300;
    const cursorRSq = cursorR * cursorR;
    const cursorPalette = lightMode ? CURSOR_COLORS_LIGHT : CURSOR_COLORS_DARK;
    const basePalette   = lightMode ? BLUES_LIGHT : BLUES_DARK;

    for (let i = particles.length - 1; i >= 0; i--) {
      const p = particles[i];

      /* ── Noise-based organic drift ── */
      const noiseMult = 1 + p.cursorInfluence * 5;
      const n1 = snoise3(p.sx * 3, p.sy * 3, time * 0.25 + 50) * 0.28 * noiseMult;
      const n2 = snoise3(p.sx * 3, p.sy * 3, time * 0.25) * 0.28 * noiseMult;
      const n3 = snoise3(p.sx * 0.4, p.sy * 0.4, time * 0.12 + 30) * 0.65;
      const n4 = snoise3(p.sx * 0.4, p.sy * 0.4, time * 0.12 + 70) * 0.65;

      p.x += p.driftX + n1 + n3 + p.vx;
      p.y += p.driftY + n2 + n4 + p.vy;
      p.angle += p.spin;

      /* ── Cursor interaction ── */
      if (mActive) {
        const dx = p.x - mx;
        const dy = p.y - my;
        const dSq = dx * dx + dy * dy;
        if (dSq < cursorRSq && dSq > 1) {
          const d = Math.sqrt(dSq);
          const proximity = 1 - d / cursorR;
          const strength  = proximity * proximity;

          /* Strong sweep drag along cursor direction */
          p.vx += mvx * strength * 0.7;
          p.vy += mvy * strength * 0.7;

          /* Also gently push outward from cursor center */
          const pushF = strength * 0.3;
          p.vx += (dx / d) * pushF;
          p.vy += (dy / d) * pushF;

          /* Dramatic spin */
          p.spin += strength * 0.008 * (Math.random() > 0.5 ? 1 : -1);

          /* Fast color & liveliness ramp-up */
          p.cursorInfluence = Math.min(1, p.cursorInfluence + strength * 0.45);
        } else {
          /* Very slow fade-back so color lingers long after cursor passes */
          p.cursorInfluence *= 0.99;
        }
      } else {
        p.cursorInfluence *= 0.99;
      }

      /* ── Color shift (near-instant trigger, slow reset) ── */
      if (p.cursorInfluence > 0.02) {
        const ci = Math.floor(p.sx * 100 + p.cursorInfluence * 9) % cursorPalette.length;
        p.color = cursorPalette[ci];
      } else {
        p.color = p.baseColor;
      }

      /* Dampen */
      p.vx *= 0.94;
      p.vy *= 0.94;

      /* ── Recycle off-screen ── */
      if (p.y < -60 || p.x < -60 || p.x > W + 60) {
        particles[i] = create(false);
        continue;
      }

      /* ── Fade in ── */
      if (p.fade < 1) p.fade = Math.min(1, p.fade + 0.014);

      /* ── Shimmer ── */
      p.alpha = p.baseAlpha + Math.sin(time * 2.5 + p.sx * 40) * 0.08;

      drawParticle(p);
    }

    animId = requestAnimationFrame(loop);
  }

  /* ═══════ Events ═══════ */
  window.addEventListener('resize', resize);
  document.addEventListener('mousemove', function (e) {
    mouse.x = e.clientX; mouse.y = e.clientY;
    mouse.active = true;
  });
  document.addEventListener('mouseleave', function () {
    mouse.active = false; mouse.x = mouse.y = -9999;
  });
  document.addEventListener('visibilitychange', function () {
    if (document.hidden) cancelAnimationFrame(animId);
    else animId = requestAnimationFrame(loop);
  });

  /* ═══════ Boot ═══════ */
  function boot() { init(); loop(); }
  if (document.readyState === 'loading')
    document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
