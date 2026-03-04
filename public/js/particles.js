/**
 * Antigravity-style Particle Animation
 * Smooth floating blue dots/squares that drift and scatter
 * Matches the Google Antigravity IDE aesthetic
 */
(function () {
  'use strict';

  const canvas = document.createElement('canvas');
  canvas.id = 'particleCanvas';
  canvas.style.cssText =
    'position:fixed;inset:0;z-index:0;pointer-events:none;width:100%;height:100%;';
  document.body.prepend(canvas);

  const ctx = canvas.getContext('2d');
  let W, H;
  let particles = [];
  let mouse = { x: -9999, y: -9999 };
  let animFrame;

  /* ── Tunables ── */
  const PARTICLE_COUNT = 110;      // total dots
  const BASE_SPEED     = 0.18;     // base drift speed
  const MAX_SIZE       = 3.8;      // largest particle side
  const MIN_SIZE       = 1.0;      // smallest particle side
  const COLORS = [
    'rgba(59,130,246,',   // blue-500
    'rgba(96,165,250,',   // blue-400
    'rgba(37,99,235,',    // blue-600
    'rgba(147,197,253,',  // blue-300
    'rgba(29,78,216,',    // blue-700
  ];

  /* ── Helpers ── */
  const rand  = (min, max) => Math.random() * (max - min) + min;
  const pick  = arr => arr[Math.floor(Math.random() * arr.length)];
  const lerp  = (a, b, t) => a + (b - a) * t;
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

  /* Easing for organic motion */
  const easeInOutSine = t => -(Math.cos(Math.PI * t) - 1) / 2;

  /* ── Particle factory ── */
  function spawn(atTop) {
    const size    = rand(MIN_SIZE, MAX_SIZE);
    const opacity = rand(0.15, 0.65);
    const color   = pick(COLORS);
    const angle   = rand(0, Math.PI * 2);
    const speed   = rand(BASE_SPEED * 0.4, BASE_SPEED * 1.6);
    const rotationSpeed = rand(-0.008, 0.008);

    /* spawn across the canvas, biased toward upper-left quadrant */
    let x, y;
    if (atTop) {
      // respawn at edges for continuous flow
      const edge = Math.random();
      if (edge < 0.3) { x = rand(0, W); y = -10; }
      else if (edge < 0.5) { x = -10; y = rand(0, H * 0.7); }
      else if (edge < 0.7) { x = W + 10; y = rand(0, H * 0.7); }
      else { x = rand(0, W); y = H + 10; }
    } else {
      x = rand(0, W);
      y = rand(0, H);
    }

    return {
      x, y,
      size,
      baseOpacity: opacity,
      opacity,
      color,
      angle,
      speed,
      rotation: rand(0, Math.PI),
      rotationSpeed,
      /* Perlin-like wandering */
      wander: rand(0, 1000),
      wanderSpeed: rand(0.001, 0.004),
      wanderRadius: rand(20, 60),
      /* Phase offset for sin oscillation */
      phase: rand(0, Math.PI * 2),
      phaseSpeed: rand(0.003, 0.012),
      /* life */
      life: 1,
      fadeIn: atTop ? 0 : 1,
      shape: Math.random() < 0.3 ? 'diamond' : (Math.random() < 0.5 ? 'square' : 'dot'),
    };
  }

  /* ── Init ── */
  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = window.innerWidth;
    H = window.innerHeight;
    canvas.width  = W * dpr;
    canvas.height = H * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  function init() {
    resize();
    particles = [];
    for (let i = 0; i < PARTICLE_COUNT; i++) {
      particles.push(spawn(false));
    }
  }

  /* ── Draw ── */
  function drawParticle(p) {
    ctx.save();
    ctx.globalAlpha = p.opacity * p.fadeIn;
    ctx.translate(p.x, p.y);
    ctx.rotate(p.rotation);

    ctx.fillStyle = p.color + p.opacity * p.fadeIn + ')';

    if (p.shape === 'dot') {
      ctx.beginPath();
      ctx.arc(0, 0, p.size / 2, 0, Math.PI * 2);
      ctx.fill();
    } else if (p.shape === 'square') {
      const half = p.size / 2;
      ctx.fillRect(-half, -half, p.size, p.size);
    } else {
      // diamond
      const half = p.size / 2;
      ctx.beginPath();
      ctx.moveTo(0, -half);
      ctx.lineTo(half, 0);
      ctx.lineTo(0, half);
      ctx.lineTo(-half, 0);
      ctx.closePath();
      ctx.fill();
    }
    ctx.restore();
  }

  /* ── Update loop ── */
  function update() {
    ctx.clearRect(0, 0, W, H);

    for (let i = particles.length - 1; i >= 0; i--) {
      const p = particles[i];

      /* Wander (organic drift) */
      p.wander += p.wanderSpeed;
      p.phase  += p.phaseSpeed;

      const wx = Math.cos(p.wander) * p.wanderRadius * 0.01;
      const wy = Math.sin(p.wander * 0.7 + 0.5) * p.wanderRadius * 0.01;

      /* Main drift */
      p.x += Math.cos(p.angle) * p.speed + wx;
      p.y += Math.sin(p.angle) * p.speed + wy + Math.sin(p.phase) * 0.15;
      p.rotation += p.rotationSpeed;

      /* Gentle upward bias (antigravity effect) */
      p.y -= 0.06;

      /* Fade in */
      if (p.fadeIn < 1) p.fadeIn = clamp(p.fadeIn + 0.008, 0, 1);

      /* Slight opacity shimmer */
      p.opacity = p.baseOpacity + Math.sin(p.phase * 2) * 0.08;

      /* Mouse interaction — gentle repel */
      const dx = p.x - mouse.x;
      const dy = p.y - mouse.y;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < 120) {
        const force = (1 - dist / 120) * 0.6;
        p.x += (dx / dist) * force;
        p.y += (dy / dist) * force;
      }

      /* recycle if out of bounds */
      const margin = 60;
      if (p.x < -margin || p.x > W + margin || p.y < -margin || p.y > H + margin) {
        particles[i] = spawn(true);
        continue;
      }

      drawParticle(p);
    }

    animFrame = requestAnimationFrame(update);
  }

  /* ── Events ── */
  window.addEventListener('resize', () => {
    resize();
  });

  document.addEventListener('mousemove', e => {
    mouse.x = e.clientX;
    mouse.y = e.clientY;
  });

  document.addEventListener('mouseleave', () => {
    mouse.x = -9999;
    mouse.y = -9999;
  });

  /* Pause when tab hidden */
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      cancelAnimationFrame(animFrame);
    } else {
      animFrame = requestAnimationFrame(update);
    }
  });

  /* ── Boot ── */
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => { init(); update(); });
  } else {
    init();
    update();
  }
})();
