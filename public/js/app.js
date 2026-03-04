// ===== Global API helper & auth utilities =====
const API = {
  async request(url, options = {}) {
    const defaults = {
      headers: { 'Content-Type': 'application/json' },
      credentials: 'same-origin'
    };
    const config = { ...defaults, ...options };
    if (options.body && typeof options.body === 'object') {
      config.body = JSON.stringify(options.body);
    }
    const res = await fetch(url, config);
    const data = await res.json();
    if (!res.ok) {
      throw new Error(data.error || `Request failed (${res.status})`);
    }
    return data;
  },

  get(url) { return this.request(url); },

  post(url, body) {
    return this.request(url, { method: 'POST', body });
  },

  delete(url) {
    return this.request(url, { method: 'DELETE' });
  },

  patch(url, body) {
    return this.request(url, { method: 'PATCH', body });
  }
};

// ===== Auth =====
const Auth = {
  user: null,

  async check() {
    try {
      const data = await API.get('/api/auth/me');
      this.user = data.user;
      return data.user;
    } catch {
      return null;
    }
  },

  async login(username, password) {
    const data = await API.post('/api/auth/login', { username, password });
    this.user = data.user;
    return data.user;
  },

  async logout() {
    await API.post('/api/auth/logout');
    this.user = null;
    window.location.href = '/login';
  },

  isAdmin() {
    return this.user && this.user.role === 'admin';
  },

  requireAuth() {
    if (!this.user) {
      window.location.href = '/login';
      return false;
    }
    return true;
  }
};

// ===== Toast Notifications =====
function showToast(message, type = 'info') {
  let container = document.querySelector('.toast-container');
  if (!container) {
    container = document.createElement('div');
    container.className = 'toast-container';
    document.body.appendChild(container);
  }

  const icons = { success: '✓', error: '✕', info: 'ℹ' };
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.innerHTML = `<span>${icons[type] || 'ℹ'}</span> ${message}`;
  container.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateX(40px) scale(0.96)';
    toast.style.transition = 'opacity 0.35s cubic-bezier(0.4, 0, 0.2, 1), transform 0.35s cubic-bezier(0.16, 1, 0.3, 1)';
    setTimeout(() => toast.remove(), 380);
  }, 4000);
}

// ===== Time formatting =====
function timeAgo(dateStr) {
  const now = new Date();
  const date = new Date(dateStr);
  const seconds = Math.floor((now - date) / 1000);

  if (seconds < 5) return 'just now';
  if (seconds < 60) return `${seconds}s ago`;
  const mins = Math.floor(seconds / 60);
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

function formatDateTime(dateStr) {
  return new Date(dateStr).toLocaleString();
}

// ===== Data display formatting =====
function formatSimData(data) {
  if (typeof data === 'string') return data;
  if (data.headers && data.rows) {
    // CSV table format
    let html = '<table style="width:100%;font-size:0.8rem;"><thead><tr>';
    data.headers.forEach(h => html += `<th style="padding:4px 8px;">${h}</th>`);
    html += '</tr></thead><tbody>';
    const displayRows = data.rows.slice(0, 20);
    displayRows.forEach(row => {
      html += '<tr>';
      data.headers.forEach(h => html += `<td style="padding:4px 8px;">${row[h] ?? ''}</td>`);
      html += '</tr>';
    });
    html += '</tbody></table>';
    if (data.rows.length > 20) {
      html += `<div style="padding:8px;color:var(--text-muted);font-size:0.78rem;">... and ${data.rows.length - 20} more rows</div>`;
    }
    return html;
  }
  if (data.text) {
    return `<pre>${data.text}</pre>`;
  }
  return `<pre>${JSON.stringify(data, null, 2)}</pre>`;
}
