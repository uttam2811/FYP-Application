/**
 * Antigravity background — multicolor particles (antigravity.google style)
 * Vanilla Three.js — per-instance colors, ring formation around cursor
 */
(function () {
  'use strict';

  if (typeof THREE === 'undefined') {
    console.warn('Three.js not loaded — skipping Antigravity animation');
    return;
  }

  /* ═══════ Multicolor palette (antigravity.google) ═══════ */
  const PALETTE = [
    '#4285F4', '#4285F4', '#4285F4',           // Google blue (weighted)
    '#EA4335', '#EA4335',                        // Google red
    '#FBBC04', '#FBBC04',                        // Google yellow
    '#34A853', '#34A853',                        // Google green
    '#1a73e8', '#1967d2', '#185abc',             // deeper blues
    '#7c3aed', '#8b5cf6', '#a855f7',            // violet/purple
    '#ec4899', '#f472b6',                        // pink
    '#f97316', '#fb923c',                        // orange
    '#14b8a6', '#0d9488',                        // teal
    '#0ea5e9',                                   // sky
  ];

  /* ═══════ Config ═══════ */
  const CFG = {
    count: 400,
    magnetRadius: 8,
    ringRadius: 8,
    waveSpeed: 0.4,
    waveAmplitude: 1.2,
    particleSize: 1.6,
    lerpSpeed: 0.05,
    autoAnimate: true,
    particleVariance: 1,
    rotationSpeed: 0,
    depthFactor: 1,
    pulseSpeed: 3,
    fieldStrength: 10
  };

  /* ═══════ Container ═══════ */
  const container = document.createElement('div');
  container.id = 'antigravity-bg';
  container.style.cssText =
    'position:fixed;inset:0;z-index:0;pointer-events:none;width:100%;height:100%;';
  document.body.prepend(container);

  /* ═══════ Scene / Camera / Renderer ═══════ */
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(
    35,
    window.innerWidth / window.innerHeight,
    0.1,
    1000
  );
  camera.position.z = 50;

  const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true });
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(0x000000, 0);
  container.appendChild(renderer.domElement);

  /* ═══════ Mixed geometries for variety ═══════ */
  const geoCapsule = new THREE.CapsuleGeometry(0.08, 0.35, 4, 8);
  const geoSphere  = new THREE.SphereGeometry(0.15, 12, 12);
  const geoBox     = new THREE.BoxGeometry(0.22, 0.22, 0.22);

  /* We use separate InstancedMesh per shape for true variety */
  const countCap = Math.floor(CFG.count * 0.5);
  const countSph = Math.floor(CFG.count * 0.3);
  const countBox = CFG.count - countCap - countSph;

  const matCap = new THREE.MeshBasicMaterial();
  const matSph = new THREE.MeshBasicMaterial();
  const matBox = new THREE.MeshBasicMaterial();

  const meshCap = new THREE.InstancedMesh(geoCapsule, matCap, countCap);
  const meshSph = new THREE.InstancedMesh(geoSphere, matSph, countSph);
  const meshBox = new THREE.InstancedMesh(geoBox, matBox, countBox);

  scene.add(meshCap, meshSph, meshBox);

  /* Build flat list so animation loop is simple */
  const meshes = [];
  for (let i = 0; i < countCap; i++) meshes.push({ mesh: meshCap, idx: i });
  for (let i = 0; i < countSph; i++) meshes.push({ mesh: meshSph, idx: i });
  for (let i = 0; i < countBox; i++) meshes.push({ mesh: meshBox, idx: i });

  /* Assign per-instance colors */
  const tmpColor = new THREE.Color();
  meshes.forEach(function (entry) {
    tmpColor.set(PALETTE[Math.floor(Math.random() * PALETTE.length)]);
    entry.mesh.setColorAt(entry.idx, tmpColor);
  });
  meshCap.instanceColor.needsUpdate = true;
  meshSph.instanceColor.needsUpdate = true;
  meshBox.instanceColor.needsUpdate = true;

  const dummy = new THREE.Object3D();

  /* ═══════ Viewport helper ═══════ */
  function getViewport() {
    const vFOV = (camera.fov * Math.PI) / 180;
    const h = 2 * Math.tan(vFOV / 2) * camera.position.z;
    return { width: h * camera.aspect, height: h };
  }

  /* ═══════ Mouse state ═══════ */
  const lastMousePos = { x: 0, y: 0 };
  let lastMouseMoveTime = 0;
  const virtualMouse = { x: 0, y: 0 };
  const pointer = { x: 0, y: 0 };

  /* ═══════ Particles data ═══════ */
  const particles = [];

  function initParticles() {
    particles.length = 0;
    const vp = getViewport();
    for (let i = 0; i < CFG.count; i++) {
      const x = (Math.random() - 0.5) * vp.width;
      const y = (Math.random() - 0.5) * vp.height;
      const z = (Math.random() - 0.5) * 20;
      particles.push({
        t: Math.random() * 100,
        speed: 0.01 + Math.random() / 200,
        mx: x, my: y, mz: z,
        cx: x, cy: y, cz: z,
        randomRadiusOffset: (Math.random() - 0.5) * 2
      });
    }
  }

  initParticles();

  /* ═══════ Clock & loop ═══════ */
  const clock = new THREE.Clock();
  let animId;

  function animate() {
    animId = requestAnimationFrame(animate);

    const elapsed = clock.getElapsedTime();
    const vp = getViewport();

    /* ── Smooth mouse target ── */
    const mouseDist = Math.hypot(
      pointer.x - lastMousePos.x,
      pointer.y - lastMousePos.y
    );
    if (mouseDist > 0.001) {
      lastMouseMoveTime = Date.now();
      lastMousePos.x = pointer.x;
      lastMousePos.y = pointer.y;
    }

    let destX = (pointer.x * vp.width) / 2;
    let destY = (pointer.y * vp.height) / 2;

    if (CFG.autoAnimate && Date.now() - lastMouseMoveTime > 2000) {
      destX = Math.sin(elapsed * 0.5) * (vp.width / 4);
      destY = Math.cos(elapsed) * (vp.height / 4);
    }

    virtualMouse.x += (destX - virtualMouse.x) * 0.05;
    virtualMouse.y += (destY - virtualMouse.y) * 0.05;

    const targetX = virtualMouse.x;
    const targetY = virtualMouse.y;
    const globalRotation = elapsed * CFG.rotationSpeed;

    /* ── Update each particle ── */
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      const entry = meshes[i];
      p.t += p.speed / 2;

      const projFactor = 1 - p.cz / 50;
      const ptX = targetX * projFactor;
      const ptY = targetY * projFactor;

      const dx = p.mx - ptX;
      const dy = p.my - ptY;
      const dist = Math.sqrt(dx * dx + dy * dy);

      var tpx = p.mx;
      var tpy = p.my;
      var tpz = p.mz * CFG.depthFactor;

      if (dist < CFG.magnetRadius) {
        const angle = Math.atan2(dy, dx) + globalRotation;
        const wave =
          Math.sin(p.t * CFG.waveSpeed + angle) * 0.5 * CFG.waveAmplitude;
        const deviation =
          p.randomRadiusOffset * (5 / (CFG.fieldStrength + 0.1));
        const r = CFG.ringRadius + wave + deviation;

        tpx = ptX + r * Math.cos(angle);
        tpy = ptY + r * Math.sin(angle);
        tpz =
          p.mz * CFG.depthFactor +
          Math.sin(p.t) * CFG.waveAmplitude * CFG.depthFactor;
      }

      p.cx += (tpx - p.cx) * CFG.lerpSpeed;
      p.cy += (tpy - p.cy) * CFG.lerpSpeed;
      p.cz += (tpz - p.cz) * CFG.lerpSpeed;

      dummy.position.set(p.cx, p.cy, p.cz);
      dummy.lookAt(ptX, ptY, p.cz);
      dummy.rotateX(Math.PI / 2);

      const distToMouse = Math.hypot(p.cx - ptX, p.cy - ptY);
      const distFromRing = Math.abs(distToMouse - CFG.ringRadius);
      var sf = Math.max(0, Math.min(1, 1 - distFromRing / 10));

      const finalScale =
        sf *
        (0.8 + Math.sin(p.t * CFG.pulseSpeed) * 0.2 * CFG.particleVariance) *
        CFG.particleSize;
      dummy.scale.set(finalScale, finalScale, finalScale);

      dummy.updateMatrix();
      entry.mesh.setMatrixAt(entry.idx, dummy.matrix);
    }

    meshCap.instanceMatrix.needsUpdate = true;
    meshSph.instanceMatrix.needsUpdate = true;
    meshBox.instanceMatrix.needsUpdate = true;
    renderer.render(scene, camera);
  }

  /* ═══════ Events ═══════ */
  window.addEventListener('resize', function () {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
  });

  document.addEventListener('mousemove', function (e) {
    pointer.x = (e.clientX / window.innerWidth) * 2 - 1;
    pointer.y = -(e.clientY / window.innerHeight) * 2 + 1;
  });

  document.addEventListener('visibilitychange', function () {
    if (document.hidden) {
      cancelAnimationFrame(animId);
      clock.stop();
    } else {
      clock.start();
      animId = requestAnimationFrame(animate);
    }
  });

  /* ═══════ Boot ═══════ */
  animate();
})();
