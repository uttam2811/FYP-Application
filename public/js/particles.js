/**
 * Light Theme Particle System
 * Soft, colorful particles on white background
 */
(function () {
  'use strict';

  if (typeof THREE === 'undefined') {
    console.warn('Three.js not loaded — skipping particle animation');
    return;
  }

  // Soft, colorful palette for light theme
  const PALETTE = [
    '#0066ff', '#0066ff', '#0066ff', // Blue
    '#00d4aa', '#00d4aa',           // Cyan/Teal
    '#7c3aed', '#7c3aed',           // Purple
    '#ec4899',                       // Pink
    '#f97316',                       // Orange
    '#10b981',                       // Green
  ];

  // Configuration
  const CFG = {
    count: 250,
    magnetRadius: 14,
    ringRadius: 14,
    waveSpeed: 0.25,
    waveAmplitude: 2.0,
    particleSize: 1.3,
    lerpSpeed: 0.035,
    autoAnimate: true,
    particleVariance: 1.3,
    rotationSpeed: 0.0004,
    depthFactor: 1.4,
    pulseSpeed: 1.8,
    fieldStrength: 18,
    connectParticles: true,
    connectionDistance: 12,
    connectionOpacity: 0.1
  };

  // Container
  const container = document.createElement('div');
  container.id = 'particle-bg';
  container.style.cssText =
    'position:fixed;inset:0;z-index:-1;pointer-events:none;width:100%;height:100%;background: transparent;';
  document.body.prepend(container);

  // Scene / Camera / Renderer
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(
    45,
    window.innerWidth / window.innerHeight,
    0.1,
    1000
  );
  camera.position.z = 60;

  const renderer = new THREE.WebGLRenderer({
    alpha: true,
    antialias: true,
    powerPreference: 'high-performance'
  });
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(0x000000, 0);
  container.appendChild(renderer.domElement);

  // Geometries
  const geoSphere = new THREE.SphereGeometry(0.15, 12, 12);
  const geoRing = new THREE.RingGeometry(0.08, 0.12, 8);

  // Distribution
  const countSph = Math.floor(CFG.count * 0.7);
  const countRing = CFG.count - countSph;

  // Materials with soft blending for light theme
  const matSph = new THREE.MeshBasicMaterial({
    transparent: true,
    opacity: 0.7,
    blending: THREE.NormalBlending,
    depthWrite: false
  });
  const matRing = new THREE.MeshBasicMaterial({
    transparent: true,
    opacity: 0.5,
    blending: THREE.NormalBlending,
    depthWrite: false,
    side: THREE.DoubleSide
  });

  const meshSph = new THREE.InstancedMesh(geoSphere, matSph, countSph);
  const meshRing = new THREE.InstancedMesh(geoRing, matRing, countRing);

  scene.add(meshSph, meshRing);

  // Build mesh list
  const meshes = [];
  for (let i = 0; i < countSph; i++) meshes.push({ mesh: meshSph, idx: i, type: 'sphere' });
  for (let i = 0; i < countRing; i++) meshes.push({ mesh: meshRing, idx: i, type: 'ring' });

  // Assign per-instance colors
  const tmpColor = new THREE.Color();
  meshes.forEach(function (entry) {
    tmpColor.set(PALETTE[Math.floor(Math.random() * PALETTE.length)]);
    entry.mesh.setColorAt(entry.idx, tmpColor);
  });
  meshSph.instanceColor.needsUpdate = true;
  meshRing.instanceColor.needsUpdate = true;

  const dummy = new THREE.Object3D();

  // Viewport helper
  function getViewport() {
    const vFOV = (camera.fov * Math.PI) / 180;
    const h = 2 * Math.tan(vFOV / 2) * camera.position.z;
    return { width: h * camera.aspect, height: h };
  }

  // Mouse state
  const lastMousePos = { x: 0, y: 0 };
  let lastMouseMoveTime = 0;
  const virtualMouse = { x: 0, y: 0 };
  const pointer = { x: 0, y: 0 };

  // Particles data
  const particles = [];

  function initParticles() {
    particles.length = 0;
    const vp = getViewport();
    for (let i = 0; i < CFG.count; i++) {
      const x = (Math.random() - 0.5) * vp.width * 1.2;
      const y = (Math.random() - 0.5) * vp.height * 1.2;
      const z = (Math.random() - 0.5) * 25;
      particles.push({
        t: Math.random() * 100,
        speed: 0.005 + Math.random() / 200,
        mx: x, my: y, mz: z,
        cx: x, cy: y, cz: z,
        randomRadiusOffset: (Math.random() - 0.5) * 3,
        phase: Math.random() * Math.PI * 2,
        rotationSpeed: (Math.random() - 0.5) * 0.015,
        pulsePhase: Math.random() * Math.PI * 2
      });
    }
  }

  initParticles();

  // Connection lines
  const lineMaterial = new THREE.LineBasicMaterial({
    color: 0x0066ff,
    transparent: true,
    opacity: CFG.connectionOpacity,
    blending: THREE.NormalBlending
  });
  const lineGeometry = new THREE.BufferGeometry();
  const lines = new THREE.LineSegments(lineGeometry, lineMaterial);
  scene.add(lines);

  // Clock & loop
  const clock = new THREE.Clock();
  let animId;

  function animate() {
    animId = requestAnimationFrame(animate);

    const elapsed = clock.getElapsedTime();
    const vp = getViewport();

    // Smooth mouse target
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

    if (CFG.autoAnimate && Date.now() - lastMouseMoveTime > 3000) {
      destX = Math.sin(elapsed * 0.2) * (vp.width / 3) + Math.sin(elapsed * 0.5) * (vp.width / 8);
      destY = Math.cos(elapsed * 0.35) * (vp.height / 3) + Math.cos(elapsed * 0.7) * (vp.height / 8);
    }

    virtualMouse.x += (destX - virtualMouse.x) * 0.04;
    virtualMouse.y += (destY - virtualMouse.y) * 0.04;

    const targetX = virtualMouse.x;
    const targetY = virtualMouse.y;
    const globalRotation = elapsed * CFG.rotationSpeed;

    // Line positions for connections
    const linePositions = [];

    // Update each particle
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      const entry = meshes[i];
      p.t += p.speed;

      const projFactor = 1 - p.cz / 50;
      const ptX = targetX * projFactor;
      const ptY = targetY * projFactor;

      const dx = p.mx - ptX;
      const dy = p.my - ptY;
      const dist = Math.sqrt(dx * dx + dy * dy);

      let tpx = p.mx;
      let tpy = p.my;
      let tpz = p.mz * CFG.depthFactor;

      if (dist < CFG.magnetRadius) {
        const angle = Math.atan2(dy, dx) + globalRotation + p.phase;
        const wave = Math.sin(p.t * CFG.waveSpeed + angle) * CFG.waveAmplitude;
        const deviation = p.randomRadiusOffset * (6 / (CFG.fieldStrength + 0.1));
        const r = CFG.ringRadius + wave + deviation;

        tpx = ptX + r * Math.cos(angle);
        tpy = ptY + r * Math.sin(angle);
        tpz = p.mz * CFG.depthFactor + Math.sin(p.t) * CFG.waveAmplitude * CFG.depthFactor;
      }

      p.cx += (tpx - p.cx) * CFG.lerpSpeed;
      p.cy += (tpy - p.cy) * CFG.lerpSpeed;
      p.cz += (tpz - p.cz) * CFG.lerpSpeed;

      dummy.position.set(p.cx, p.cy, p.cz);

      // Different rotation for different shapes
      if (entry.type === 'ring') {
        dummy.lookAt(camera.position.x, camera.position.y, camera.position.z);
        dummy.rotateZ(elapsed * p.rotationSpeed);
      } else {
        dummy.rotation.x = elapsed * p.rotationSpeed * 2;
        dummy.rotation.y = elapsed * p.rotationSpeed * 3;
      }

      // Pulse effect
      const distToMouse = Math.hypot(p.cx - ptX, p.cy - ptY);
      const distFromRing = Math.abs(distToMouse - CFG.ringRadius);
      const scalePulse = Math.max(0, Math.min(1, 1 - distFromRing / 12));

      const pulseScale = 1 + Math.sin(elapsed * CFG.pulseSpeed + p.pulsePhase) * 0.2 * CFG.particleVariance;
      const finalScale = (0.8 + scalePulse * 0.3) * pulseScale * CFG.particleSize;
      dummy.scale.set(finalScale, finalScale, finalScale);

      dummy.updateMatrix();
      entry.mesh.setMatrixAt(entry.idx, dummy.matrix);

      // Connections
      if (CFG.connectParticles && i % 8 === 0) {
        for (let j = i + 1; j < particles.length; j += 8) {
          const p2 = particles[j];
          const d = Math.hypot(p.cx - p2.cx, p.cy - p2.cy, p.cz - p2.cz);
          if (d < CFG.connectionDistance) {
            linePositions.push(p.cx, p.cy, p.cz);
            linePositions.push(p2.cx, p2.cy, p2.cz);
          }
        }
      }
    }

    meshSph.instanceMatrix.needsUpdate = true;
    meshRing.instanceMatrix.needsUpdate = true;

    // Update connection lines
    if (CFG.connectParticles) {
      lineGeometry.setAttribute('position', new THREE.Float32BufferAttribute(linePositions, 3));
      lineGeometry.attributes.position.needsUpdate = true;
      lineMaterial.opacity = CFG.connectionOpacity * (0.6 + Math.sin(elapsed * 0.8) * 0.4);
    }

    // Smooth camera movement with subtle sway
    camera.position.x += (pointer.x * 2.0 - camera.position.x) * 0.006;
    camera.position.y += (pointer.y * 2.0 - camera.position.y) * 0.006;
    camera.position.x += Math.sin(elapsed * 0.15) * 0.02;
    camera.position.y += Math.cos(elapsed * 0.12) * 0.02;
    camera.lookAt(0, 0, 0);

    renderer.render(scene, camera);
  }

  // Events
  window.addEventListener('resize', function () {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
    initParticles();
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

  // Boot
  animate();

  console.log('%c FYP Power System ', 'background: linear-gradient(135deg, #0066ff, #00d4aa); color: white; font-weight: bold; padding: 10px; border-radius: 5px;');
  console.log('%c Light Theme Particle System Initialized ', 'color: #0066ff;');
})();
