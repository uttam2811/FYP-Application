/**
 * Futuristic 3D Effects and Animations
 * Cyberpunk-inspired interactions and visual effects
 */

(function() {
  'use strict';

  // ============================================================
  // LOADING SCREEN
  // ============================================================
  function initLoadingScreen() {
    const existingScreen = document.getElementById('loadingScreen');
    if (existingScreen) return;
    
    const loadingScreen = document.createElement('div');
    loadingScreen.className = 'loading-screen';
    loadingScreen.id = 'loadingScreen';
    loadingScreen.innerHTML = `
      <div class="loading-logo">FYP SYSTEM</div>
      <div class="loading-bar"></div>
      <div class="loading-text">INITIALIZING SYSTEM...</div>
    `;
    document.body.appendChild(loadingScreen);

    const loadingText = loadingScreen.querySelector('.loading-text');
    const messages = ['LOADING MODULES...', 'CONNECTING SERVICES...', 'READY'];
    let msgIdx = 0;
    
    const msgInterval = setInterval(() => {
      if (msgIdx < messages.length) {
        loadingText.textContent = messages[msgIdx];
        msgIdx++;
      } else {
        clearInterval(msgInterval);
      }
    }, 700);

    setTimeout(() => {
      clearInterval(msgInterval);
      loadingScreen.classList.add('hidden');
      setTimeout(() => loadingScreen.remove(), 800);
    }, 2500);
  }

  // ============================================================
  // 3D TILT EFFECT
  // ============================================================
  function initTiltEffect() {
    const tiltCards = document.querySelectorAll('[data-tilt]');

    tiltCards.forEach(card => {
      card.addEventListener('mousemove', handleTilt);
      card.addEventListener('mouseleave', resetTilt);
      card.addEventListener('mouseenter', addShine);
    });

    function handleTilt(e) {
      const card = e.currentTarget;
      const rect = card.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const centerX = rect.width / 2;
      const centerY = rect.height / 2;

      const rotateX = ((y - centerY) / 12).toFixed(2);
      const rotateY = ((centerX - x) / 12).toFixed(2);

      card.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) translateZ(20px)`;
      card.style.transition = 'transform 0.1s ease-out';

      // Update shine effect
      const shine = card.querySelector('.tilt-card-shine');
      if (shine) {
        const percentX = (x / rect.width) * 100;
        const percentY = (y / rect.height) * 100;
        shine.style.background = `radial-gradient(circle at ${percentX}% ${percentY}%, rgba(255,255,255,0.25) 0%, rgba(255,255,255,0.05) 40%, transparent 60%)`;
        shine.style.opacity = '1';
      }
    }

    function resetTilt(e) {
      const card = e.currentTarget;
      card.style.transform = 'perspective(1000px) rotateX(0) rotateY(0) translateZ(0)';
      card.style.transition = 'transform 0.5s cubic-bezier(0.34, 1.56, 0.64, 1)';
      const shine = card.querySelector('.tilt-card-shine');
      if (shine) shine.style.opacity = '0';
    }

    function addShine(e) {
      const card = e.currentTarget;
      if (!card.querySelector('.tilt-card-shine')) {
        const shine = document.createElement('div');
        shine.className = 'tilt-card-shine';
        card.appendChild(shine);
      }
    }
  }

  // ============================================================
  // MAGNETIC BUTTONS
  // ============================================================
  function initMagneticButtons() {
    const magneticButtons = document.querySelectorAll('[data-magnetic]');

    magneticButtons.forEach(button => {
      button.addEventListener('mousemove', handleMagnetic);
      button.addEventListener('mouseleave', resetMagnetic);
    });

    function handleMagnetic(e) {
      const button = e.currentTarget;
      const rect = button.getBoundingClientRect();
      const x = e.clientX - rect.left - rect.width / 2;
      const y = e.clientY - rect.top - rect.height / 2;

      button.style.transform = `translate(${x * 0.3}px, ${y * 0.3}px)`;
    }

    function resetMagnetic(e) {
      const button = e.currentTarget;
      button.style.transform = 'translate(0, 0)';
    }
  }

  // ============================================================
  // TEXT SCRAMBLE EFFECT
  // ============================================================
  class TextScramble {
    constructor(el) {
      this.el = el;
      this.chars = '!<>-_\\/[]{}—=+*^?#________';
      this.update = this.update.bind(this);
    }

    setText(newText) {
      const oldText = this.el.innerText;
      const length = Math.max(oldText.length, newText.length);
      const promise = new Promise(resolve => this.resolve = resolve);

      this.queue = [];
      for (let i = 0; i < length; i++) {
        const from = oldText[i] || '';
        const to = newText[i] || '';
        const start = Math.floor(Math.random() * 40);
        const end = start + Math.floor(Math.random() * 40);
        this.queue.push({ from, to, start, end });
      }

      cancelAnimationFrame(this.frameRequest);
      this.frame = 0;
      this.update();
      return promise;
    }

    update() {
      let output = '';
      let complete = 0;

      for (let i = 0, n = this.queue.length; i < n; i++) {
        let { from, to, start, end, char } = this.queue[i];

        if (this.frame >= end) {
          complete++;
          output += to;
        } else if (this.frame >= start) {
          if (!char || Math.random() < 0.28) {
            char = this.randomChar();
            this.queue[i].char = char;
          }
          output += `<span style="color: var(--neon-cyan)">${char}</span>`;
        } else {
          output += from;
        }
      }

      this.el.innerHTML = output;

      if (complete === this.queue.length) {
        this.resolve();
      } else {
        this.frameRequest = requestAnimationFrame(this.update);
        this.frame++;
      }
    }

    randomChar() {
      return this.chars[Math.floor(Math.random() * this.chars.length)];
    }
  }

  function initTextScramble() {
    const elements = document.querySelectorAll('[data-scramble]');
    elements.forEach(el => {
      const fx = new TextScramble(el);
      let counter = 0;
      const phrases = el.dataset.scramble.split('|');

      const next = () => {
        fx.setText(phrases[counter]).then(() => {
          setTimeout(next, 2000);
        });
        counter = (counter + 1) % phrases.length;
      };

      next();
    });
  }

  // ============================================================
  // PARALLAX EFFECT
  // ============================================================
  function initParallax() {
    const parallaxElements = document.querySelectorAll('[data-parallax]');

    window.addEventListener('scroll', () => {
      const scrollY = window.scrollY;

      parallaxElements.forEach(el => {
        const speed = el.dataset.parallax || 0.5;
        el.style.transform = `translateY(${scrollY * speed}px)`;
      });
    });
  }

  // ============================================================
  // INTERSECTION OBSERVER ANIMATIONS
  // ============================================================
  function initScrollAnimations() {
    const observerOptions = {
      threshold: 0.1,
      rootMargin: '0px 0px -50px 0px'
    };

    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.style.animationPlayState = 'running';
          entry.target.classList.add('animate-in');
        }
      });
    }, observerOptions);

    const animatedElements = document.querySelectorAll('[data-animate]');
    animatedElements.forEach(el => {
      el.style.animationPlayState = 'paused';
      observer.observe(el);
    });
  }

  // ============================================================
  // NEON FLICKER EFFECT
  // ============================================================
  function initNeonFlicker() {
    const neonElements = document.querySelectorAll('[data-neon]');

    neonElements.forEach(el => {
      el.style.animation = `glitch ${2 + Math.random() * 3}s infinite`;
    });
  }

  // ============================================================
  // SMOOTH PAGE TRANSITIONS
  // ============================================================
  function initPageTransitions() {
    document.querySelectorAll('a[href^="/"]').forEach(link => {
      link.addEventListener('click', handleTransition);
    });

    function handleTransition(e) {
      const href = e.currentTarget.getAttribute('href');
      if (href.startsWith('/')) {
        e.preventDefault();

        const overlay = document.createElement('div');
        overlay.style.cssText = `
          position: fixed;
          inset: 0;
          background: var(--bg-primary);
          z-index: 9999;
          transform: scaleX(0);
          transform-origin: left;
          transition: transform 0.5s cubic-bezier(0.16, 1, 0.3, 1);
        `;
        document.body.appendChild(overlay);

        requestAnimationFrame(() => {
          overlay.style.transform = 'scaleX(1)';
          overlay.style.transformOrigin = 'left';
        });

        setTimeout(() => {
          window.location.href = href;
        }, 500);
      }
    }
  }

  // ============================================================
  // CUSTOM CURSOR
  // ============================================================
  function initCustomCursor() {
    if (window.matchMedia('(pointer: coarse)').matches) return;

    const cursor = document.createElement('div');
    cursor.className = 'custom-cursor';
    cursor.style.cssText = `
      position: fixed;
      width: 20px;
      height: 20px;
      border: 2px solid var(--neon-cyan);
      border-radius: 50%;
      pointer-events: none;
      z-index: 9999;
      transition: transform 0.15s ease, width 0.15s ease, height 0.15s ease;
      mix-blend-mode: difference;
    `;

    const cursorDot = document.createElement('div');
    cursorDot.className = 'custom-cursor-dot';
    cursorDot.style.cssText = `
      position: fixed;
      width: 4px;
      height: 4px;
      background: var(--neon-cyan);
      border-radius: 50%;
      pointer-events: none;
      z-index: 9999;
    `;

    document.body.appendChild(cursor);
    document.body.appendChild(cursorDot);

    let mouseX = 0, mouseY = 0;
    let cursorX = 0, cursorY = 0;
    let dotX = 0, dotY = 0;

    document.addEventListener('mousemove', (e) => {
      mouseX = e.clientX;
      mouseY = e.clientY;
    });

    // Hover effects
    document.querySelectorAll('button, a, [data-hover]').forEach(el => {
      el.addEventListener('mouseenter', () => {
        cursor.style.transform = 'scale(2)';
        cursor.style.borderColor = 'var(--neon-pink)';
      });
      el.addEventListener('mouseleave', () => {
        cursor.style.transform = 'scale(1)';
        cursor.style.borderColor = 'var(--neon-cyan)';
      });
    });

    function animateCursor() {
      cursorX += (mouseX - cursorX) * 0.15;
      cursorY += (mouseY - cursorY) * 0.15;
      dotX += (mouseX - dotX) * 0.5;
      dotY += (mouseY - dotY) * 0.5;

      cursor.style.left = cursorX - 10 + 'px';
      cursor.style.top = cursorY - 10 + 'px';
      cursorDot.style.left = dotX - 2 + 'px';
      cursorDot.style.top = dotY - 2 + 'px';

      requestAnimationFrame(animateCursor);
    }

    animateCursor();
  }

  // ============================================================
  // BACKGROUND GRID ANIMATION
  // ============================================================
  function initGridBackground() {
    const grid = document.createElement('div');
    grid.className = 'grid-bg';
    document.body.appendChild(grid);

    // Animate grid lines smoothly
    let offset = 0;
    function animateGrid() {
      offset += 0.3;
      grid.style.backgroundPosition = `${offset}px ${offset}px`;
      requestAnimationFrame(animateGrid);
    }
    animateGrid();
  }

  // ============================================================
  // RIPPLE EFFECT ON BUTTONS
  // ============================================================
  function initRippleButtons() {
    document.addEventListener('click', function(e) {
      const btn = e.target.closest('.button-submit, .btn-primary, .btn');
      if (!btn) return;

      const ripple = document.createElement('span');
      const rect = btn.getBoundingClientRect();
      const size = Math.max(rect.width, rect.height);
      
      ripple.style.cssText = `
        position: absolute;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.3);
        width: ${size}px;
        height: ${size}px;
        left: ${e.clientX - rect.left - size/2}px;
        top: ${e.clientY - rect.top - size/2}px;
        transform: scale(0);
        animation: rippleEffect 0.6s ease-out;
        pointer-events: none;
      `;
      
      btn.style.position = 'relative';
      btn.style.overflow = 'hidden';
      btn.appendChild(ripple);
      setTimeout(() => ripple.remove(), 600);
    });

    // Add CSS for ripple
    const style = document.createElement('style');
    style.textContent = `
      @keyframes rippleEffect {
        0% { transform: scale(0); opacity: 0.6; }
        100% { transform: scale(4); opacity: 0; }
      }
    `;
    document.head.appendChild(style);
  }

  // ============================================================
  // SMOOTH REVEAL ON SCROLL
  // ============================================================
  function initScrollReveal() {
    const style = document.createElement('style');
    style.textContent = `
      .reveal-ready {
        opacity: 0;
        transform: translateY(30px);
        transition: opacity 0.6s cubic-bezier(0.16, 1, 0.3, 1), transform 0.6s cubic-bezier(0.16, 1, 0.3, 1);
      }
      .reveal-visible {
        opacity: 1;
        transform: translateY(0);
      }
    `;
    document.head.appendChild(style);

    const elements = document.querySelectorAll('.stat-card, .card, .stat-card-3d, .section-card');
    elements.forEach((el, index) => {
      el.classList.add('reveal-ready');
      el.style.transitionDelay = `${index * 0.08}s`;
    });

    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('reveal-visible');
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.1, rootMargin: '0px 0px -30px 0px' });

    elements.forEach(el => observer.observe(el));
  }

  // ============================================================
  // STATS COUNTER ANIMATION
  // ============================================================
  function initStatsCounter() {
    const stats = document.querySelectorAll('[data-count]');

    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          animateCounter(entry.target);
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.5 });

    stats.forEach(stat => observer.observe(stat));

    function animateCounter(el) {
      const target = parseInt(el.dataset.count);
      const duration = 2000;
      const step = target / (duration / 16);
      let current = 0;

      const update = () => {
        current += step;
        if (current < target) {
          el.textContent = Math.floor(current);
          requestAnimationFrame(update);
        } else {
          el.textContent = target;
        }
      };

      update();
    }
  }

  // ============================================================
  // SIDEBAR HOVER EXPAND
  // ============================================================
  function initSidebarHover() {
    const sidebar = document.querySelector('.sidebar-futuristic');
    if (!sidebar) return;

    let timeout;
    sidebar.addEventListener('mouseenter', () => {
      clearTimeout(timeout);
      sidebar.classList.remove('collapsed');
    });

    sidebar.addEventListener('mouseleave', () => {
      timeout = setTimeout(() => {
        sidebar.classList.add('collapsed');
      }, 300);
    });
  }

  // ============================================================
  // AUDIO FEEDBACK (Optional - subtle UI sounds)
  // ============================================================
  function initAudioFeedback() {
    // Simple beep using Web Audio API
    const audioContext = new (window.AudioContext || window.webkitAudioContext)();

    function playHoverSound() {
      if (audioContext.state === 'suspended') audioContext.resume();

      const oscillator = audioContext.createOscillator();
      const gainNode = audioContext.createGain();

      oscillator.connect(gainNode);
      gainNode.connect(audioContext.destination);

      oscillator.frequency.value = 800;
      oscillator.type = 'sine';
      gainNode.gain.setValueAtTime(0.05, audioContext.currentTime);
      gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.1);

      oscillator.start(audioContext.currentTime);
      oscillator.stop(audioContext.currentTime + 0.1);
    }

    // Add subtle hover sounds to interactive elements
    document.querySelectorAll('.btn-futuristic, .nav-item-futuristic').forEach(el => {
      el.addEventListener('mouseenter', playHoverSound);
    });
  }

  // ============================================================
  // TYPEWRITER EFFECT
  // ============================================================
  function initTypewriter() {
    const typewriters = document.querySelectorAll('[data-typewriter]');

    typewriters.forEach(el => {
      const text = el.dataset.typewriter;
      let i = 0;
      el.textContent = '';

      function type() {
        if (i < text.length) {
          el.textContent += text.charAt(i);
          i++;
          setTimeout(type, 50 + Math.random() * 50);
        }
      }

      // Start when element is in view
      const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            type();
            observer.disconnect();
          }
        });
      });

      observer.observe(el);
    });
  }

  // ============================================================
  // CORNER DECORATIONS
  // ============================================================
  function initCornerDecorations() {
    const corners = ['top-left', 'top-right', 'bottom-left', 'bottom-right'];

    corners.forEach(position => {
      const decoration = document.createElement('div');
      decoration.className = `corner-decoration ${position}`;
      document.body.appendChild(decoration);
    });
  }

  // ============================================================
  // HOLOGRAPHIC CARD EFFECT
  // ============================================================
  function initHolographicCards() {
    const cards = document.querySelectorAll('.holographic');

    cards.forEach(card => {
      card.addEventListener('mousemove', (e) => {
        const rect = card.getBoundingClientRect();
        const x = ((e.clientX - rect.left) / rect.width) * 100;
        const y = ((e.clientY - rect.top) / rect.height) * 100;

        card.style.setProperty('--mouse-x', `${x}%`);
        card.style.setProperty('--mouse-y', `${y}%`);
      });
    });
  }

  // ============================================================
  // INITIALIZE ALL EFFECTS
  // ============================================================
  function init() {
    initLoadingScreen();

    // Wait for DOM to be ready
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', onReady);
    } else {
      onReady();
    }

    function onReady() {
      initTiltEffect();
      initMagneticButtons();
      initTextScramble();
      initParallax();
      initScrollAnimations();
      initNeonFlicker();
      initGridBackground();
      initStatsCounter();
      initSidebarHover();
      initTypewriter();
      initCornerDecorations();
      initHolographicCards();
      initRippleButtons();
      initScrollReveal();

      // Optional effects
      // initCustomCursor();
      // initAudioFeedback();
    }
  }

  // Start initialization
  init();

})();
